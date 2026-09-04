// BIXOLON G30 Windows 전송 경로 실기 프로브.
//
// 앱 전체를 빌드하지 않고 **가장 위험한 가정 하나**만 검증한다:
//   "G30 은 usbprint devnode 로 ESC/POS 래스터(GS v 0)를 그대로 받는가?"
//
// 앱과 **같은 인코더**(`g30_escpos_raster.dart`)와 **같은 전송 방식**
// (SetupAPI 열거 → CreateFile → WriteFile, 스풀러 미경유)을 쓰므로, 여기서
// 제대로 나오면 앱 경로도 나온다. 여기서 백지/깨짐이면 ESC/POS 가정이 틀린
// 것이고 BXLPAPI FFI 백엔드로 전환해야 한다.
//
// 실행:
//   dart run tool/g30_windows_probe.dart           # 장치 목록만 출력 (인쇄 안 함)
//   dart run tool/g30_windows_probe.dart --print    # 테스트 패턴 1장 인쇄
//   dart run tool/g30_windows_probe.dart --status   # DLE EOT 실시간 상태 조회
//
// `--status` 는 두 번째 가정을 검증한다: "G30 이 usbprint 로 상태를 되돌려주는가?"
// PR800 은 DLE EOT 에 응답하지 않는 전례가 있어(`com_port_print_service.dart`)
// 가정하면 안 된다. 정상 / 커버 열림 / 용지 제거 세 상태에서 각각 돌려 비트가
// 실제로 바뀌는지 확인한다. 무응답이면 Windows 복구대기 게이트는 구현 불가다.
//
// standalone Dart VM 에서 돈다 — Flutter 엔진(`dart:ui`)을 쓰지 않으려고
// 인코더를 순수 파일로 분리해 둔 것이 여기서 값을 한다.

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import 'package:appfit_order_agent/services/label_printer/label_printer_models.dart';
import 'package:appfit_order_agent/services/label_printer/windows/escpos_realtime_status.dart';
import 'package:appfit_order_agent/services/label_printer/windows/g30_escpos_raster.dart';
import 'package:appfit_order_agent/services/usb_print_descriptor.dart';

/// `GUID_DEVINTERFACE_USBPRINT` — usbprint.sys 가 노출하는 장치 인터페이스.
const String _guidUsbPrint = '{28D78FAD-5A12-11D1-AE5B-0000F803A8C2}';

/// G30 58mm 연속용지의 실효 인쇄폭(실측 420dot 에서 8dot 여유).
/// `LabelMediaSpec.continuous58.widthDots` 와 같은 값이다.
const int _widthDots = 412;

void main(List<String> args) {
  if (!Platform.isWindows) {
    stderr.writeln('Windows 전용 프로브입니다.');
    exit(2);
  }

  final devices = _enumerateUsbPrint();
  stdout.writeln('usbprint 장치 ${devices.length}건:');
  for (final d in devices) {
    final mark = _isG30(d) ? '  <-- G30' : '';
    stdout.writeln('  ${d.displayLabel}$mark');
    stdout.writeln('      ${d.devicePath}');
  }

  final g30 = devices.where(_isG30).firstOrNull;
  if (g30 == null) {
    stderr.writeln('\nG30(VID ${_hex(kBixolonVendorId)}) 을 찾지 못했습니다. '
        '전원/케이블을 확인하세요.');
    exit(1);
  }

  if (args.contains('--status')) {
    _runStatusProbe(g30.devicePath);
    return;
  }

  if (!args.contains('--print')) {
    stdout.writeln('\nG30 검출됨.');
    stdout.writeln('  --print   테스트 패턴 1장 인쇄');
    stdout.writeln('  --status  DLE EOT 실시간 상태 조회');
    return;
  }

  final bytes = encodeG30RasterFromRgba(
    rgba: _testPattern(_widthDots, 320),
    width: _widthDots,
    height: 320,
  );
  stdout.writeln('\n테스트 패턴 ${bytes.length} bytes 전송 중...');

  final r = _write(g30.devicePath, bytes);
  if (r == null) {
    stdout.writeln('전송 성공. 용지를 확인하세요.');
    stdout.writeln('  기대: 테두리 사각형 + 대각선 + 하단 검정 바 + partial cut');
    stdout.writeln('  백지/깨진 문자면 ESC/POS 가정이 틀린 것 → BXLPAPI 로 전환');
  } else {
    stderr.writeln('전송 실패: $r');
    exit(1);
  }
}

