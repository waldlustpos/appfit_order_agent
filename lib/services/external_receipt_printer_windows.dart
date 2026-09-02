import 'dart:typed_data';

import 'package:appfit_order_agent/utils/logger.dart';
import 'package:appfit_order_agent/services/com_port_descriptor.dart';
import 'package:appfit_order_agent/services/com_port_print_service.dart';
import 'package:appfit_order_agent/services/preference_service.dart';
import 'package:appfit_order_agent/services/printer_transport.dart';
import 'package:appfit_order_agent/services/usb_print_descriptor.dart';
import 'package:appfit_order_agent/services/usb_print_service.dart';

/// Windows 전용 외부 영수증 프린터 transport.
///
/// 이 파일은 [ExternalReceiptPrinter] 와 [PrintService] 에서 `deferred as` 로
/// import 되어 Android 런타임에는 절대 로드되지 않는다. (win32 / serial_port_win32
/// 패키지의 native static initializer 가 안드로이드에서 `kernel32.dll` lookup 을
/// 시도해 실패하기 때문 — 클래스 reference 자체가 안드로이드에서 발생하지 않도록
/// 격리한다.)
///
/// ## 지원하는 두 경로
///
/// 같은 USB 영수증 프린터라도 Windows 드라이버 바인딩이 갈린다. 어느 쪽을 쓸지는
/// **사용자가 설정에서 명시적으로 고르며**([PreferenceService.getExternalPrinterConnection]),
/// 기본값은 COM 이라 기존 현장 단말의 동작은 변하지 않는다.
///
/// - **COM**: 프린터가 CDC-ACM 을 노출해 가상 COM 포트가 생기는 경우
///   (PR800 = `USB\VID_0D28&PID_4C59`). [ComPortPrintService].
/// - **usbprint**: USB Printer class 만 노출해 usbprint.sys 가 붙고 COM 이 없는
///   경우 (POSBANK A8 = `USB\VID_0483&PID_A319`). [UsbPrintService] 가 장치
///   인터페이스를 `CreateFile`/`WriteFile` 로 직접 연다.
///
/// ## Winspool RAW 는 여전히 배제되어 있다
///
/// 사용자가 명시 설정하지 않은 OS default 프린터(라벨 프린터 / Microsoft Print to
/// PDF 등) 가 외부 영수증으로 잘못 잡혀 isConnected 가 false-positive 가 되거나
/// 실제 영수증이 라벨 프린터로 송출되는 사고를 차단하기 위함이다.
/// **usbprint 경로는 이 금지에 해당하지 않는다** — 스풀러/프린터 큐/기본 프린터를
/// 전혀 경유하지 않고, 자동 선택이 없으며, 라벨 프린터 VID 를 열거에서 제외한다.
/// 근거 전문은 [UsbPrintService] 헤더 주석에 있다.

/// [PrinterJobQueue] 가 사용하는 Windows transport 어댑터.
///
/// 두 경로 모두 **송출 전에 디바이스 생존을 확인**하므로 false-success 가 발생하지
/// 않는다 (COM: DLE EOT 1 핑 / usbprint: DIGCF_PRESENT 열거). 실패 시 사유별로
/// PrinterNoDevice / PrinterBusy / PrinterTransportError 로 분류해 [PrinterJobQueue]
/// backoff 재시도를 유도한다 (사용자 시나리오: 끄기 -> 재출력 -> 켜기 -> 자동 출력).
class WindowsTransport implements PrinterTransport {
  const WindowsTransport();

  @override
  Future<PrinterTransportResult> send(Uint8List bytes, String jobName) async {
    final pref = PreferenceService();
    return pref.getExternalPrinterConnection() ==
            PreferenceService.extPrinterConnUsbPrint
        ? _sendUsbPrint(pref, bytes)
        : _sendCom(pref, bytes);
  }

