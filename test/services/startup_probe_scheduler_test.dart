// fake_async 는 flutter_test 의 전이 의존성(pubspec.lock 에 이미 고정)이며,
// 순수 Timer 로만 구성된 스케줄러라 가상 시계로 결정론적 검증이 가능하다.
// ignore_for_file: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:appfit_order_agent/services/startup_probe_scheduler.dart';

/// [StartupProbeScheduler] — 앱 시작 시 외부 프린터 연결 확인이 실패했을 때의
/// 백오프 재확인 정책을 고정한다.
///
/// 현장 시나리오: 부팅 직후 다른 POS / 배달 프로그램이 COM 포트를 배타 점유해
/// 첫 확인이 실패하고, 몇십 초 뒤 점유가 풀리면 사용자 조작 없이 복구되어야 한다.
void main() {
  const backoffs = [
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(seconds: 30),
  ];

  test('실패가 이어지면 backoff 간격대로 예약하고, 소진 후 재기동하지 않는다', () {
    fakeAsync((async) {
      final probedAt = <Duration>[];
      final scheduled = <String>[];
      var exhaustedTotal = 0;
      var recovered = 0;

      final s = StartupProbeScheduler(
        backoffs: backoffs,
        probe: () async {
          probedAt.add(async.elapsed);
          return false;
        },
        onRetryScheduled: (attempt, total, delay) =>
            scheduled.add('$attempt/$total@${delay.inSeconds}s'),
        onRecovered: (_, __) => recovered++,
        onExhausted: (total) => exhaustedTotal = total,
      );

      s.startAfterInitialFailure();

      // 초기 확인(1회차)은 호출자가 이미 수행한 상태 — 스케줄러는 2회차부터 예약.
      expect(scheduled, ['2/4@5s']);
      expect(probedAt, isEmpty);

      for (final d in backoffs) {
        async.elapse(d);
        async.flushMicrotasks();
      }

      // 재확인은 backoff 길이만큼(3회), 각 간격 경계에서 정확히 1회씩.
      expect(probedAt, [
        const Duration(seconds: 5),
        const Duration(seconds: 20),
        const Duration(seconds: 50),
      ]);
      expect(scheduled, ['2/4@5s', '3/4@15s', '4/4@30s']);
      expect(exhaustedTotal, 4, reason: '초기 1회 + 재시도 3회');
      expect(recovered, 0);
      expect(s.isDone, isTrue);

      // 소진 후에는 어떤 타이머도 남지 않아야 한다 (주기 폴링으로 승격 금지).
      async.elapse(const Duration(minutes: 10));
      expect(probedAt.length, 3);
    });
  });

  test('점유가 풀려 재시도 중 연결되면 즉시 멈추고 복구를 1회 보고한다', () {
    fakeAsync((async) {
      var connected = false;
      var probeCount = 0;
      int? recoveredAttempt;
      var exhausted = 0;

      final s = StartupProbeScheduler(
        backoffs: backoffs,
        probe: () async {
          probeCount++;
          return connected;
        },
        onRecovered: (attempt, _) => recoveredAttempt = attempt,
        onExhausted: (_) => exhausted++,
      )..startAfterInitialFailure();

      async.elapse(const Duration(seconds: 5)); // 2회차 — 아직 점유 중
      async.flushMicrotasks();
      expect(probeCount, 1);
      expect(s.isDone, isFalse);

      connected = true; // 타 프로그램이 포트를 놓음
      async.elapse(const Duration(seconds: 15)); // 3회차 — 복구
      async.flushMicrotasks();

      expect(probeCount, 2);
      expect(recoveredAttempt, 3);
      expect(exhausted, 0);
      expect(s.isDone, isTrue);

      async.elapse(const Duration(minutes: 10));
      expect(probeCount, 2, reason: '복구 후에는 재확인하지 않는다');
    });
  });

  test('shouldContinue 가 false 면 로그 없이 조용히 종료한다', () {
    fakeAsync((async) {
      var probeCount = 0;
      var recovered = 0;
      var exhausted = 0;
      var useExternal = true;

      final s = StartupProbeScheduler(
        backoffs: backoffs,
        probe: () async {
          probeCount++;
          return false;
        },
        shouldContinue: () => useExternal,
        onRecovered: (_, __) => recovered++,
        onExhausted: (_) => exhausted++,
      )..startAfterInitialFailure();

      useExternal = false; // 대기 중 사용자가 외부 프린터 토글 OFF
      async.elapse(const Duration(seconds: 5));
      async.flushMicrotasks();

      expect(probeCount, 0, reason: '토글이 꺼졌으면 포트를 열지 않는다');
      expect(recovered, 0);
      expect(exhausted, 0, reason: '소진이 아니라 조용한 종료');
      expect(s.isDone, isTrue);

      async.elapse(const Duration(minutes: 10));
      expect(probeCount, 0);
    });
  });

  test('stop() 은 예약을 취소하고, 진행 중인 probe 결과도 무시한다', () {
    fakeAsync((async) {
      var probeCount = 0;
      var recovered = 0;

      final s = StartupProbeScheduler(
        backoffs: backoffs,
        probe: () async {
          probeCount++;
          return true;
        },
        onRecovered: (_, __) => recovered++,
      )..startAfterInitialFailure();

      s.stop();
      async.elapse(const Duration(minutes: 10));
      async.flushMicrotasks();

      expect(probeCount, 0);
      expect(recovered, 0);
      expect(s.isDone, isTrue);

      // 재호출은 무해해야 한다 (provider dispose 와 자연 종료가 겹칠 수 있음).
      s.stop();
      expect(s.isDone, isTrue);
    });
  });
}
