import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:appfit_order_agent/models/waldpos_scan_result.dart';
import 'package:appfit_order_agent/services/platform_service.dart'
    show logToFile, LogTag;
import 'package:appfit_order_agent/services/waldpos/waldpos_a01.dart';

/// Windows 전용: waldpos_agent(로컬 VAN 브리지)에 A01 전문으로 바코드 스캔을 요청.
///
/// 경로: 앱 -> waldpos_agent(127.0.0.1:8888) -> VAN 모듈 -> 토스프런트.
/// UI 는 이 서비스를 직접 호출하지 않고 waldposScanProvider 를 경유한다.
class WaldposScanService {
  WaldposScanService(this._ref);

  // 현재는 host/port 고정이라 ref 미사용. 향후 설정 주입 대비 보관.
  // ignore: unused_field
  final Ref _ref;

  static const String _host = '127.0.0.1';
  static const int _port = 8888;
  static const Duration _connectTimeout = Duration(seconds: 2);

  /// 스캔은 고객이 단말에 바코드를 제시할 때까지 대기하므로 넉넉히 둔다.
  static const Duration _responseTimeout = Duration(seconds: 60);

  /// 바코드 스캔 요청(paymentInfo:"B"). 성공 시 barcode(cardNo) 반환.
  Future<WaldposScanResult> requestBarcodeScan() async {
    if (!Platform.isWindows) {
      return WaldposScanResult.failure(
        WaldposScanError.notSupported,
        'Windows 전용 기능입니다.',
      );
    }

    // 가이드 #6 의 Data 전문(paymentInfo:"B" = 바코드 요청).
    final dataMap = <String, String>{
      'payRequestType': 'DEVICE',
      'payType': '',
      'vanType': '',
      'terminalNo': '',
      'easyPayType': 'NULL',
      'amount': '',
      'vat': '',
      'taxFree': '',
      'installment': '',
      'cupDepositAmount': '',
      'barcodeNo': '',
      'approvalNo': '',
      'approvalDate': '',
      'cashType': '',
      'cashInfo': '',
      'paymentInfo': 'B',
    };
    // Data 는 JSON 문자열(이중 인코딩) -- 가이드/kiosk_v4 동일.
    final envelope = <String, dynamic>{
      'Command': 'Payment',
      'Data': jsonEncode(dataMap),
      'Tag': null,
    };

    Socket? socket;
    try {
      final frame = WaldposA01.buildFrame(jsonEncode(envelope));
      await logToFile(tag: LogTag.PLATFORM, message: '[waldpos] 스캔 요청 전송');

      socket = await Socket.connect(_host, _port, timeout: _connectTimeout);
      socket.add(frame);
      await socket.flush();

      final responseBytes =
          await _readUntilEtx(socket).timeout(_responseTimeout);

      final parsed = WaldposA01.parseResponse(responseBytes);
      final result = _interpret(parsed);
      await logToFile(
          tag: result.success ? LogTag.PLATFORM : LogTag.ERROR,
          message: '[waldpos] 스캔 결과 success=${result.success} '
              'error=${result.error}');
      return result;
    } on TimeoutException {
      await logToFile(tag: LogTag.ERROR, message: '[waldpos] 스캔 응답 시간 초과');
      return WaldposScanResult.failure(
          WaldposScanError.timeout, '스캔 응답 시간이 초과되었습니다.');
    } on WaldposA01Exception catch (e) {
      await logToFile(tag: LogTag.ERROR, message: '[waldpos] 응답 파싱 오류: $e');
      return WaldposScanResult.failure(
          WaldposScanError.crcMismatch, '스캔 응답을 해석할 수 없습니다.');
    } on SocketException catch (e) {
      await logToFile(
          tag: LogTag.ERROR, message: '[waldpos] 소켓 연결 실패: ${e.message}');
      return WaldposScanResult.failure(
        WaldposScanError.connectionFailed,
        '결제 단말(waldpos_agent)에 연결할 수 없습니다.',
      );
    } catch (e) {
      await logToFile(tag: LogTag.ERROR, message: '[waldpos] 스캔 오류: $e');
      return WaldposScanResult.failure(
          WaldposScanError.unknown, '스캔 중 오류가 발생했습니다.');
    } finally {
      socket?.destroy();
    }
  }

  /// ETX(0x03)를 만날 때까지 응답 바이트를 누적한다(멀티 청크 대응).
  Future<List<int>> _readUntilEtx(Socket socket) {
    final buffer = <int>[];
    final completer = Completer<List<int>>();
    late final StreamSubscription<Uint8List> sub;
    sub = socket.listen(
      (Uint8List chunk) {
        buffer.addAll(chunk);
        if (buffer.isNotEmpty && buffer.last == WaldposA01.etx) {
          if (!completer.isCompleted) {
            completer.complete(List<int>.from(buffer));
          }
          sub.cancel();
        }
      },
      onError: (Object e, StackTrace s) {
        if (!completer.isCompleted) completer.completeError(e, s);
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete(List<int>.from(buffer));
      },
      cancelOnError: true,
    );
    return completer.future;
  }

  /// `{ResultCode, ResultMessage}` 를 해석해 결과로 변환한다.
  /// ResultMessage 는 JSON 문자열이며 returnValue == "1" + cardNo 가 성공 조건.
  WaldposScanResult _interpret(Map<String, dynamic> parsed) {
    final resultCode = parsed['ResultCode']?.toString() ?? '';
    final messageRaw = parsed['ResultMessage'];
    var msg = <String, dynamic>{};
    if (messageRaw is String && messageRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(messageRaw);
        if (decoded is Map<String, dynamic>) msg = decoded;
      } catch (_) {
        // ResultMessage 가 JSON 이 아닌 평문일 수 있음 -> 그대로 사유 처리.
        return WaldposScanResult.failure(WaldposScanError.declined, messageRaw);
      }
    } else if (messageRaw is Map<String, dynamic>) {
      msg = messageRaw;
    }

    final returnValue = msg['returnValue']?.toString() ?? '';
    final cardNo = msg['cardNo']?.toString() ?? '';
    final message1 = msg['message1']?.toString() ?? '';
    final message2 = msg['message2']?.toString() ?? '';

    if (resultCode == '0000' && returnValue == '1' && cardNo.isNotEmpty) {
      return WaldposScanResult.success(cardNo);
    }
    final reason =
        [message1, message2].where((s) => s.isNotEmpty).join(' ').trim();
    return WaldposScanResult.failure(
      WaldposScanError.declined,
      reason.isNotEmpty ? reason : '스캔에 실패했습니다.',
    );
  }
}
