/// BIXOLON G30 의 Windows 라벨 백엔드.
///
/// Caysn/REXOD 가 `autoreplyprint.dll` 을 거치는 것과 달리, G30 은 **벤더 DLL 없이**
/// usbprint devnode 로 직접 ESC/POS 를 받는다. 전송은 POSBANK A8 영수증으로 이미
/// 검증된 `UsbPrintService.sendRaw`(SetupAPI 열거 + `CreateFile`/`WriteFile`,
/// 스풀러 미경유)를 그대로 재사용하고, 이 파일은 **장치 검출 + 인코더 호출**만 한다.
///
/// ## Caysn 백엔드와의 구조적 차이
///
/// - **연결이라는 상태가 없다.** `sendRaw` 가 매 출력마다 열고 닫는다. 그래서
///   `dispose()` 가 반납할 핸들도, stale 핸들 재연결 판정도 없다.
/// - **생존 신호가 열거 그 자체다.** usbprint devnode 는 프린터 전원 OFF /
///   케이블 분리 시 사라진다(`DIGCF_PRESENT`). Caysn 경로가 `portIsConnectionValid`
///   로 좀비 핸들을 걸러야 했던 문제가 여기서는 발생하지 않는다.
/// - **진입 게이트는 Android 와 동등하다.** 인쇄 전에 `DLE EOT` 로 커버열림·
///   용지없음을 확인하고 해소될 때까지 무한 대기한다([_waitEntryGate]).
/// - **완료 판정은 여전히 최소 범위다.** `WriteFile` 성공 = 출력 성공으로 본다.
///   Android(UPOS 동기 모드)는 물리 인쇄 완료까지 블로킹하지만 Windows 는 프린터
///   버퍼에 적재된 시점에 성공을 돌려준다. ESC/POS 실시간 상태에는 "이 작업이
///   끝났는가" 신호가 없어 근사 판정을 하면 라벨을 두 번 뽑을 위험이 있고,
///   **중복은 유실보다 나쁘다**(유실은 재발행으로 복구되지만 중복은 손님에게 나간다).
///   떼기 대기는 연속용지+커터라 애초에 개념이 없다.
///
/// ## win32 도달 가능성 규율
///
/// 이 파일은 `windows_label_router` ← `print_service` 를 통해 **Android import
/// 그래프에서 도달 가능**하다. `usb_print_service.dart` 는 top-level 로
/// `package:win32` 를 import 하므로 여기서 일반 import 하면 Android 에서
/// kernel32.dll lookup 크래시가 난다 → **`deferred as` + `loadLibrary()` 필수.**
/// 값 객체(`UsbPrintDescriptor`, `parseUsbIdsFromDevicePath`)는 native 의존이 없는
/// `usb_print_descriptor.dart` 에 따로 있어 일반 import 로 쓴다 — 그 파일이 분리돼
/// 있는 이유가 정확히 이것이다.
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:appfit_order_agent/services/label_printer/label_printer_models.dart';
import 'package:appfit_order_agent/services/label_printer/windows/escpos_realtime_status.dart';
import 'package:appfit_order_agent/services/label_printer/windows/g30_escpos_raster.dart';
import 'package:appfit_order_agent/services/platform_service.dart';
import 'package:appfit_order_agent/services/usb_print_descriptor.dart';
import 'package:appfit_order_agent/utils/logger.dart';

// ★ deferred 필수 — 위 "win32 도달 가능성 규율" 참조.
import 'package:appfit_order_agent/services/usb_print_service.dart'
    deferred as usbprint;

class BixolonG30WindowsBackend {
  BixolonG30WindowsBackend._();

  static final BixolonG30WindowsBackend instance =
      BixolonG30WindowsBackend._();

  /// 복구대기 폴링 간격. Windows Caysn 백엔드의 `_kPaperWaitStepMs` 와 같은 값으로
  /// 맞춘다 — 같은 화면에서 두 기종이 같은 반응 속도를 보이게 하기 위함이다.
  static const int _kStatusPollIntervalMs = 100;

  /// 복구대기가 길어질 때 살아있음을 남기는 주기. Android
  /// `RECOVERY_HEARTBEAT_MS` / Windows Caysn `_kPaperWaitProgressLogMs` 와 동일.
  static const int _kRecoveryHeartbeatMs = 60000;

