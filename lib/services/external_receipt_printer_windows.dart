import 'dart:typed_data';

import '../utils/logger.dart';
import 'com_port_print_service.dart';
import 'preference_service.dart';
import 'printer_transport.dart';

/// Windows 전용 외부 영수증 프린터 transport.
///
/// 이 파일은 [ExternalReceiptPrinter] 와 [PrintService] 에서 `deferred as` 로
/// import 되어 Android 런타임에는 절대 로드되지 않는다. (win32 / serial_port_win32
/// 패키지의 native static initializer 가 안드로이드에서 `kernel32.dll` lookup 을
/// 시도해 실패하기 때문 — 클래스 reference 자체가 안드로이드에서 발생하지 않도록
/// 격리한다.)
///
/// 매장 운영 환경은 USB-Serial 가상 COM 포트(D3MINI + NXP CDC 등) 단일 source
/// of truth. Winspool RAW 경로는 의도적으로 제거됨 — 사용자가 명시 설정하지
/// 않은 OS default 프린터(라벨 프린터 / Microsoft Print to PDF 등) 가 외부
/// 영수증으로 잘못 잡혀 isConnected 가 false-positive 가 되거나 실제 영수증이
/// 라벨 프린터로 송출되는 사고를 차단한다.

/// [PrinterJobQueue] 가 사용하는 Windows transport 어댑터.
///
/// [ComPortPrintService] 가 ESC/POS DLE EOT 1 핑으로 디바이스 생존을 사전
/// 확인하므로 false-success 가 발생하지 않는다. 실패 시 사유별로 PrinterNoDevice
/// / PrinterBusy / PrinterTransportError 로 분류해 [PrinterJobQueue] backoff
/// 재시도를 유도한다 (사용자 시나리오: 끄기 -> 재출력 -> 켜기 -> 자동 출력).
class WindowsTransport implements PrinterTransport {
  const WindowsTransport();

  @override
  Future<PrinterTransportResult> send(Uint8List bytes, String jobName) async {
    final pref = PreferenceService();
    final comPort = pref.getComPortName();

    if (comPort == null || comPort.isEmpty) {
      return const PrinterNoDevice('no COM port configured');
    }

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

    // ComPortPrintService 가 _lastFailureReason 에 정확한 사유를 기록하므로
    // 결과 타입을 PrinterBusy / PrinterNoDevice / PrinterTransportError 로
    // 분리해 큐 로그의 진단성을 높인다. (backoff 정책 자체는 동일.)
    final reason = ComPortPrintService.lastFailureReason;
    switch (reason) {
      case 'not-enumerated':
      case 'open-throws-file-not-found':
      case 'enumerate-timeout-after-close':
        return PrinterNoDevice('COM $comPort not enumerated ($reason)');
      case 'open-throws-access-denied':
        return PrinterBusy('COM $comPort access denied (외부 프로세스 점유 의심)');
      case 'open-failed-silent':
      case 'probe-timeout':
      case 'probe-write-failed':
        return PrinterBusy('COM $comPort offline/busy ($reason)');
      case 'write-exception':
        return PrinterTransportError('COM $comPort write failed');
      case 'open-throws-other':
        return PrinterTransportError('COM $comPort open failed ($reason)');
      default:
        return PrinterBusy('COM $comPort offline/busy/write-failed');
    }
  }
}

/// COM 포트가 설정되어 있고 현재 enumerate 결과에 존재하는지로 연결 여부 판단.
bool isConnected() {
  final comPort = PreferenceService().getComPortName();
  if (comPort == null || comPort.isEmpty) return false;
  return ComPortPrintService.getAvailableComPorts().contains(comPort);
}

/// Windows 설정 UI 에서 COM 포트 드롭다운 채우는 용도.
List<String> getAvailableComPorts() =>
    ComPortPrintService.getAvailableComPorts();
