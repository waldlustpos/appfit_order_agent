import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/services.dart';

import 'package:appfit_order_agent/services/platform_service.dart';

/// 프린터 transport 1회 호출 결과.
///
/// success 외의 모든 결과는 [PrinterJobQueue] 재시도 정책의 대상이다.
/// 분류 의미:
///   busy           : 다른 프로세스/세션이 디바이스를 점유 중. 재시도 시 풀릴 가능성 큼.
///   noDevice       : 디바이스 자체가 enumerate 되지 않음(미연결/단선).
///   transportError : open 까지는 됐지만 write 도중 실패.
/// 셋 다 동일한 backoff 로 재시도하지만 로깅을 통해 운영 진단을 돕는다.
sealed class PrinterTransportResult {
  const PrinterTransportResult();
  bool get isSuccess => this is PrinterSuccess;
}

final class PrinterSuccess extends PrinterTransportResult {
  const PrinterSuccess();
  @override
  String toString() => 'PrinterSuccess';
}

final class PrinterBusy extends PrinterTransportResult {
  const PrinterBusy(this.reason);
  final String reason;
  @override
  String toString() => 'PrinterBusy($reason)';
}

final class PrinterNoDevice extends PrinterTransportResult {
  const PrinterNoDevice(this.reason);
  final String reason;
  @override
  String toString() => 'PrinterNoDevice($reason)';
}

final class PrinterTransportError extends PrinterTransportResult {
  const PrinterTransportError(this.reason);
  final String reason;
  @override
  String toString() => 'PrinterTransportError($reason)';
}

/// 외부 영수증 프린터로 바이트 1회 송출.
///
/// Windows 구현([WindowsTransport])은 win32 / serial_port_win32 의존성 때문에
/// 별도의 deferred-loaded 파일 ([external_receipt_printer_windows.dart]) 에 위치한다.
/// Android 런타임이 win32 static initializer 를 로드해 kernel32.dll lookup 으로
/// 크래시하지 않도록 본 파일에는 Android transport 만 둔다.
abstract class PrinterTransport {
  Future<PrinterTransportResult> send(Uint8List bytes, String jobName);
}

/// Android UsbReceiptPrinter (MethodChannel 'printReceiptBytes') 어댑터.
///
/// native 측은 실패 사유를 PlatformException.code 로 구분해서 던진다:
///   BUSY            -> claim/open 실패. 점유 의심.
///   NO_DEVICE       -> usbManager.openDevice null / 미연결.
///   TRANSPORT_ERROR -> bulkTransfer 도중 실패.
///   INVALID_ARGUMENT-> bytes null/empty.
class AndroidUsbTransport implements PrinterTransport {
  const AndroidUsbTransport();

  @override
  Future<PrinterTransportResult> send(Uint8List bytes, String jobName) async {
    // PrinterJobQueue 의 0/2/5/10/20/40/60s backoff 7단계를 결정적으로 검증하기
    // 위한 debug-only 진입점. Android USB Host API 는 claimInterface(force=true)
    // 라 외부 도구만으로 점유 충돌을 재현할 수 없으므로, 디버그 빌드에서만
    // 카운터가 양수일 때 native 호출 없이 즉시 PrinterBusy 를 반환한다.
    if (kDebugMode && DebugPrinterFault.consumeOne()) {
      return const PrinterBusy('debug-injected BUSY');
    }
    try {
      final ok = await platform.invokeMethod<bool>(
        'printReceiptBytes',
        {'bytes': bytes, 'jobName': jobName},
      );
      if (ok == true) return const PrinterSuccess();
      // 구버전 native 와의 호환: false 반환 자체는 transport 단계 실패로 간주.
      return const PrinterTransportError('printReceiptBytes returned false');
    } on PlatformException catch (e) {
      switch (e.code) {
        case 'BUSY':
          return PrinterBusy(e.message ?? 'claim/open failed');
        case 'NO_DEVICE':
          return PrinterNoDevice(e.message ?? 'device not attached');
        case 'TRANSPORT_ERROR':
          return PrinterTransportError(e.message ?? 'bulkTransfer failed');
        case 'INVALID_ARGUMENT':
          return PrinterTransportError(e.message ?? 'invalid argument');
        default:
          return PrinterTransportError('${e.code}: ${e.message ?? ''}');
      }
    } catch (e) {
      return PrinterTransportError('$e');
    }
  }
}

/// Debug 빌드 전용 BUSY 주입 카운터.
///
/// Windows 는 PowerShell 로 COM 포트를 점유하면 자연스럽게 [PrinterJobQueue]
/// 의 0/2/5/10/20/40/60s 백오프를 관찰할 수 있지만, Android USB Host API 는
/// claimInterface(force=true) 로 점유를 강제 탈취하므로 외부 도구만으로는 BUSY
/// 시나리오를 결정적으로 재현할 수 없다. 디버그 빌드에서 본 카운터를 N 으로
/// 세팅하면 다음 N 회의 [AndroidUsbTransport.send] 호출이 native 진입 없이 즉시
/// PrinterBusy 를 반환해 backoff 전 구간 검증이 가능하다.
///
/// 호출은 단일 event loop (Dart) 에서 직렬화되므로 별도 동기화 불필요.
/// 릴리즈 빌드(kReleaseMode)에서는 호출부가 가드되어 dead-code 가 된다.
class DebugPrinterFault {
  DebugPrinterFault._();

  static int _remaining = 0;

  /// 잔여 강제 BUSY 회수. UI 표시용.
  static int get remaining => _remaining;

  /// 다음 [n] 회 출력 시도를 강제 BUSY 로 만든다. [n] 이 0 이하면 해제.
  static void schedule(int n) {
    _remaining = n < 0 ? 0 : n;
  }

  /// 카운터가 양수면 1 감소시키고 true 를 반환. 그 외에는 false.
  /// [AndroidUsbTransport.send] 진입부에서만 호출되어야 한다.
  static bool consumeOne() {
    if (_remaining <= 0) return false;
    _remaining -= 1;
    return true;
  }
}