  Future<PrinterTransportResult> _sendCom(
      PreferenceService pref, Uint8List bytes) async {
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

  Future<PrinterTransportResult> _sendUsbPrint(
      PreferenceService pref, Uint8List bytes) async {
    final path = pref.getUsbPrintDevicePath();

    // 미선택은 미연결과 같다 — 자동으로 아무 프린터나 고르지 않는다.
    if (path == null || path.isEmpty) {
      return const PrinterNoDevice('no USB print device configured');
    }

    try {
      final ok = await UsbPrintService.sendRaw(bytes, devicePath: path);
      if (ok) return const PrinterSuccess();
    } catch (e) {
      logger.w('[WindowsTransport] usbprint 출력 예외: $e');
    }

    final reason = UsbPrintService.lastFailureReason;
    switch (reason) {
      case 'not-enumerated':
        return PrinterNoDevice('usbprint not enumerated ($reason)');
      case 'open-access-denied':
        return const PrinterBusy('usbprint access denied (프린터 큐/외부 유틸 점유 의심)');
      case 'write-failed':
        return const PrinterTransportError('usbprint write failed');
      case 'open-failed':
        return PrinterTransportError('usbprint open failed ($reason)');
      default:
        return const PrinterBusy('usbprint offline/busy/write-failed');
    }
  }
}

/// 외부 ESC/POS 프린터의 실제 연결(생존) 여부 판단. 저장된 연결 방식에 따라 갈린다.
///
/// **COM**: 포트 enumerate 존재만으로는 USB-Serial CDC 칩이 프린터 본체 전원 OFF
/// 에도 PC USB bus power 로 살아있어 false-positive 가 된다(설정 화면 "연결됨"
/// 오탐). [ComPortPrintService.probeConnection] 이 DLE EOT 1 핑으로 print head
/// 생존까지 검증하므로 정확하다. (Android 의 verifyConnection ESC @ 핑과 대칭.)
///
/// **usbprint**: devnode 가 전원 OFF/분리 시 사라지므로 열거 자체가 정직한 신호다.
/// 그 위에 [UsbPrintService.probeConnection] 이 ESC @ write 로 쓰기 가능까지 본다.
Future<bool> isConnected() async {
  final pref = PreferenceService();
  if (pref.getExternalPrinterConnection() ==
      PreferenceService.extPrinterConnUsbPrint) {
    final path = pref.getUsbPrintDevicePath();
    if (path == null || path.isEmpty) return false;
    return UsbPrintService.probeConnection(devicePath: path);
  }
  final comPort = pref.getComPortName();
  if (comPort == null || comPort.isEmpty) return false;
  return ComPortPrintService.probeConnection(
    comPort: comPort,
    baudRate: pref.getComPortBaudRate(),
  );
}

/// Windows 설정 UI 에서 COM 포트 드롭다운 채우는 용도.
List<String> getAvailableComPorts() =>
    ComPortPrintService.getAvailableComPorts();

/// COM 포트 목록 + 각 포트에 물린 장치 식별 정보 (설정 화면 드롭다운 / 진단 로그).
///
/// 반환 타입 [ComPortDescriptor] 는 native 의존이 없는 별도 파일에 있다 —
/// 이 라이브러리는 UI 에서 `deferred as` 로만 로드되므로 여기 정의된 타입은
/// 위젯의 필드 타입으로 쓸 수 없다.
List<ComPortDescriptor> listComPorts() =>
    ComPortPrintService.getComPortDescriptors();

/// 재연결 버튼의 포트 스캔 전용 probe.
///
/// [isConnected] 와 달리 (1) 저장된 포트가 아니라 임의 포트를 지정하고,
/// (2) "최근 출력 성공" fast-path 를 우회한다. 사용자가 명시적으로 재확인을
/// 요청한 경로라 캐시된 판정을 그대로 돌려주면 안 되고, 스캔 중 모든 후보가
/// true 로 오탐하는 것도 막아야 하기 때문.
Future<bool> probeComPort(
  String comPort, {
  required int baudRate,
  required int maxAttempts,
}) =>
    ComPortPrintService.probeConnection(
      comPort: comPort,
      baudRate: baudRate,
      maxAttempts: maxAttempts,
      useRecentSendFastPath: false,
    );

/// 설정 화면 usbprint 드롭다운 채우는 용도. 라벨 프린터는 제외되어 나온다.
///
/// 반환 타입 [UsbPrintDescriptor] 는 [ComPortDescriptor] 와 같은 이유로 native
/// 의존이 없는 별도 파일에 있다 — 이 라이브러리는 UI 에서 `deferred as` 로만
/// 로드되므로 여기 정의된 타입은 위젯의 필드 타입으로 쓸 수 없다.
List<UsbPrintDescriptor> listUsbPrintDevices() => UsbPrintService.enumerate();

/// 재연결 버튼의 usbprint 장치 probe. [probeComPort] 와 짝.
Future<bool> probeUsbPrintDevice(String devicePath) =>
    UsbPrintService.probeConnection(devicePath: devicePath);
