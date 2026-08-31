import 'package:appfit_core/appfit_core.dart';
import 'package:appfit_order_agent/services/appfit/benign_api_log_filter.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// 미가입 조회 404 만 Sentry 에서 빠지고, 그 외는 전부 올라가는지 고정한다.
///
/// 이 필터가 넓어지면 실제 장애가 조용해진다. 특히 스탬프 적립이
/// `NOT_FOUND_USER` 로 실패하는 경우는 **반드시 보여야 하는** 신호다 —
/// 서버가 미가입 번호의 적립을 거부한다는 뜻이고, 미가입 접수 기능 자체가
/// 무력하다는 얘기가 되기 때문이다.

class _RecordingLogger implements AppFitLogger {
  final List<String> errors = [];
  final List<String> logs = [];

  @override
  Future<void> log(String message) async => logs.add(message);

  @override
  Future<void> error(String message, dynamic error) async =>
      errors.add(message);
}

ApiHttpException _apiError({
  required int status,
  required String path,
  String? code,
}) =>
    ApiHttpException.fromDio(
      DioException(
        requestOptions: RequestOptions(path: path, method: 'GET'),
        response: Response(
          requestOptions: RequestOptions(path: path, method: 'GET'),
          statusCode: status,
          data: {if (code != null) 'code': code, 'message': 'msg'},
        ),
      ),
    );

void main() {
  late _RecordingLogger sentry;
  late _RecordingLogger plain;
  late BenignApiLogFilter filter;

  setUp(() {
    sentry = _RecordingLogger();
    plain = _RecordingLogger();
    filter = BenignApiLogFilter(sentry: sentry, plain: plain);
  });

  test('미가입 회원조회 404 는 Sentry 로 가지 않는다', () async {
    await filter.error(
      'x',
      _apiError(status: 404, path: '/v0/user/profile', code: 'NOT_FOUND_USER'),
    );
    expect(sentry.errors, isEmpty);
    expect(plain.errors, isEmpty, reason: 'ERROR 레벨로 파일에 남기지 않는다');
    expect(plain.logs, hasLength(1), reason: '기록 자체는 INFO 로 남는다');
  });

  // 회원조회 외의 NOT_FOUND_USER 는 전부 이상 신호다:
  //  - 내역 2종: 미가입이면 애초에 호출하지 않으므로(_enterUnregistered),
  //    여기서 나온다는 건 프로필은 성공했는데 내역은 유저가 없다는 서버 불일치.
  //  - 쓰기 계열: 서버가 미가입 적립/사용을 거부한다는 뜻 = 기능 전제가 깨짐.
  for (final path in const [
    '/v0/stamps/history',
    '/v0/coupons/history',
    '/v0/stamp/earn',
    '/v0/coupon/ABC123/use-without-item',
    '/v0/coupon/ABC123/use-cancel',
  ]) {
    test('회원조회 외의 NOT_FOUND_USER 는 Sentry 로 간다 — $path', () async {
      await filter.error(
        'x',
        _apiError(status: 404, path: path, code: 'NOT_FOUND_USER'),
      );
      expect(sentry.errors, hasLength(1));
      expect(plain.logs, isEmpty);
    });
  }

  test('같은 코드·경로라도 404 가 아니면 Sentry 로 간다', () async {
    await filter.error(
      'x',
      _apiError(status: 500, path: '/v0/user/profile', code: 'NOT_FOUND_USER'),
    );
    expect(sentry.errors, hasLength(1));
  });

  test('같은 경로라도 코드가 다르면 Sentry 로 간다', () async {
    await filter.error(
      'x',
      _apiError(status: 404, path: '/v0/user/profile', code: 'NOT_FOUND_SHOP'),
    );
    expect(sentry.errors, hasLength(1));
  });

  test('서버 코드가 없는 오류는 Sentry 로 간다', () async {
    await filter.error('x', _apiError(status: 500, path: '/v0/user/profile'));
    expect(sentry.errors, hasLength(1));
  });

  test('ApiHttpException 이 아닌 오류는 그대로 Sentry 로 간다', () async {
    await filter.error('x', Exception('boom'));
    expect(sentry.errors, hasLength(1));
  });
}