  /// 마지막 [detect] 에서 찾은 devnode 경로. 미검출이면 null.
  ///
  /// USB 허브의 물리 포트가 경로에 들어가므로 **다른 포트로 옮겨 꽂으면 값이
  /// 바뀐다**. 사용자 설정에 저장하지 않고 매 [detect] 마다 다시 찾는 이유다
  /// (영수증 경로는 사용자가 고른 경로를 저장하지만, 라벨은 기종 선택 UI 자체가
  /// 없고 지원 모델이 고정이라 자동 검출이 정본이다).
  String? _devicePath;

  String? get devicePath => _devicePath;

  /// 직전 [detect] 결과. 동기 getter 라 설정 화면의 연결 배지가 바로 읽을 수 있다.
  bool get isPresent => _devicePath != null;

  bool get isAvailable => Platform.isWindows;

  /// G30 이 현재 꽂혀 있는지 확인하고 devnode 경로를 캐시한다.
  ///
  /// 판정은 Android `BixolonPosDriver.isG30Device` 와 같은 규칙이다 —
  /// VID 확정 + (PID 일치 또는 이름에 "G30" 포함). VID 만으로는 확정하지 않는다:
  /// XD5-40d 지원 종료로 폴백 대상이 사라져서, 미식별 0x1504 기기는 **의도적으로
  /// 미검출**이다(넓혀서 G30 으로 몰면 실패 원인이 흐려진다).
  Future<bool> detect() async {
    if (!isAvailable) {
      _devicePath = null;
      return false;
    }
    try {
      await usbprint.loadLibrary();
      final devices = usbprint.UsbPrintService.enumerateLabelPrinters();
      final match = _pickG30(devices);
      if (match == null) {
        if (_devicePath != null) {
          logger.i('[G30] devnode 사라짐 — 미연결로 전환 (직전: $_devicePath)');
        }
        _devicePath = null;
        return false;
      }
      if (_devicePath != match.devicePath) {
        logger.i('[G30] 검출: ${match.displayLabel} path=${match.devicePath}');
      }
      _devicePath = match.devicePath;
      return true;
    } catch (e, s) {
      logger.e('[G30] 검출 실패', error: e, stackTrace: s);
      _devicePath = null;
      return false;
    }
  }

  static UsbPrintDescriptor? _pickG30(List<UsbPrintDescriptor> devices) {
    for (final d in devices) {
      if (d.vendorId != kBixolonVendorId) continue;
      if (d.productId == kBixolonG30ProductId) return d;
      final name = d.friendlyName?.toUpperCase() ?? '';
      if (name.contains('G30')) return d;
    }
    return null;
  }

  /// 라벨 PNG 한 장 출력. 성공하면 true.
  ///
  /// false 는 "프린터에 아무것도 전달되지 않았다" 를 뜻한다 — [encodeG30Label]
  /// 실패든 `sendRaw` 실패든 전송 전에 끊긴 것이므로 **재시도가 안전**하다.
  /// (`sendRaw` 는 부분 write 를 `write-failed` 로 보고하므로 그 경우만 중복
  /// 위험이 있는데, 라벨 한 장이 커터로 끝나지 않으면 다음 장과 이어져 나오므로
  /// 육안으로 즉시 드러난다.)
  Future<bool> printPng(Uint8List pngBytes) async {
    if (!isAvailable) return false;
    final path = _devicePath;
    if (path == null) {
      logger.w('[G30] 출력 요청됐으나 devnode 미검출 — 먼저 detect() 가 성공해야 한다');
      return false;
    }
    try {
      // 인쇄 전 복구대기 — Android waitEntryGateLocked 와 같은 자리다.
      if (!await _waitEntryGate(path)) return false;

      final bytes = await _encodeLabel(pngBytes);
      await usbprint.loadLibrary();
      final ok = await usbprint.UsbPrintService.sendRaw(bytes, devicePath: path);
      if (!ok) {
        logger.w('[G30] 전송 실패 — '
            'reason=${usbprint.UsbPrintService.lastFailureReason} path=$path');
        // devnode 가 사라진 경우 다음 연결 확인에서 미연결로 떨어지도록 캐시를 버린다.
        if (usbprint.UsbPrintService.lastFailureReason == 'not-enumerated') {
          _devicePath = null;
        }
      }
      return ok;
    } catch (e, s) {
      logger.e('[G30] 출력 예외', error: e, stackTrace: s);
      return false;
    }
  }

