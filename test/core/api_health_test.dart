import 'package:appfit_order_agent/core/net/api_health.dart';
import 'package:appfit_order_agent/providers/api_health_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

DioException _dioType(DioExceptionType type) => DioException(
      requestOptions: RequestOptions(path: '/v1/orders'),
      type: type,
    );

DioException _dioStatus(int code) => DioException(
      requestOptions: RequestOptions(path: '/v1/orders'),
      type: DioExceptionType.badResponse,
      response: Response(
        requestOptions: RequestOptions(path: '/v1/orders'),
        statusCode: code,
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
  });

  tearDown(() {
    container.dispose();
  });

  ApiHealth read() => container.read(apiHealthNotifierProvider);
  ApiHealthNotifier notifier() =>
      container.read(apiHealthNotifierProvider.notifier);

  group('ApiHealth 초기 상태', () {
    test('실패 0, 성공 이력 없음, 정상', () {
      expect(read().consecutiveFailures, 0);
      expect(read().lastSuccessAt, isNull);
      expect(read().isDegraded, isFalse);
    });
  });

  group('transient 실패 누적', () {
    test('연속 2회 실패에서 degraded 로 전환된다', () {
      notifier().recordFailure(_dioType(DioExceptionType.connectionError));
      expect(read().isDegraded, isFalse, reason: '1회는 단발 blip 일 수 있다');

      notifier().recordFailure(_dioType(DioExceptionType.receiveTimeout));
      expect(read().isDegraded, isTrue);
      expect(read().consecutiveFailures, 2);
    });

    test('마지막 실패 종류를 기록한다 (진단·문구 분기용)', () {
      notifier().recordFailure(_dioType(DioExceptionType.connectionTimeout));
      expect(read().lastFailureKind, 'connectionTimeout');

      notifier().recordFailure(_dioStatus(503));
      expect(read().lastFailureKind, 'badResponse');
    });

    test('5xx 는 transient 로 센다', () {
      notifier().recordFailure(_dioStatus(500));
      notifier().recordFailure(_dioStatus(502));
      expect(read().isDegraded, isTrue);
    });
  });

  group('성공 기록', () {
    test('성공하면 카운터가 리셋되고 마지막 성공 시각이 남는다', () {
      notifier().recordFailure(_dioType(DioExceptionType.connectionError));
      notifier().recordFailure(_dioType(DioExceptionType.connectionError));
      expect(read().isDegraded, isTrue);

      final at = DateTime(2026, 8, 7, 15, 6);
      notifier().recordSuccess(at: at);

      expect(read().consecutiveFailures, 0);
      expect(read().isDegraded, isFalse);
      expect(read().lastSuccessAt, at);
      expect(read().lastFailureKind, isNull);
    });
  });

  group('열화로 세면 안 되는 실패', () {
    test('4xx 는 서버가 응답한 것이므로 카운터를 리셋한다', () {
      notifier().recordFailure(_dioType(DioExceptionType.connectionError));
      expect(read().consecutiveFailures, 1);

      notifier().recordFailure(_dioStatus(400));

      expect(read().consecutiveFailures, 0);
      expect(read().isDegraded, isFalse);
    });

    test('401/404 도 마찬가지로 열화가 아니다', () {
      notifier().recordFailure(_dioStatus(401));
      notifier().recordFailure(_dioStatus(404));
      expect(read().isDegraded, isFalse);
      expect(read().consecutiveFailures, 0);
    });

    test('4xx 리셋은 lastSuccessAt 을 갱신하지 않는다 (데이터는 못 받았다)', () {
      final at = DateTime(2026, 8, 7, 15, 0);
      notifier().recordSuccess(at: at);
      notifier().recordFailure(_dioStatus(404));
      expect(read().lastSuccessAt, at);
    });

    test('취소는 네트워크 상태를 말해주지 않으므로 상태를 바꾸지 않는다', () {
      notifier().recordFailure(_dioType(DioExceptionType.connectionError));
      final before = read();

      notifier().recordFailure(_dioType(DioExceptionType.cancel));

      expect(read(), before);
    });

    test('Dio 가 아닌 예외(파싱 오류 등)는 열화로 세지 않는다', () {
      notifier().recordFailure(_dioType(DioExceptionType.connectionError));
      notifier().recordFailure(FormatException('bad json'));
      expect(read().isDegraded, isFalse);
      expect(read().consecutiveFailures, 0);
    });
  });

  group('동등성', () {
    test('같은 값이면 == (불필요한 리빌드 방지의 전제)', () {
      final at = DateTime(2026, 8, 7);
      expect(
        const ApiHealth(consecutiveFailures: 2, lastFailureKind: 'x'),
        const ApiHealth(consecutiveFailures: 2, lastFailureKind: 'x'),
      );
      expect(
        ApiHealth(consecutiveFailures: 0, lastSuccessAt: at),
        ApiHealth(consecutiveFailures: 0, lastSuccessAt: at),
      );
      expect(
        const ApiHealth(consecutiveFailures: 1),
        isNot(const ApiHealth(consecutiveFailures: 2)),
      );
    });
  });
}
