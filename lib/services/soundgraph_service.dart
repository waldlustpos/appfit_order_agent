import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:appfit_order_agent/services/platform_service.dart';
import 'package:appfit_order_agent/utils/logger.dart';

class SoundGraphService {
  static const String _baseUrl = 'https://youframe-manager-mmth.appspot.com';
  static const String _sendPath = '/server/addDeliciousOrderData';
  static const String _authToken = 'Bearer SG245UILPISLEDFBLDUFJLQURJzKKXMLU9';

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ),
  );

  Future<bool> sendOrder(Map<String, dynamic> payload) async {
    try {
      final orderId = payload['orderId'] ?? '';
      logToFile(
        tag: LogTag.SOUNDGRAPH,
        message: 'Sending order: $orderId',
      );
      final response = await _dio.post(
        _baseUrl + _sendPath,
        data: payload,
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Authorization': _authToken,
          },
          responseType: ResponseType.json,
        ),
      );
      final body = response.data;
      if (body is Map<String, dynamic> && body.containsKey('meta')) {
        final meta = body['meta'];
        if (meta is Map && meta['code'] == 200) {
          logToFile(
            tag: LogTag.SOUNDGRAPH,
            message: 'Response OK for $orderId: ${body['data']}',
          );
          return true;
        }
        final msg = (meta is Map ? meta['msg'] : null) ?? 'unknown error';
        logToFile(
          tag: LogTag.ERROR,
          message:
              'SoundGraph send failed for $orderId — code: ${meta is Map ? meta['code'] : 'N/A'}, msg: $msg',
        );
        return false;
      }
      logToFile(
        tag: LogTag.ERROR,
        message: 'SoundGraph unexpected response for $orderId: $body',
      );
      return false;
    } catch (e, s) {
      logger.e('[SoundGraph] sendOrder error', error: e, stackTrace: s);
      return false;
    }
  }
}

final soundGraphServiceProvider =
    Provider<SoundGraphService>((_) => SoundGraphService());
