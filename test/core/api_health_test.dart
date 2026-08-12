import 'package:appfit_order_agent/core/net/api_health.dart';
import 'package:appfit_order_agent/core/net/network_outage_summary.dart';
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

  // 전이 시 Sentry 태그 세팅 + 원격 이벤트를 발행하는데, 테스트 환경은
  // Sentry 미init 이라 NoOpHub(configureScope 콜백 미실행) + MonitoringService
  // 의 _initialized 가드로 이중 차단된다. 그 전제가 깨지면(예: 태그 세팅을
  // 게이트 밖으로 옮기면) 여기서 먼저 터진다.
  group('전이 발행이 미init 환경을 오염시키지 않는다', () {
    test('degraded 진입', () {
      expect(() {
        notifier().recordFailure(_dioType(DioExceptionType.connectionError));
        notifier().recordFailure(_dioType(DioExceptionType.connectionError));
      }, returnsNormally);
      expect(read().isDegraded, isTrue);
    });

    test('성공 회복', () {
      notifier().recordFailure(_dioType(DioExceptionType.connectionError));
      notifier().recordFailure(_dioType(DioExceptionType.connectionError));
      expect(() => notifier().recordSuccess(at: DateTime(2026, 8, 8)),
          returnsNormally);
      expect(read().isDegraded, isFalse);
    });

    test('4xx 리셋 회복 — 태그가 degraded 로 sticky 하게 남으면 안 되는 경로', () {
      notifier().recordFailure(_dioType(DioExceptionType.connectionError));
      notifier().recordFailure(_dioType(DioExceptionType.connectionError));
      expect(read().isDegraded, isTrue);

      expect(() => notifier().recordFailure(_dioStatus(404)), returnsNormally);
      expect(read().isDegraded, isFalse, reason: '4xx 는 서버 도달 확인이므로 정식 회복 전이다');
    });
  });

  // 회복 이벤트는 Sentry 로 나가지만 테스트 환경은 미init 이라 이벤트 자체를
  // 볼 수 없다. notifier 가 노출하는 요약값으로 계산을 검증한다.
  group('회복 요약 (원격 관제용)', () {
    final degradedAt = DateTime(2026, 8, 11, 21, 9, 49);
    final recoveredAt = DateTime(2026, 8, 11, 21, 19, 30);

    void degrade(DateTime at) {
      notifier().recordFailure(_dioType(DioExceptionType.connectionError),
          at: at.subtract(const Duration(minutes: 1)));
      notifier()
          .recordFailure(_dioType(DioExceptionType.connectionError), at: at);
    }

    test('진입~회복 지속시간을 초로 담는다', () {
      degrade(degradedAt);
      notifier().recordSuccess(at: recoveredAt);

      expect(notifier().lastOutageSummary?.outageSeconds, 581);
      expect(notifier().lastOutageSummary?.degradedSince, degradedAt);
      expect(notifier().lastOutageSummary?.recoveredAt, recoveredAt);
    });

    // 2026-08-11 PAIK00002: 진입 이벤트에는 fails=2 만 담겼지만 실제로는 11회까지
    // 쌓였다. 진입 시점 값을 그대로 쓰면 원격에서 장애 규모가 5분의 1로 보인다.
    test('피크는 진입 시점(2)이 아니라 구간 최대값이다', () {
      degrade(degradedAt);
      // 21:10:49 ~ 21:18:49 — 실제 장애에서 9회가 더 쌓였다.
      for (var i = 1; i <= 9; i++) {
        notifier().recordFailure(
          _dioType(DioExceptionType.connectionError),
          at: degradedAt.add(Duration(minutes: i)),
        );
      }
      expect(read().consecutiveFailures, 11);

      notifier().recordSuccess(at: recoveredAt);

      expect(notifier().lastOutageSummary?.peakFailures, 11);
    });

    test('성공 회복은 reason=success', () {
      degrade(degradedAt);
      notifier().recordSuccess(at: recoveredAt);

      expect(
          notifier().lastOutageSummary?.reason, NetworkRecoveryReason.success);
      expect(notifier().lastOutageSummary?.lastFailureKind, 'connectionError');
    });

    test('4xx 회복은 reason=serverReachable4xx (데이터는 못 받았다)', () {
      degrade(degradedAt);
      notifier().recordFailure(_dioStatus(404), at: recoveredAt);

      expect(notifier().lastOutageSummary?.reason,
          NetworkRecoveryReason.serverReachable4xx);
      expect(notifier().lastOutageSummary?.outageSeconds, 581);
    });

    test('열화가 없었으면 회복 요약도 없다 (성공만 반복)', () {
      notifier().recordSuccess(at: degradedAt);
      notifier().recordSuccess(at: recoveredAt);

      expect(notifier().lastOutageSummary, isNull);
      expect(notifier().outageReportCount, 0);
    });

    test('1회 실패 후 성공은 전이가 아니므로 요약을 만들지 않는다', () {
      notifier().recordFailure(_dioType(DioExceptionType.connectionError),
          at: degradedAt);
      notifier().recordSuccess(at: recoveredAt);

      expect(notifier().lastOutageSummary, isNull);
    });
  });

  group('회복 이벤트 쿨다운 (5분)', () {
    final t0 = DateTime(2026, 8, 11, 21, 0);

    void cycle({required DateTime degradedAt, required DateTime recoveredAt}) {
      notifier().recordFailure(_dioType(DioExceptionType.connectionError),
          at: degradedAt);
      notifier().recordFailure(_dioType(DioExceptionType.connectionError),
          at: degradedAt);
      notifier().recordSuccess(at: recoveredAt);
    }

    test('5분 안의 두 번째 회복은 전송하지 않는다', () {
      cycle(degradedAt: t0, recoveredAt: t0.add(const Duration(minutes: 1)));
      expect(notifier().outageReportCount, 1);

      cycle(
        degradedAt: t0.add(const Duration(minutes: 2)),
        recoveredAt: t0.add(const Duration(minutes: 3)),
      );

      expect(notifier().outageReportCount, 1, reason: '쿨다운으로 억제');
      expect(notifier().lastOutageSummary?.recoveredAt,
          t0.add(const Duration(minutes: 3)),
          reason: '전송은 막혀도 계산은 갱신된다');
    });

    test('5분이 지나면 다시 전송한다', () {
      cycle(degradedAt: t0, recoveredAt: t0.add(const Duration(minutes: 1)));
      cycle(
        degradedAt: t0.add(const Duration(minutes: 7)),
        recoveredAt: t0.add(const Duration(minutes: 8)),
      );

      expect(notifier().outageReportCount, 2);
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
