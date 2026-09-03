import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import 'package:appfit_order_agent/services/platform_service.dart';
import 'package:appfit_order_agent/services/usb_print_descriptor.dart';
import 'package:appfit_order_agent/utils/logger.dart';

/// Windows USB 프린터 클래스(usbprint.sys) 장치로 ESC/POS 바이트를 직접 보내는
/// 서비스. POSBANK A8 처럼 **가상 COM 포트를 만들지 않는** 영수증 프린터용.
///
/// ## 왜 필요한가
///
/// 같은 USB 영수증 프린터라도 Windows 바인딩이 두 갈래로 갈린다 (본 PC 실측):
///
/// - PR800 = `USB\VID_0D28&PID_4C59` (NXP LPC 복합) → CDC-ACM 인터페이스가
///   usbser.sys 를 통해 **COM3** 을 만든다 → [ComPortPrintService] 가 처리.
/// - POSBANK A8 = `USB\VID_0483&PID_A319` "EASYSET PBP_A8" → **usbprint.inf 단독**
///   바인딩. COM 포트가 생기지 않아 COM 경로에서는 영원히 안 잡힌다.
///
/// ## 이것은 Winspool 부활이 아니다 (되돌리기 전에 읽을 것)
///
/// `docs/ARCHITECTURE.md` 와 메모리 `project_store_printer_topology` 는 Winspool
/// RAW 폴백을 금지한다. 그 금지의 실질은 **"사용자가 고르지 않은 OS 기본 프린터로
/// 영수증이 새어나가는 사고"** 이며, 이 경로는 그 세 조건을 모두 피한다.
///
/// 1. **스풀러를 거치지 않는다.** `OpenPrinter`/`StartDocPrinter` 가 아니라 장치
///    인터페이스 경로를 `CreateFile` 로 직접 열어 `WriteFile` 한다. 프린터 큐 ·
///    기본 프린터라는 개념이 이 파일에 등장하지 않는다.
/// 2. **자동 선택이 없다.** 사용자가 목록에서 명시적으로 고르기 전까지 전송 경로는
///    `PrinterNoDevice` 다 (COM 경로의 `comPort == null` 규율과 동일).
/// 3. **라벨 프린터를 열거에서 제외한다** ([_isLabelPrinterVendor]). 현장 PC 에는
///    BIXOLON G30 도 usbprint 로 잡혀 있어, 제외가 없으면 정확히 그 금지된 사고
///    (영수증이 라벨 프린터로 송출)가 재현된다.
///
/// ## COM 경로와의 비대칭 하나
///
/// [ComPortPrintService] 가 DLE EOT 1 핑을 꼭 필요로 했던 이유는 USB-CDC 칩이
/// 프린터 본체 전원 OFF 에도 PC bus power 로 살아남아 포트가 유지되기 때문이다
/// (false-success). usbprint devnode 는 전원 OFF / 케이블 분리 시 **사라지므로**
/// `DIGCF_PRESENT` 열거 자체가 정직한 생존 신호다 — 여기서 DLE EOT 를 흉내낼
/// 필요가 없다. 대신 Android [UsbReceiptPrinter.verifyConnection] 과 같은
/// `ESC @` 2바이트 write 로 실제 쓰기 가능 여부까지 확인한다.
class UsbPrintService {
  UsbPrintService._();

  /// `GUID_DEVINTERFACE_USBPRINT` — usbprint.sys 가 노출하는 장치 인터페이스.
  /// 값은 Windows DDK 에서 영구 고정.
  static const String guidDevInterfaceUsbPrint =
      '{28D78FAD-5A12-11D1-AE5B-0000F803A8C2}';

  /// `SP_DEVICE_INTERFACE_DETAIL_DATA_W` 의 `cbSize`.
  ///
  /// 구조체는 `{ DWORD cbSize; WCHAR DevicePath[1]; }` 이고 정렬 규칙 때문에
  /// **x64 에서 8, x86 에서 6** 이다 (필드 오프셋이 아니라 sizeof). Win32 의
  /// 유명한 함정으로, 틀리면 `SetupDiGetDeviceInterfaceDetail` 이 ERROR_INVALID_
  /// USER_BUFFER 로 실패한다. DevicePath 의 **오프셋은 항상 4** 라는 점과 혼동
  /// 하지 말 것 ([_readDevicePath] 참조).
  static int get _detailHeaderSize => sizeOf<IntPtr>() == 8 ? 8 : 6;

  /// bulk write 청크. Android [UsbReceiptPrinter] 의 `CHUNK_SIZE` 와 같은 8 KiB —
  /// 로고 비트맵 포함 영수증이 30~80 KiB 까지 가므로 나눠 보낸다.
  static const int _chunkSize = 8 * 1024;