// ---------------------------------------------------------------------------
// DLE EOT 실시간 상태 프로브
// ---------------------------------------------------------------------------

void _runStatusProbe(String devicePath) {
  // ── 먼저 인터페이스가 양방향인지 확정한다 ────────────────────────────────
  // USB 프린터 클래스의 bInterfaceProtocol:
  //   Prot_01 = 단방향(IN 엔드포인트 없음 → 읽기 영원히 불가)
  //   Prot_02 = 양방향, Prot_03 = IEEE 1284.4
  // Windows 가 이걸 호환 ID 로 노출하므로 물리 조작 없이 판정할 수 있다.
  stdout.writeln('\nUSB 프린터 인터페이스 호환 ID:');
  final ids = _compatibleIds(devicePath);
  if (ids.isEmpty) {
    stdout.writeln('  (읽지 못함)');
  } else {
    for (final id in ids) {
      final note = id.toUpperCase().contains('PROT_01')
          ? '   ← 단방향: IN 엔드포인트 없음 = 상태 조회 불가'
          : (id.toUpperCase().contains('PROT_02')
              ? '   ← 양방향: 상태 조회 가능'
              : '');
      stdout.writeln('  $id$note');
    }
  }

  stdout.writeln('\nDLE EOT 실시간 상태 조회 (타임아웃 1000ms)');
  stdout.writeln('  응답 고정 비트: bit0=0 bit1=1 bit4=1 bit7=0  (b & 0x93 == 0x12)\n');

  const names = {
    kDleEotPrinter: 'n=1 프린터',
    kDleEotOffline: 'n=2 오프라인원인',
    kDleEotError: 'n=3 에러',
    kDleEotPaper: 'n=4 용지센서',
  };

  // 핸들을 한 번만 열고 4개 질의를 이어서 한다. 질의마다 open/close 하면
  // 첫 질의 외에는 0바이트가 돌아오는 것이 실측됐다(2026-09-03).
  final session = _StatusSession.open(devicePath);
  if (session == null) {
    stdout.writeln('  핸들 열기 실패 — 다른 프로세스가 점유 중일 수 있음');
    return;
  }
  // 안정성이 핵심이다 — 한 번 답했다고 쓸 수 있는 게 아니다. 각 질의를 여러 번
  // 반복해 **같은 값이 재현되는지** 본다. 값이 흔들리면 그 신호로 무한 대기를
  // 걸 수 없다.
  const rounds = 5;
  final ok = <int, int>{};
  final vals = <int, Set<int>>{};
  try {
    for (var round = 1; round <= rounds; round++) {
      for (final n in [
        kDleEotPrinter,
        kDleEotOffline,
        kDleEotError,
        kDleEotPaper,
      ]) {
        final r = session.query(n);
        final label = names[n]!.padRight(14);
        final drain = r.drained > 0 ? ' [잔여 ${r.drained}바이트 버림]' : '';
        if (r.error != null) {
          stdout.writeln('  #$round $label  무응답 — ${r.error}$drain');
          continue;
        }
        ok[n] = (ok[n] ?? 0) + 1;
        final b = r.byte!;
        (vals[n] ??= <int>{}).add(b);
        final bin = b.toRadixString(2).padLeft(8, '0');
        final valid = isValidStatusByte(b);
        final hex = '0x${b.toRadixString(16).padLeft(2, '0').toUpperCase()}';
        stdout.write(
            '  #$round $label  $hex  0b$bin  ${valid ? "유효" : "★고정비트 불일치"}');
        if (valid && n == kDleEotOffline) {
          stdout.write('  → ${decodeOfflineStatus(b)}');
        } else if (valid && n == kDleEotPaper) {
          stdout.write('  → ${decodePaperStatus(b)}');
        }
        stdout.writeln(drain);
      }
      stdout.writeln();
    }
  } finally {
    session.close();
  }

  stdout.writeln('요약 ($rounds회 중 응답 횟수 / 관측된 값):');
  for (final n in [kDleEotPrinter, kDleEotOffline, kDleEotError, kDleEotPaper]) {
    final hits = ok[n] ?? 0;
    final seen = (vals[n] ?? const <int>{})
        .map((b) => '0x${b.toRadixString(16).padLeft(2, '0').toUpperCase()}')
        .join(' ');
    stdout.writeln('  ${names[n]!.padRight(14)} $hits/$rounds  $seen');
  }

  final coverOk = (ok[kDleEotOffline] ?? 0) == rounds;
  final paperOk = (ok[kDleEotPaper] ?? 0) == rounds;
  stdout.writeln();
  if (coverOk && paperOk) {
    stdout.writeln('판정: n=2(커버) · n=4(용지) 가 안정적으로 응답한다.');
    stdout.writeln('      → 커버를 열고 / 용지를 빼고 다시 실행해 비트가 실제로 서는지 확인할 것.');
  } else {
    stdout.writeln('판정: 게이트에 필요한 n=2/n=4 가 안정적이지 않다 '
        '(cover=${ok[kDleEotOffline] ?? 0}/$rounds, paper=${ok[kDleEotPaper] ?? 0}/$rounds).');
    stdout.writeln('      → 불안정한 신호로 무한 대기를 걸면 라벨이 영영 안 나온다. 구현 보류.');
  }
}