  /// 인쇄 진입 게이트 — 커버열림·용지없음이 해소될 때까지 **무한 대기**한다.
  ///
  /// Android [BixolonPosDriver.waitEntryGateLocked] 의 의미론을 그대로 옮긴 것이다:
  /// 폴링 간격·로그 어휘(`복구대기 진입`/`복구감지`)·60초 heartbeat 까지 맞췄다.
  /// 두 플랫폼 로그를 같은 눈으로 읽기 위함이다.
  ///
  /// ## 상태를 못 읽으면 통과시킨다 (fail-open)
  ///
  /// 조회 실패 시 대기하면 "상태를 못 읽는 개체" 에서 라벨이 **영구히 안 나온다**.
  /// 게이트가 없던 시절에도 출력은 됐으므로, 게이트 도입이 출력을 막는 회귀를
  /// 만들어선 안 된다. 잘못된 통과는 최악이 "게이트 도입 전과 같음" 이지만,
  /// 잘못된 대기는 없던 장애를 새로 만든다.
  ///
  /// 중단(false 반환)은 devnode 가 사라진 경우뿐 — 프린터가 뽑혔다는 뜻이라
  /// 기다릴 대상이 없다.
  Future<bool> _waitEntryGate(String devicePath) async {
    final started = DateTime.now();
    var lastNotice = started;
    var noticed = false;

    while (true) {
      await usbprint.loadLibrary();
      final status =
          await usbprint.UsbPrintService.queryGateStatus(devicePath: devicePath);

      if (status == null) {
        // 열거에서 사라졌으면 프린터가 뽑힌 것 — 대기가 무의미하다.
        final devices = usbprint.UsbPrintService.enumerateLabelPrinters();
        if (_pickG30(devices) == null) {
          logger.w('[G30] 복구대기 중단 — devnode 사라짐 $devicePath');
          _devicePath = null;
          return false;
        }
        if (noticed) {
          logger.w('[G30] 복구대기 중 상태 조회 실패 — 통과시킴(fail-open)');
        }
        return true;
      }

      if (status.canPrint) {
        if (noticed) {
          final waited = DateTime.now().difference(started).inMilliseconds;
          logToFile(
              tag: LogTag.PLATFORM,
              message: '[G30] 복구감지 wait=${waited}ms — 인쇄재개');
        }
        return true;
      }

      if (!noticed) {
        logToFile(
          tag: LogTag.WARNING,
          message: '[G30] 복구대기 진입 ['
              '${describeEntryBlock(coverOpen: status.coverOpen, paperEnd: status.paperEnd)}]',
        );
        noticed = true;
      }

      final now = DateTime.now();
      if (now.difference(lastNotice).inMilliseconds >= _kRecoveryHeartbeatMs) {
        logToFile(
            tag: LogTag.PLATFORM,
            message: '[G30] 복구대기중 elapsed='
                '${now.difference(started).inSeconds}s $status');
        lastNotice = now;
      }
      await Future.delayed(
          const Duration(milliseconds: _kStatusPollIntervalMs));
    }
  }

  /// 라벨 PNG → ESC/POS 바이트열.
  ///
  /// 디코드가 여기 있는 이유: `g30_escpos_raster.dart` 를 `dart:ui` 없는 순수
  /// 파일로 유지해 standalone `dart run`(= `tool/g30_windows_probe.dart`)에서도
  /// 같은 인코더를 그대로 쓰게 하기 위함이다.
  ///
  /// 치수는 **디코드 결과에서 얻는다** — 연속용지라 장마다 높이가 달라 호출부가
  /// 상수로 넘길 수 없다.
  static Future<Uint8List> _encodeLabel(Uint8List pngBytes) async {
    final codec = await ui.instantiateImageCodec(pngBytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) {
        throw StateError('G30 라벨 PNG 디코드 실패 — rawRgba 가 null');
      }
      return encodeG30RasterFromRgba(
        rgba: data.buffer.asUint8List(),
        width: image.width,
        height: image.height,
      );
    } finally {
      image.dispose();
      codec.dispose();
    }
  }

  /// 열린 핸들이 없으므로 캐시만 버린다. 앱 종료·브랜드 전환에서 호출된다.
  void dispose() {
    _devicePath = null;
  }
}