  /// ESC @ (0x1B 0x40) — "Initialize printer". 표준 ESC/POS no-op 이라 출력물에
  /// 영향이 없어 생존 확인용 write 로 쓴다.
  static const List<int> _escInit = [0x1B, 0x40];

  /// 직전 false 반환의 사유. `WindowsTransport` 가 결과 분류에 사용한다.
  /// 값 도메인은 [ComPortPrintService.lastFailureReason] 과 같은 이유로 문자열이다:
  /// - 'not-enumerated'    : 진입 시 usbprint 열거 결과에 해당 경로가 없음
  /// - 'open-access-denied': CreateFile 이 배타 점유로 거부 (win32 5 / 32)
  /// - 'open-failed'       : 그 외 CreateFile 실패
  /// - 'write-failed'      : WriteFile 실패 또는 0바이트 write
  static String? _lastFailureReason;
  static String? get lastFailureReason => _lastFailureReason;

  /// 장치 오픈~클로즈 임계구역 직렬화 락 (Future 체이닝 mutex).
  /// [sendRaw] 와 [probeConnection] 이 같은 장치를 동시에 열지 않도록 보장한다.
  /// [ComPortPrintService] 와 같은 idiom — 단일 isolate 라 일반 필드로 충분.
  static Future<void> _lock = Future<void>.value();

  static Future<T> _synchronized<T>(Future<T> Function() action) {
    final completer = Completer<void>();
    final prev = _lock;
    _lock = completer.future;
    return prev.then((_) => action()).whenComplete(completer.complete);
  }

  // ---- 열거 --------------------------------------------------------------

  /// 라벨 프린터 제조사 VID. **영수증 경로가 절대 잡으면 안 되는 장치**다.
  ///
  /// ★ 이 목록은 세 곳에 흩어져 있고 함께 유지해야 한다 (2026-09-01 에 G30 이
  /// 한 곳만 갱신돼 영수증 경로가 라벨 프린터를 선점한 사고가 있었다):
  ///   - `windows_label_printer_backend.dart` `_kUsbPortCandidates` (Windows 라벨)
  ///   - `UsbReceiptPrinter.isLabelPrinter` (Android 영수증)
  ///   - 여기 (Windows 영수증)
  ///
  /// 주의: 범용 USB-Serial 브리지 칩(PL2303 = 0x067B 등)은 절대 넣지 말 것 —
  /// 영수증 프린터가 그 칩으로 붙으면 라벨로 오인돼 목록에서 사라진다.
  static const Set<int> _labelPrinterVendors = {
    0x1504, // BIXOLON (G30 등)
    0x4B43, // Caysn (D2 / D3)
    0x0FE6, // REXOD RXLA-561
  };

  static bool _isLabelPrinterVendor(int? vid) =>
      vid != null && _labelPrinterVendors.contains(vid);

  /// 현재 연결된 usbprint 장치 목록. 라벨 프린터는 제외된다.
  ///
  /// `DIGCF_PRESENT` 라서 **지금 꽂혀 있고 전원이 들어온 장치만** 나온다 —
  /// 이 목록에 있다는 사실 자체가 1차 생존 신호다.
  static List<UsbPrintDescriptor> enumerate() {
    final guid = GUIDFromString(guidDevInterfaceUsbPrint);
    final hDevInfo = SetupDiGetClassDevs(
      guid,
      nullptr,
      0,
      DIGCF_PRESENT | DIGCF_DEVICEINTERFACE,
    );
    if (hDevInfo == INVALID_HANDLE_VALUE) {
      calloc.free(guid);
      logger.w('[UsbPrint] SetupDiGetClassDevs 실패 (win32=${GetLastError()})');
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
          break; // ERROR_NO_MORE_ITEMS
        }
        devInfo.ref.cbSize = sizeOf<SP_DEVINFO_DATA>();

        // 1-pass: 필요한 버퍼 크기만 받는다 (실패가 정상 — required 만 채워진다).
        required.value = 0;
        SetupDiGetDeviceInterfaceDetail(
            hDevInfo, iface, nullptr, 0, required, nullptr);
        final size = required.value;
        if (size == 0) continue;

        // 2-pass: 실제 경로 + devInfo 를 채운다.
        final detail = calloc<Uint8>(size);
        try {
          detail.cast<Uint32>().value = _detailHeaderSize;
          final ok = SetupDiGetDeviceInterfaceDetail(
            hDevInfo,
            iface,
            detail.cast<SP_DEVICE_INTERFACE_DETAIL_DATA_>(),
            size,
            nullptr,
            devInfo,
          );
          if (ok == 0) continue;

          final path = _readDevicePath(detail);
          if (path.isEmpty) continue;

          final ids = parseUsbIdsFromDevicePath(path);
          if (_isLabelPrinterVendor(ids.vendorId)) {
            logger.d('[UsbPrint] 라벨 프린터 제외: $path');
            continue;
          }

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
    } catch (e, s) {
      logger.e('[UsbPrint] 장치 열거 실패', error: e, stackTrace: s);
    } finally {
      calloc.free(required);
      calloc.free(devInfo);
      calloc.free(iface);
      calloc.free(guid);
      SetupDiDestroyDeviceInfoList(hDevInfo);
    }
    return result;
  }