class _StatusResult {
  const _StatusResult({this.byte, this.error, this.drained = 0});
  final int? byte;
  final String? error;

  /// 질의 전에 버린 잔여 바이트 수. 0 이 아니면 정렬이 깨져 있었다는 뜻.
  final int drained;
}

/// 열린 핸들 하나로 여러 DLE EOT 질의를 이어서 하는 세션.
///
/// 질의마다 open/close 하면 첫 질의 외에 0바이트가 돌아온다(실측). 프로덕션
/// 게이트도 폴링 중에는 핸들을 유지해야 한다는 뜻이다.
class _StatusSession {
  _StatusSession._(this._handle, this._hEvent);

  final int _handle;
  final int _hEvent;
  final Pointer<OVERLAPPED> _ov = calloc<OVERLAPPED>();
  final Pointer<Uint32> _xferred = calloc<Uint32>();
  final Pointer<Uint8> _wbuf = calloc<Uint8>(8);
  final Pointer<Uint8> _rbuf = calloc<Uint8>(8);

  /// 조회는 읽기가 필요하므로 `GENERIC_READ` 를 함께 연다. 출력 경로(`sendRaw`)는
  /// 쓰기 전용을 유지해야 한다 — 읽기를 지원하지 않는 장치에서 open 이 깨진다.
  static _StatusSession? open(String devicePath) {
    final pathPtr = devicePath.toNativeUtf16();
    try {
      final h = CreateFile(pathPtr, GENERIC_READ | GENERIC_WRITE, 0, nullptr,
          OPEN_EXISTING, FILE_FLAG_OVERLAPPED, 0);
      if (h == INVALID_HANDLE_VALUE) return null;
      final e = CreateEvent(nullptr, TRUE, FALSE, nullptr);
      if (e == 0) {
        CloseHandle(h);
        return null;
      }
      return _StatusSession._(h, e);
    } finally {
      calloc.free(pathPtr);
    }
  }

  /// `DLE EOT n` 1회. **질의 전에 반드시 드레인한다** — 앞선 질의의 응답이
  /// 버퍼에 남아 있으면 그걸 읽어 한 칸씩 밀린 상태를 보게 된다. 이 오정렬이
  /// 곧 "엉뚱한 바이트를 상태로 오독" 이고, 없는 용지없음으로 무한 대기하는 길이다.
  _StatusResult query(int n, {int timeoutMs = 1000, int readAttempts = 3}) {
    final drained = _drain();

    final cmd = dleEot(n);
    _wbuf.asTypedList(cmd.length).setAll(0, cmd);
    final w =
        _io(timeoutMs, () => WriteFile(_handle, _wbuf, cmd.length, nullptr, _ov));
    if (w != null) return _StatusResult(error: 'write $w', drained: drained);

    for (var i = 0; i < readAttempts; i++) {
      final r = _io(timeoutMs, () => ReadFile(_handle, _rbuf, 1, nullptr, _ov));
      if (r != null) return _StatusResult(error: 'read $r', drained: drained);
      if (_xferred.value >= 1) {
        return _StatusResult(byte: _rbuf.value, drained: drained);
      }
      sleep(const Duration(milliseconds: 30));
    }
    return _StatusResult(error: 'read 0바이트', drained: drained);
  }

