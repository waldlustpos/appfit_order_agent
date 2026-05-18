import 'package:flutter/services.dart';

import 'platform_service.dart';

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
