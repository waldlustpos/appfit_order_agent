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

/// [PrinterJobQueue] 가 사용하는 Windows transport 어댑터.
///
/// 매장 운영 환경은 USB-Serial 가상 COM 포트(D3MINI + NXP CDC 등) 가 표준이라
/// COM 경로를 단일 source of truth 로 쓴다. [ComPortPrintService] 가 ESC/POS
/// DLE EOT 1 핑으로 디바이스 생존을 사전 확인하므로 false-success 가 발생하지
/// 않는다. 실패 시 [PrinterBusy] 로 분류해 [PrinterJobQueue] backoff 재시도를
/// 유도한다 (사용자 시나리오: 끄기 -> 재출력 -> 켜기 -> 자동 출력).
///
/// COM 이 설정되지 않은 매장은 안전망으로 Winspool RAW 로 폴백. Winspool 은
/// 스풀러 단계에서 큐잉만 검증되고 실제 디바이스 IO 여부는 알기 어려우므로
/// 가급적 COM 설정을 권장한다.
class WindowsTransport implements PrinterTransport {
  const WindowsTransport();

  @override
  Future<PrinterTransportResult> send(Uint8List bytes, String jobName) async {
    final pref = PreferenceService();
    final comPort = pref.getComPortName();

    // 1) COM 우선 (매장 운영 표준 경로). probe 통과 후에만 출력 성공.
    if (comPort != null && comPort.isNotEmpty) {
      try {
        final comOk = await ComPortPrintService.sendRaw(
          bytes,
          comPort: comPort,
          baudRate: pref.getComPortBaudRate(),
        );
        if (comOk) return const PrinterSuccess();
      } catch (e) {
        logger.w('[WindowsTransport] COM 출력 예외: $e');
      }
      // probe 실패 / open 실패 / write 예외 모두 동일 backoff 대상.
      // Winspool 폴백을 의도적으로 안 하는 이유:
      //   - 동일 물리 디바이스 -> Winspool 도 OFFLINE 일 가능성 큼
      //   - Winspool RAW 는 OS 스풀러까지만 동기 확인 -> false-success 위험
      //   - 매장 운영 환경에서는 COM 단일 경로 사용 (사용자 합의)
      return PrinterBusy('COM $comPort offline/busy/write-failed');
    }

    // 2) Winspool 폴백 (COM 미설정 환경 안전망)
    final printerName = _resolvePrinter();
    if (printerName == null || printerName.isEmpty) {
      return const PrinterNoDevice('no Windows printer configured');
    }
    try {
      final ok = WinspoolRawClient.sendRaw(printerName, jobName, bytes);
      if (ok) return const PrinterSuccess();
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