  /// 남아 있는 미수신 바이트를 짧은 타임아웃으로 버린다. 버린 개수를 돌려준다
  /// (0 이 아니면 앞 질의가 정렬을 깨고 있었다는 뜻이라 진단에 필요하다).
  int _drain() {
    var count = 0;
    for (var i = 0; i < 8; i++) {
      final r = _io(120, () => ReadFile(_handle, _rbuf, 1, nullptr, _ov));
      if (r != null || _xferred.value < 1) break;
      count++;
    }
    return count;
  }

  String? _io(int timeoutMs, int Function() io) =>
      _overlapped(_handle, _hEvent, _ov, _xferred, timeoutMs, io);

  void close() {
    CloseHandle(_hEvent);
    CloseHandle(_handle);
    calloc.free(_rbuf);
    calloc.free(_wbuf);
    calloc.free(_xferred);
    calloc.free(_ov);
  }
}

/// overlapped I/O 1회 — 성공하면 null, 실패하면 사유.
/// 타임아웃 시 `CancelIo` 로 걷어내야 핸들을 닫을 때 걸리지 않는다.
String? _overlapped(int handle, int hEvent, Pointer<OVERLAPPED> ov,
    Pointer<Uint32> xferred, int timeoutMs, int Function() io) {
  ResetEvent(hEvent);
  ov.ref.hEvent = hEvent;
  ov.ref.Internal = 0;
  ov.ref.InternalHigh = 0;
  xferred.value = 0;

  if (io() == 0) {
    final err = GetLastError();
    // err==0 은 "완료했는데 FALSE 를 돌려준" 경우다 — overlapped 핸들에
    // lpNumberOfBytes=NULL 로 호출하면 일부 드라이버가 이렇게 동작한다.
    // 실패로 단정하지 말고 GetOverlappedResult 로 진짜 결과를 묻는다.
    if (err != ERROR_IO_PENDING && err != NO_ERROR) return '실패 win32=$err';
    if (err == ERROR_IO_PENDING &&
        WaitForSingleObject(hEvent, timeoutMs) != WAIT_OBJECT_0) {
      CancelIo(handle);
      // 취소 완료를 기다려야 버퍼를 안전하게 해제할 수 있다.
      GetOverlappedResult(handle, ov, xferred, TRUE);
      return '타임아웃 ${timeoutMs}ms';
    }
  }
  if (GetOverlappedResult(handle, ov, xferred, TRUE) == 0) {
    return 'GetOverlappedResult 실패 win32=${GetLastError()}';
  }
  return null;
}

bool _isG30(UsbPrintDescriptor d) {
  if (d.vendorId != kBixolonVendorId) return false;
  if (d.productId == kBixolonG30ProductId) return true;
  return (d.friendlyName?.toUpperCase() ?? '').contains('G30');
}

String _hex(int v) =>
    '0x${v.toRadixString(16).toUpperCase().padLeft(4, '0')}';

/// 눈으로 즉시 판정 가능한 패턴 — 폭 clamp / 비트 반전 / 행 정렬이 한 장에 드러난다.
///
/// - 1px 테두리   : 폭이 잘리거나 밀리면 오른쪽 변이 사라진다
/// - 대각선       : 행 단위 오프셋이 어긋나면 계단이 튄다
/// - 하단 검정 바 : 전면 반전(흰/검 뒤집힘)을 즉시 드러낸다
Uint8List _testPattern(int w, int h) {
  final rgba = Uint8List(w * h * 4);
  void set(int x, int y, int level) {
    final i = (y * w + x) * 4;
    rgba[i] = level;
    rgba[i + 1] = level;
    rgba[i + 2] = level;
    rgba[i + 3] = 255;
  }

  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      set(x, y, 255); // 흰 배경
    }
  }
  for (int x = 0; x < w; x++) {
    set(x, 0, 0);
    set(x, h - 1, 0);
  }
  for (int y = 0; y < h; y++) {
    set(0, y, 0);
    set(w - 1, y, 0);
  }
  for (int y = 0; y < h; y++) {
    final x = (y * (w - 1) / (h - 1)).round();
    set(x, y, 0);
  }
  for (int y = h - 60; y < h - 20; y++) {
    for (int x = 20; x < w - 20; x++) {
      set(x, y, 0);
    }
  }
  return rgba;
}

// ---------------------------------------------------------------------------
// SetupAPI 열거 / CreateFile+WriteFile — usb_print_service.dart 와 같은 방식.
// (그 파일은 Flutter 의존 때문에 standalone 에서 임포트하지 않는다.)
// ---------------------------------------------------------------------------

