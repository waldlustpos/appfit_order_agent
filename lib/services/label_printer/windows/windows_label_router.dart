// Windows 라벨 프린터 벤더 라우터 — Caysn(REXOD RXLA-561 등) vs BIXOLON(XD5-40d).
//
// Android NativeMethodHandler 의 printLabel 분기와 동일한 정책:
// - 매 호출마다 USB VID 0x1504 존재를 재평가 (attach/detach stale 방지).
// - 두 벤더 동시 연결 시 BIXOLON 우선.
// - intra-print fallback 없음 — 실패 시 Dart 재시도(1.5s)가 재선택하므로
//   분리된 BIXOLON 은 다음 시도에서 자연스럽게 Caysn 으로 넘어간다.
//
// 호출부(main.dart warmup/dispose, print_service.dart checkConnection/printLabel)
// 는 기존 WindowsLabelPrinterBackend.instance 대신 이 라우터만 바라본다.

import 'dart:io';
import 'dart:typed_data';

import 'package:appfit_order_agent/services/label_printer/label_printer_options.dart';
import 'package:appfit_order_agent/services/label_printer/windows/bixolon_usb_presence_windows.dart'
    deferred as bxl_scan;
import 'package:appfit_order_agent/services/label_printer/windows/bxllapi_bindings.dart';
import 'package:appfit_order_agent/services/label_printer/windows/bixolon_windows_label_backend.dart';
import 'package:appfit_order_agent/services/label_printer/windows/windows_label_printer_backend.dart';
import 'package:appfit_order_agent/utils/logger.dart';

class WindowsLabelRouter {
  WindowsLabelRouter._();

  static final WindowsLabelRouter instance = WindowsLabelRouter._();

  bool get isAvailable => Platform.isWindows;

  /// 설정 UI "연결됨" = 어느 한쪽 벤더라도 열려 있으면 true.
  bool get isOpen =>
      BixolonWindowsLabelBackend.instance.isOpen ||
      WindowsLabelPrinterBackend.instance.isOpen;

  /// 연결된 라벨 프린터의 사용자 표시용 기종명. 미연결이면 null.
  /// Caysn 쪽은 오픈에 성공한 포트 문자열(enum 디바이스 경로 `vid_XXXX` 또는
  /// whitelist `VID:0xXXXX`)에서 VID/PID 를 추출해 매핑한다.
  String? get connectedModelName {
    if (BixolonWindowsLabelBackend.instance.isOpen) return 'BIXOLON XD5-40d';
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

  /// BIXOLON 경로를 쓸지 결정. ①이미 열려 있으면 그대로(자연 캐시),
  /// ②DLL 로드 불가면 Caysn (스캔 불필요), ③VID 0x1504 스캔.
  Future<bool> _useBixolon() async {
    if (!Platform.isWindows) return false;
    if (BixolonWindowsLabelBackend.instance.isOpen) return true;
    // DLL 미배치 fleet 에서 스캔/실패 왕복 없이 즉시 Caysn 으로.
    if (BxlLapiBindings.tryGet() == null) return false;
    try {
      await bxl_scan.loadLibrary();
      return await bxl_scan.isBixolonUsbPresent();
    } catch (e, s) {
      logger.w('[Label][Router] BIXOLON VID 스캔 실패 — Caysn 경로 사용',
          error: e, stackTrace: s);
      return false;
    }
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
    if (await _useBixolon()) {
      // Caysn 전용 knob(options)은 BIXOLON 경로에서 무의미 — 전달하지 않는다.
      return BixolonWindowsLabelBackend.instance.printPng(
        pngBytes: pngBytes,
        width: width,
        height: height,
        orderNo: orderNo,
        labelIndex: labelIndex,
        totalLabels: totalLabels,
      );
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

  Future<bool> warmupOpen({required int autoReplyMode}) async {
    if (!isAvailable) return false;
    if (await _useBixolon()) {
      return BixolonWindowsLabelBackend.instance.warmupOpen();
    }
    return WindowsLabelPrinterBackend.instance
        .warmupOpen(autoReplyMode: autoReplyMode);
  }

  /// 앱 종료 시 양쪽 백엔드 정리 (각자 미연결이면 no-op).
  void dispose() {
    BixolonWindowsLabelBackend.instance.dispose();
    WindowsLabelPrinterBackend.instance.dispose();
  }
}
