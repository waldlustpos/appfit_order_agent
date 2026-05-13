import 'dart:typed_data';

import '../utils/logger.dart';
import 'com_port_print_service.dart';
import 'preference_service.dart';
import 'winspool_raw_client.dart';

/// Windows 전용 외부 영수증 프린터 transport.
///
/// 이 파일은 [ExternalReceiptPrinter] 에서 `deferred as` 로 import 되어 Android
/// 런타임에는 절대 로드되지 않는다. (win32 / serial_port_win32 패키지의 native
/// static initializer 가 안드로이드에서 `kernel32.dll` lookup 을 시도해 실패하기
/// 때문 — 클래스 reference 자체가 안드로이드에서 발생하지 않도록 격리한다.)
///
/// COM 포트가 설정돼 있으면 우선 사용(PR800 등 시리얼), 실패 시 Winspool RAW 로 폴백.
Future<bool> sendBytes(Uint8List data, String jobName) async {
  final pref = PreferenceService();
  final printerName = _resolvePrinter();
  if (printerName == null) {
    logger.e('[ExternalReceiptPrinterWindows] 프린터 미설정 — 출력 생략');
    return false;
  }
  final comPort = pref.getComPortName();
  if (comPort != null && comPort.isNotEmpty) {
    try {
      final comOk = await ComPortPrintService.sendRaw(
        data,
        comPort: comPort,
        baudRate: pref.getComPortBaudRate(),
      );
      if (comOk) return true;
    } catch (e) {
      logger.w('[ExternalReceiptPrinterWindows] COM 출력 실패, Winspool 폴백: $e');
    }
  }
  return WinspoolRawClient.sendRaw(printerName, jobName, data);
}

/// COM 포트 enumerate 또는 Winspool default printer 확인.
bool isConnected() {
  final comPort = PreferenceService().getComPortName();
  if (comPort != null && comPort.isNotEmpty) {
    return ComPortPrintService.getAvailableComPorts().contains(comPort);
  }
  return _resolvePrinter() != null;
}

/// Windows 설정 UI 에서 COM 포트 드롭다운 채우는 용도.
List<String> getAvailableComPorts() =>
    ComPortPrintService.getAvailableComPorts();

String? _resolvePrinter() {
  final configured = PreferenceService().getWindowsPrinterName();
  if (configured != null && configured.isNotEmpty) return configured;
  return WinspoolRawClient.getDefaultPrinterName();
}