/// `SP_DEVICE_INTERFACE_DETAIL_DATA_W.cbSize` — x64 에서 8, x86 에서 6.
int get _detailHeaderSize => sizeOf<IntPtr>() == 8 ? 8 : 6;

List<UsbPrintDescriptor> _enumerateUsbPrint() {
  final guid = GUIDFromString(_guidUsbPrint);
  final hDevInfo = SetupDiGetClassDevs(
      guid, nullptr, 0, DIGCF_PRESENT | DIGCF_DEVICEINTERFACE);
  if (hDevInfo == INVALID_HANDLE_VALUE) {
    calloc.free(guid);
    stderr.writeln('SetupDiGetClassDevs 실패 (win32=${GetLastError()})');
    return const [];
  }

  final result = <UsbPrintDescriptor>[];
  final iface = calloc<SP_DEVICE_INTERFACE_DATA>();
  final devInfo = calloc<SP_DEVINFO_DATA>();
  final required = calloc<Uint32>();
  try {
    iface.ref.cbSize = sizeOf<SP_DEVICE_INTERFACE_DATA>();
    for (int index = 0;; index++) {
      if (SetupDiEnumDeviceInterfaces(hDevInfo, nullptr, guid, index, iface) ==
          0) {
        break;
      }
      devInfo.ref.cbSize = sizeOf<SP_DEVINFO_DATA>();
      required.value = 0;
      SetupDiGetDeviceInterfaceDetail(
          hDevInfo, iface, nullptr, 0, required, nullptr);
      final size = required.value;
      if (size == 0) continue;

      final detail = calloc<Uint8>(size);
      try {
        detail.cast<Uint32>().value = _detailHeaderSize;
        if (SetupDiGetDeviceInterfaceDetail(
              hDevInfo,
              iface,
              detail.cast<SP_DEVICE_INTERFACE_DETAIL_DATA_>(),
              size,
              nullptr,
              devInfo,
            ) ==
            0) {
          continue;
        }
        // DevicePath 의 오프셋은 아키텍처와 무관하게 항상 4 (cbSize 와 혼동 금지).
        final path = (detail + 4).cast<Utf16>().toDartString();
        if (path.isEmpty) continue;
        final ids = parseUsbIdsFromDevicePath(path);
        result.add(UsbPrintDescriptor(
          devicePath: path,
          friendlyName: _registryString(hDevInfo, devInfo, SPDRP_FRIENDLYNAME) ??
              _registryString(hDevInfo, devInfo, SPDRP_DEVICEDESC),
          vendorId: ids.vendorId,
          productId: ids.productId,
        ));
      } finally {
        calloc.free(detail);
      }
    }
  } finally {
    calloc.free(required);
    calloc.free(devInfo);
    calloc.free(iface);
    calloc.free(guid);
    SetupDiDestroyDeviceInfoList(hDevInfo);
  }
  return result;
}

/// 해당 devnode 의 `SPDRP_COMPATIBLEIDS` (REG_MULTI_SZ).
///
/// 프린터 클래스 장치는 `USB\Class_07&SubClass_01&Prot_0X` 형태를 포함한다.
/// 여기서 X 가 인터페이스의 bInterfaceProtocol 이다.
List<String> _compatibleIds(String devicePath) {
  final guid = GUIDFromString(_guidUsbPrint);
  final hDevInfo = SetupDiGetClassDevs(
      guid, nullptr, 0, DIGCF_PRESENT | DIGCF_DEVICEINTERFACE);
  if (hDevInfo == INVALID_HANDLE_VALUE) {
    calloc.free(guid);
    return const [];
  }
  final iface = calloc<SP_DEVICE_INTERFACE_DATA>();
  final devInfo = calloc<SP_DEVINFO_DATA>();
  final required = calloc<Uint32>();
  final target = devicePath.toLowerCase();
  try {
    iface.ref.cbSize = sizeOf<SP_DEVICE_INTERFACE_DATA>();
    for (int index = 0;; index++) {
      if (SetupDiEnumDeviceInterfaces(hDevInfo, nullptr, guid, index, iface) ==
          0) {
        break;
      }
      devInfo.ref.cbSize = sizeOf<SP_DEVINFO_DATA>();
      required.value = 0;
      SetupDiGetDeviceInterfaceDetail(
          hDevInfo, iface, nullptr, 0, required, nullptr);
      final size = required.value;
      if (size == 0) continue;
      final detail = calloc<Uint8>(size);
      try {
        detail.cast<Uint32>().value = _detailHeaderSize;
        if (SetupDiGetDeviceInterfaceDetail(
                hDevInfo,
                iface,
                detail.cast<SP_DEVICE_INTERFACE_DETAIL_DATA_>(),
                size,
                nullptr,
                devInfo) ==
            0) {
          continue;
        }
        final path = (detail + 4).cast<Utf16>().toDartString();
        if (path.toLowerCase() != target) continue;
        return _registryMultiString(hDevInfo, devInfo, SPDRP_COMPATIBLEIDS);
      } finally {
        calloc.free(detail);
      }
    }
  } finally {
    calloc.free(required);
    calloc.free(devInfo);
    calloc.free(iface);
    calloc.free(guid);
    SetupDiDestroyDeviceInfoList(hDevInfo);
  }
  return const [];
}

