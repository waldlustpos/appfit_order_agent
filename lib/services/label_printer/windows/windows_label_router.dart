// Windows 라벨 프린터 벤더 라우팅 seam.
//
// ★ 지금 분기가 하나뿐인 것은 일시적 상태다 — "백엔드가 하나인데 왜 이 파일이
//   있는가" 의 답:
//
// - BIXOLON G30 의 Windows 이식(BXLPAPI)이 아직 미착수다. 착수하면
//   `connectedModelName` / `printPng` / `warmupOpen` 세 지점에 두 번째 분기가
//   그대로 들어온다. 그때 필요한 자리를 지금 없애면 호출부 6곳을 다시 뒤집어야
//   한다. (G30 은 Android 에서 UPOS/JavaPOS 를 쓰지만 Windows 는 BXLPAPI 로
//   명령셋이 또 다르다 — Android 코드를 그대로 옮길 수 없다.)
// - Android `NativeMethodHandler` 의 벤더 분기와 대칭을 유지하는 것이 목적이다.
//   호출부(main.dart warmup/dispose, print_service.dart checkConnection/printLabel,
//   설정 화면)는 백엔드를 직접 보지 않는다 — 이 불변식이 이 파일의 존재 이유다.
//
// 이력: 2026-07 ~ 2026-09 사이에는 BIXOLON XD5-40d 용 BXLLAPI FFI 백엔드가 두 번째
// 분기였다. XD5-40d 지원 종료와 함께 삭제됐다. 재이식 시 재사용할 결론(사전 이진화
// 임계 210 등)은 docs/PRINTER_FLOW.md §3.4 tombstone 과 메모리 노트
// project_bixolon_xd5_removal_residue.md 참조.

import 'dart:io';
import 'dart:typed_data';

import 'package:appfit_order_agent/services/label_printer/label_printer_options.dart';
import 'package:appfit_order_agent/services/label_printer/windows/windows_label_printer_backend.dart';

class WindowsLabelRouter {
  WindowsLabelRouter._();

  static final WindowsLabelRouter instance = WindowsLabelRouter._();

  bool get isAvailable => Platform.isWindows;

  /// 설정 UI "연결됨".
  bool get isOpen => WindowsLabelPrinterBackend.instance.isOpen;

  /// 연결된 라벨 프린터의 사용자 표시용 기종명. 미연결이면 null.
  /// 오픈에 성공한 포트 문자열(enum 디바이스 경로 `vid_XXXX` 또는 whitelist
  /// `VID:0xXXXX`)에서 VID/PID 를 추출해 매핑한다.
  String? get connectedModelName {
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

  Future<bool> warmupOpen({required int autoReplyMode}) async {
    if (!isAvailable) return false;
    return WindowsLabelPrinterBackend.instance
        .warmupOpen(autoReplyMode: autoReplyMode);
  }

  /// 앱 종료 시 백엔드 정리 (미연결이면 no-op).
  void dispose() {
    WindowsLabelPrinterBackend.instance.dispose();
  }
}
