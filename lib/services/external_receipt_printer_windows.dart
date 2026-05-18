import 'dart:typed_data';

import '../utils/logger.dart';
import 'com_port_print_service.dart';
import 'preference_service.dart';
import 'printer_transport.dart';
import 'winspool_raw_client.dart';

/// Windows 전용 외부 영수증 프린터 transport.
///
/// 이 파일은 [ExternalReceiptPrinter] 와 [PrintService] 에서 `deferred as` 로
/// import 되어 Android 런타임에는 절대 로드되지 않는다. (win32 / serial_port_win32
/// 패키지의 native static initializer 가 안드로이드에서 `kernel32.dll` lookup 을
/// 시도해 실패하기 때문 — 클래스 reference 자체가 안드로이드에서 발생하지 않도록
/// 격리한다.)
///
/// COM 포트가 설정돼 있으면 우선 사용(PR800 등 시리얼), 실패 시 Winspool RAW 로 폴백.

/// [PrinterJobQueue] 가 사용하는 Windows transport 어댑터. 점유 충돌
/// 시 [PrinterBusy] 로 분류해 큐가 backoff 재시도하도록 한다.
class WindowsTransport implements PrinterTransport {
  const WindowsTransport();

  @override
  Future<PrinterTransportResult> send(Uint8List bytes, String jobName) async {
    final pref = PreferenceService();
    final comPort = pref.getComPortName();
    final printerName = _resolvePrinter();

    // 1) COM 포트 우선
    if (comPort != null && comPort.isNotEmpty) {
      try {
        final comOk = await ComPortPrintService.sendRaw(
          bytes,
          comPort: comPort,
          baudRate: pref.getComPortBaudRate(),
        );
        if (comOk) return const PrinterSuccess();
      } catch (e) {
        logger.w('[WindowsTransport] COM 출력 실패: $e');
      }
      if (printerName == null || printerName.isEmpty) {
        return PrinterBusy('COM port=$comPort open/write failed');
      }
    }

    // 2) Winspool 폴백 (또는 COM 미설정 시 1차 경로)
    if (printerName == null || printerName.isEmpty) {
      return const PrinterNoDevice('no Windows printer configured');
    }
    try {
      final ok = WinspoolRawClient.sendRaw(printerName, jobName, bytes);
      if (ok) return const PrinterSuccess();
      if (comPort != null && comPort.isNotEmpty) {
        return PrinterBusy('COM and Winspool both failed for $printerName');
      }
      return PrinterTransportError('Winspool sendRaw failed for $printerName');
    } catch (e) {
      return PrinterTransportError('Winspool exception: $e');
    }
  }
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