  /// `SP_DEVICE_INTERFACE_DETAIL_DATA_W.DevicePath` 를 읽는다.
  ///
  /// 구조체의 **sizeof 는 8(x64)** 이지만 `DevicePath` 필드의 **오프셋은 4** 다
  /// (cbSize DWORD 바로 뒤). 8 에서 읽으면 경로 앞 2글자가 잘린다.
  static String _readDevicePath(Pointer<Uint8> detail) {
    try {
      return (detail + 4).cast<Utf16>().toDartString();
    } catch (_) {
      return '';
    }
  }

  /// SetupAPI 레지스트리 문자열 property 1건. 없거나 실패하면 null.
  static String? _registryString(
    int hDevInfo,
    Pointer<SP_DEVINFO_DATA> devInfo,
    int property,
  ) {
    final required = calloc<Uint32>();
    try {
      required.value = 0;
      SetupDiGetDeviceRegistryProperty(
          hDevInfo, devInfo, property, nullptr, nullptr, 0, required);
      final size = required.value;
      if (size == 0) return null;
      final buf = calloc<Uint8>(size);
      try {
        final ok = SetupDiGetDeviceRegistryProperty(
            hDevInfo, devInfo, property, nullptr, buf, size, nullptr);
        if (ok == 0) return null;
        final s = buf.cast<Utf16>().toDartString().trim();
        return s.isEmpty ? null : s;
      } finally {
        calloc.free(buf);
      }
    } catch (_) {
      return null;
    } finally {
      calloc.free(required);
    }
  }

  // ---- 전송 --------------------------------------------------------------

  /// ESC/POS 바이트를 [devicePath] 장치로 송출. 성공하면 true.
  ///
  /// 진입 가드로 [enumerate] 존재 확인을 먼저 한다 — COM 경로의 'not-enumerated'
  /// 가드와 같은 역할이며, 여기서는 그것이 곧 전원/케이블 판정이다.
  static Future<bool> sendRaw(
    Uint8List data, {
    required String devicePath,
  }) {
    return _synchronized(() => _sendRawLocked(data, devicePath));
  }

  static Future<bool> _sendRawLocked(Uint8List data, String devicePath) async {
    _lastFailureReason = null;

    if (!_isPresent(devicePath)) {
      _lastFailureReason = 'not-enumerated';
      logToFile(
        tag: LogTag.PLATFORM,
        message: '[UsbPrint] 장치가 열거 결과에 없음 — 즉시 noDevice '
            '(전원/케이블 확인, 다음 attempt backoff 안에서 자연 복구 예상) $devicePath',
      );
      return false;
    }

    // 동기 win32 open/write 는 수백ms~수초 main thread 를 막을 수 있다
    // (로고 포함 영수증 80KiB). 라벨 FFI 와 같은 규율으로 Isolate 로 boxing 하고,
    // isolate 안에서는 로깅/플랫폼 채널을 쓰지 않는다.
    final r = await Isolate.run(() => _openWriteClose(devicePath, data));

    if (r.ok) {
      logger.i('[UsbPrint] ${data.length} bytes 송출 성공 — $devicePath');
      return true;
    }
    _lastFailureReason = r.reason;
    _logFailure(r, devicePath);
    return false;
  }

  /// 열거 결과에 [devicePath] 가 있는지. 경로 비교는 대소문자 무시 —
  /// SetupAPI 가 돌려주는 표기가 OS/드라이버 버전에 따라 갈린다.
  static bool _isPresent(String devicePath) {
    final target = devicePath.toLowerCase();
    return enumerate().any((d) => d.devicePath.toLowerCase() == target);
  }

  static void _logFailure(_WriteOutcome r, String devicePath) {
    switch (r.reason) {
      case 'open-access-denied':
        logToFile(
          tag: LogTag.WARNING,
          message: '[UsbPrint] access denied (win32=${r.win32}) — '
              'Windows 프린터 큐 또는 외부 유틸이 장치를 점유 중일 수 있음. $devicePath',
        );
      case 'write-failed':
        logToFile(
          tag: LogTag.ERROR,
          message: '[UsbPrint] write 실패 (win32=${r.win32}, '
              'sent=${r.bytesWritten}/${r.total}) $devicePath',
        );
      default:
        logToFile(
          tag: LogTag.WARNING,
          message: '[UsbPrint] open 실패 (win32=${r.win32}) — 점유 외 원인. $devicePath',
        );
    }
  }