/// REG_MULTI_SZ 속성 — null 로 구분된 문자열들, 빈 문자열로 종료.
List<String> _registryMultiString(
    int hDevInfo, Pointer<SP_DEVINFO_DATA> devInfo, int prop) {
  final required = calloc<Uint32>();
  try {
    SetupDiGetDeviceRegistryProperty(
        hDevInfo, devInfo, prop, nullptr, nullptr, 0, required);
    final size = required.value;
    if (size == 0) return const [];
    final buf = calloc<Uint8>(size);
    try {
      if (SetupDiGetDeviceRegistryProperty(
              hDevInfo, devInfo, prop, nullptr, buf, size, nullptr) ==
          0) {
        return const [];
      }
      final units = buf.cast<Uint16>().asTypedList(size ~/ 2);
      final out = <String>[];
      var start = 0;
      for (var i = 0; i < units.length; i++) {
        if (units[i] != 0) continue;
        if (i == start) break; // 빈 문자열 = 종료 마커
        out.add(String.fromCharCodes(units.sublist(start, i)));
        start = i + 1;
      }
      return out;
    } finally {
      calloc.free(buf);
    }
  } finally {
    calloc.free(required);
  }
}

String? _registryString(int hDevInfo, Pointer<SP_DEVINFO_DATA> devInfo, int prop) {
  final required = calloc<Uint32>();
  try {
    SetupDiGetDeviceRegistryProperty(
        hDevInfo, devInfo, prop, nullptr, nullptr, 0, required);
    final size = required.value;
    if (size == 0) return null;
    final buf = calloc<Uint8>(size);
    try {
      if (SetupDiGetDeviceRegistryProperty(
              hDevInfo, devInfo, prop, nullptr, buf, size, nullptr) ==
          0) {
        return null;
      }
      final s = buf.cast<Utf16>().toDartString();
      return s.trim().isEmpty ? null : s.trim();
    } finally {
      calloc.free(buf);
    }
  } finally {
    calloc.free(required);
  }
}

/// 성공하면 null, 실패하면 사유 문자열.
String? _write(String devicePath, Uint8List data) {
  final pathPtr = devicePath.toNativeUtf16();
  int handle = INVALID_HANDLE_VALUE;
  try {
    handle = CreateFile(pathPtr, GENERIC_WRITE, 0, nullptr, OPEN_EXISTING,
        FILE_ATTRIBUTE_NORMAL, 0);
    if (handle == INVALID_HANDLE_VALUE) {
      final err = GetLastError();
      return (err == ERROR_ACCESS_DENIED || err == ERROR_SHARING_VIOLATION)
          ? 'open-access-denied (win32=$err) — 스풀러/타 유틸이 점유 중'
          : 'open-failed (win32=$err)';
    }
    final buf = calloc<Uint8>(data.length);
    final written = calloc<Uint32>();
    try {
      buf.asTypedList(data.length).setAll(0, data);
      if (WriteFile(handle, buf, data.length, written, nullptr) == 0) {
        return 'write-failed (win32=${GetLastError()})';
      }
      if (written.value != data.length) {
        return 'partial-write (${written.value}/${data.length})';
      }
      return null;
    } finally {
      calloc.free(written);
      calloc.free(buf);
    }
  } finally {
    if (handle != INVALID_HANDLE_VALUE) CloseHandle(handle);
    calloc.free(pathPtr);
  }
}
