// Windows 라벨 프린터 벤더 라우팅 seam.
//
// 두 백엔드를 가른다:
// - BIXOLON G30            → usbprint devnode 직결 ESC/POS (벤더 DLL 없음)
// - Caysn D2/D3 · REXOD    → autoreplyprint.dll FFI
//
// Android `NativeMethodHandler` 의 벤더 분기와 **대칭이며 우선순위도 같다** —
// 거기서 `BixolonPosDriver.isG30Attached()` 가 먼저 걸리듯 여기서도 G30 이 먼저다.
// 호출부(main.dart warmup/dispose, print_service.dart checkConnection/printLabel,
// 설정 화면)는 백엔드를 직접 보지 않는다 — 이 불변식이 이 파일의 존재 이유다.
//
// ★ G30 이 붙어 있으면 Caysn 백엔드를 **아예 호출하지 않는다.** 이건 성능이 아니라
//   안전 문제다: Caysn SDK 의 `CP_Port_EnumUsb` 는 usbprint 장치를 가리지 않고
//   내놓고, usbprint devnode 는 `CreateFile` 이 성공하므로 SDK 가 G30 에 Caysn
//   핸드셰이크 바이트를 써 넣어 **깨진 문자가 인쇄된다**(2026-09-03 실기 관측).
//   백엔드 쪽 VID/PID 게이트(`_ensurePortOpen`)와 이중으로 막는다.
//
// 이력: 2026-07 ~ 2026-09 사이에는 BIXOLON XD5-40d 용 BXLLAPI FFI 백엔드가 두 번째
// 분기였다. XD5-40d 지원 종료와 함께 삭제됐고, 그 자리를 지금 G30 이 쓴다. 재사용한
// 결론(사전 이진화 임계 210 등)은 docs/PRINTER_FLOW.md §3.4 tombstone 과 메모리 노트
// project_bixolon_xd5_removal_residue.md 참조.

import 'dart:io';
import 'dart:typed_data';

import 'package:appfit_order_agent/services/label_printer/label_printer_models.dart';
import 'package:appfit_order_agent/services/label_printer/label_printer_options.dart';
import 'package:appfit_order_agent/services/label_printer/windows/bixolon_g30_windows_backend.dart';
import 'package:appfit_order_agent/services/label_printer/windows/windows_label_printer_backend.dart';

class WindowsLabelRouter {
  WindowsLabelRouter._();

  static final WindowsLabelRouter instance = WindowsLabelRouter._();

  BixolonG30WindowsBackend get _g30 => BixolonG30WindowsBackend.instance;

  bool get isAvailable => Platform.isWindows;

  /// 설정 UI "연결됨".
  ///
  /// G30 은 열린 핸들이라는 개념이 없어 **직전 검출 결과**를 그대로 쓴다. 갱신은
  /// [warmupOpen] 이 한다 — `PrintService.checkConnection` 이 `isOpen == false`
  /// 일 때 [warmupOpen] 을 부르는 기존 흐름에 그대로 얹힌다.
  bool get isOpen => _g30.isPresent || WindowsLabelPrinterBackend.instance.isOpen;

  /// 연결된 라벨 프린터의 사용자 표시용 기종명. 미연결이면 null.
  ///
  /// G30 이 아니면 오픈에 성공한 포트 문자열(enum 디바이스 경로 `vid_XXXX` 또는
  /// whitelist `VID:0xXXXX`)에서 VID/PID 를 추출해 매핑한다.
  String? get connectedModelName {
    if (_g30.isPresent) return kBixolonG30ModelName;
    if (WindowsLabelPrinterBackend.instance.isOpen) {
      final port =
          WindowsLabelPrinterBackend.instance.openedPortName?.toLowerCase() ??
              '';
      if (port.contains('0fe6')) return 'REXOD RXLA-561';
      if (port.contains('4b43') && port.contains('3538')) return 'Caysn D2';
      if (port.contains('4b43') && port.contains('3830')) return 'Caysn D3';
      return 'Caysn/REXOD';
    }
    return null;
  }

  /// [width] / [height] 는 Caysn 백엔드의 `PageBegin` 전용이다. G30 경로는
  /// PNG 를 디코드해 실제 치수를 얻으므로 이 값을 쓰지 않는다 — 연속용지라
  /// 장마다 높이가 달라 애초에 상수로 표현할 수 없다.
  Future<bool> printPng({
    required Uint8List pngBytes,
    required int width,
    required int height,
    required LabelPrinterOptions options,
    required String orderNo,
    required int labelIndex,
    required int totalLabels,
  }) async {
    if (!isAvailable) return false;
    if (_g30.isPresent) {
      return _g30.printPng(pngBytes);
    }
    return WindowsLabelPrinterBackend.instance.printPng(
      pngBytes: pngBytes,
      width: width,
      height: height,
      options: options,
      orderNo: orderNo,
      labelIndex: labelIndex,
      totalLabels: totalLabels,
    );
  }

  /// 벤더 재평가 + 연결 준비. 연결 상태 갱신의 **단일 진입점**이다.
  ///
  /// G30 검출을 먼저 하고, 붙어 있으면 Caysn 경로로 내려가지 않는다(파일 상단 ★).
  Future<bool> warmupOpen({required int autoReplyMode}) async {
    if (!isAvailable) return false;
    if (await _g30.detect()) return true;
    return WindowsLabelPrinterBackend.instance
        .warmupOpen(autoReplyMode: autoReplyMode);
  }

  /// 앱 종료 시 백엔드 정리 (미연결이면 no-op).
  void dispose() {
    _g30.dispose();
    WindowsLabelPrinterBackend.instance.dispose();
  }
}