  /// 실제 오픈 → 청크 write → 클로즈. **Isolate 안에서만 실행된다** —
  /// 로깅/플랫폼 채널 금지, 반환값으로만 결과를 알린다.
  static _WriteOutcome _openWriteClose(String devicePath, Uint8List data) {
    final pathPtr = devicePath.toNativeUtf16();
    int handle = INVALID_HANDLE_VALUE;
    try {
      handle = CreateFile(
        pathPtr,
        GENERIC_WRITE,
        0, // 배타 오픈. 스풀러/타 유틸과의 동시 점유를 허용하지 않는다.
        nullptr,
        OPEN_EXISTING,
        FILE_ATTRIBUTE_NORMAL,
        0,
      );
      if (handle == INVALID_HANDLE_VALUE) {
        final err = GetLastError();
        final denied =
            err == ERROR_ACCESS_DENIED || err == ERROR_SHARING_VIOLATION;
        return _WriteOutcome(
          ok: false,
          reason: denied ? 'open-access-denied' : 'open-failed',
          win32: err,
          bytesWritten: 0,
          total: data.length,
        );
      }

      final buf = calloc<Uint8>(data.length);
      final written = calloc<Uint32>();
      try {
        buf.asTypedList(data.length).setAll(0, data);
        int offset = 0;
        while (offset < data.length) {
          final len = (data.length - offset) < _chunkSize
              ? (data.length - offset)
              : _chunkSize;
          written.value = 0;
          final ok = WriteFile(handle, buf + offset, len, written, nullptr);
          // 0바이트 write 는 성공 반환이어도 진행이 없으므로 무한 루프가 된다.
          if (ok == 0 || written.value <= 0) {
            return _WriteOutcome(
              ok: false,
              reason: 'write-failed',
              win32: GetLastError(),
              bytesWritten: offset,
              total: data.length,
            );
          }
          offset += written.value;
        }
        return _WriteOutcome(
          ok: true,
          reason: null,
          win32: 0,
          bytesWritten: offset,
          total: data.length,
        );
      } finally {
        calloc.free(written);
        calloc.free(buf);
      }
    } finally {
      if (handle != INVALID_HANDLE_VALUE) CloseHandle(handle);
      calloc.free(pathPtr);
    }
  }

  // ---- 생존 확인 ----------------------------------------------------------

  /// [devicePath] 장치가 실제로 쓰기 가능한지 검증한다.
  ///
  /// `DIGCF_PRESENT` 열거 + `ESC @` 2바이트 write. Android
  /// `UsbReceiptPrinter.verifyConnection` 과 같은 신호이며 출력물에 영향이 없다.
  /// [sendRaw] 와 락을 공유하므로 출력 중에는 검증이 대기한다.
  static Future<bool> probeConnection({required String devicePath}) {
    return _synchronized(() async {
      if (!_isPresent(devicePath)) {
        logToFile(
          tag: LogTag.PLATFORM,
          message: '[UsbPrint] probeConnection → false '
              '(reason=not-enumerated) $devicePath',
        );
        return false;
      }
      final r = await Isolate.run(
          () => _openWriteClose(devicePath, Uint8List.fromList(_escInit)));
      if (r.ok) {
        logger.d('[UsbPrint] probeConnection alive — $devicePath');
        return true;
      }
      _lastFailureReason = r.reason;
      _logFailure(r, devicePath);
      return false;
    });
  }

  /// 설정 UI "테스트 출력" 이 아니라 **연결 방식 전환 직후 진단**용 —
  /// 실제 테스트 페이지는 `ExternalReceiptPrinter.printTestPage` 가 큐를 거쳐
  /// 보낸다. 여기 별도 진입점을 두지 않는 이유는 COM 경로의
  /// `ComPortPrintService.printTestPage` 와 달리 큐 우회 경로를 늘리지 않기 위함.
  static String describe(String? devicePath) =>
      devicePath == null || devicePath.isEmpty ? '(미선택)' : devicePath;
}

/// [UsbPrintService._openWriteClose] 의 결과. isolate 경계를 넘으므로 단순 값만
/// 담는다.
class _WriteOutcome {
  const _WriteOutcome({
    required this.ok,
    required this.reason,
    required this.win32,
    required this.bytesWritten,
    required this.total,
  });

  final bool ok;
  final String? reason;
  final int win32;
  final int bytesWritten;
  final int total;
}
