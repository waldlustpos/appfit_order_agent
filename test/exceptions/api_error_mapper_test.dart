import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appfit_order_agent/exceptions/api_error_mapper.dart';
import 'package:appfit_order_agent/exceptions/api_exceptions.dart';
import 'package:appfit_order_agent/i18n/strings.g.dart';

/// 지정한 status/data 로 badResponse DioException 을 만든다.
DioException _dioWith({int? status, Object? data}) {
  final req = RequestOptions(path: '/v0/project/info');
  return DioException(
    requestOptions: req,
    type: DioExceptionType.badResponse,
    response: status == null
        ? null
        : Response(requestOptions: req, statusCode: status, data: data),
  );
}

void main() {
  // logToFile/MonitoringService 등이 binding 을 건드릴 수 있어 초기화.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('mapDioErrorToApiException', () {
    test('404 + 서버 한국어 message → 서버 message 그대로 노출', () {
      final e = _dioWith(status: 404, data: {
        'code': 'NOT_FOUND_PROJECT_API_KEY',
        'message': '요청한 프로젝트 API Key 를 찾을 수 없습니다.',
      });
      final result = mapDioErrorToApiException(e, StackTrace.current);
      expect(result, isA<ApiException>());
      expect(result.message, '요청한 프로젝트 API Key 를 찾을 수 없습니다.');
    });

    test('404 + body 없음 → not_found i18n 폴백', () {
      final e = _dioWith(status: 404, data: null);
      final result = mapDioErrorToApiException(e, StackTrace.current);
      expect(result.message, t.common.api_error.not_found);
    });

    test('401 → auth i18n 폴백', () {
      final e = _dioWith(status: 401, data: null);
      final result = mapDioErrorToApiException(e, StackTrace.current);
      expect(result.message, t.common.api_error.auth);
    });

    test('500 → server i18n 폴백', () {
      final e = _dioWith(status: 500, data: {'code': 'X'}); // message 없음
      final result = mapDioErrorToApiException(e, StackTrace.current);
      expect(result.message, t.common.api_error.server);
    });

    test('connectionError → network i18n 폴백', () {
      final e = DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: DioExceptionType.connectionError,
      );
      final result = mapDioErrorToApiException(e, StackTrace.current);
      expect(result.message, t.common.api_error.network);
    });

    test('receiveTimeout → timeout i18n 폴백', () {
      final e = DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: DioExceptionType.receiveTimeout,
      );
      final result = mapDioErrorToApiException(e, StackTrace.current);
      expect(result.message, t.common.api_error.timeout);
    });

    test('response.data 가 Map 이 아님(String) → status 폴백', () {
      final e = _dioWith(status: 404, data: '<html>Not Found</html>');
      final result = mapDioErrorToApiException(e, StackTrace.current);
      expect(result.message, t.common.api_error.not_found);
    });

    test('서버 message 가 과도하게 길면(>200) status 폴백', () {
      final longMsg = '가' * 201;
      final e = _dioWith(status: 500, data: {'message': longMsg});
      final result = mapDioErrorToApiException(e, StackTrace.current);
      expect(result.message, t.common.api_error.server);
    });

    test('서버 message 가 빈 문자열 → status 폴백', () {
      final e = _dioWith(status: 404, data: {'message': '   '});
      final result = mapDioErrorToApiException(e, StackTrace.current);
      expect(result.message, t.common.api_error.not_found);
    });

    test('이미 ApiException 이면 동일 객체 반환(멱등)', () {
      final original = ApiException('이미 변환된 메시지');
      final result = mapDioErrorToApiException(original, StackTrace.current);
      expect(identical(result, original), isTrue);
    });

    test('DioException/ApiException 아닌 일반 예외 → generic 폴백', () {
      final result =
          mapDioErrorToApiException(StateError('boom'), StackTrace.current);
      expect(result.message, t.common.api_error.generic);
    });

    test('원본 예외와 스택트레이스를 보존한다', () {
      final e = _dioWith(status: 404, data: {'message': '없음'});
      final st = StackTrace.current;
      final result = mapDioErrorToApiException(e, st);
      expect(result.originalException, same(e));
      expect(result.originalStackTrace, same(st));
    });
  });
}
