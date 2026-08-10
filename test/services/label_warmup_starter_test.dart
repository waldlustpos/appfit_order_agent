// fake_async 는 flutter_test 의 전이 의존성(pubspec.lock 에 이미 고정)이며,
// warm-up 재시도가 순수 Timer(StartupProbeScheduler)로만 구성돼 가상 시계로
// 결정론적 검증이 가능하다.
// ignore_for_file: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:appfit_order_agent/services/label_printer/label_warmup_starter.dart';
import 'package:appfit_order_agent/services/startup_probe_scheduler.dart';

/// [startLabelWarmup] — 앱 시작 시 라벨 프린터 USB 포트를 미리 여는 정책을 고정한다.
///
/// 현장 시나리오: 기기 부팅 후 앱 최초 실행에서 세션 첫 `CP_Port_OpenUsb` 가
/// 실패해, 첫 주문의 라벨이 `실패 [연결오류]` 를 내고 1.5초 뒤 재시도에서야
/// 인쇄됐다. warm-up 은 그 open 을 주문 도착 전으로 옮긴다.
void main() {
  /// 테스트 전용 짧은 백오프. 기본값 검증은 별도 테스트에서 상수로 직접 확인한다.
  const backoffs = [
    Duration(seconds: 3),
    Duration(seconds: 8),
    Duration(seconds: 20),
  ];

  /// fakeAsync 안에서 [startLabelWarmup] 을 돌리고 결과를 동기적으로 회수한다.
  StartupProbeScheduler? runStarter(
    FakeAsync async, {
    required bool useLabelPrinter,
    required int Function() autoReplyMode,
    required Future<bool> Function(int mode) warmup,
    required bool Function() shouldContinue,
    void Function(String message)? onInfo,
    void Function(String message)? onWarning,
  }) {
    StartupProbeScheduler? scheduler;
    startLabelWarmup(
      useLabelPrinter: useLabelPrinter,
      autoReplyMode: autoReplyMode,
      warmup: warmup,
      shouldContinue: shouldContinue,
      backoffs: backoffs,
      onInfo: onInfo,
      onWarning: onWarning,
    ).then((s) => scheduler = s);
    async.flushMicrotasks();
    return scheduler;
  }

  test('라벨 프린터를 쓰지 않으면 포트를 열지 않는다', () {
    fakeAsync((async) {
      var warmupCount = 0;
      final infos = <String>[];

      final s = runStarter(
        async,
        useLabelPrinter: false,
        autoReplyMode: () => 1,
        warmup: (_) async {
          warmupCount++;
          return true;
        },
        shouldContinue: () => true,
        onInfo: infos.add,
      );

      expect(warmupCount, 0, reason: '토글 OFF 면 USB 를 건드리지 않는다');
      expect(s, isNull);
      expect(infos, isEmpty);

      async.elapse(const Duration(minutes: 10));
      expect(warmupCount, 0);
    });
  });

  test('초기 warm-up 이 성공하면 재시도를 예약하지 않는다', () {
    fakeAsync((async) {
      var warmupCount = 0;
      final infos = <String>[];

      final s = runStarter(
        async,
        useLabelPrinter: true,
        autoReplyMode: () => 1,
        warmup: (_) async {
          warmupCount++;
          return true;
        },
        shouldContinue: () => true,
        onInfo: infos.add,
      );

      expect(warmupCount, 1);
      expect(s, isNull, reason: '성공 시 스케줄러를 만들지 않는다');
      expect(infos, ['라벨 warm-up 완료']);

      // 성공 후에는 어떤 타이머도 남지 않아야 한다 (주기 폴링으로 승격 금지).
      async.elapse(const Duration(minutes: 10));
      expect(warmupCount, 1);
    });
  });

  test('실패가 이어지면 backoff 간격대로 재시도하고, 소진 후 재기동하지 않는다', () {
    fakeAsync((async) {
      final warmupAt = <Duration>[];
      final infos = <String>[];
      final warnings = <String>[];

      final s = runStarter(
        async,
        useLabelPrinter: true,
        autoReplyMode: () => 1,
        warmup: (_) async {
          warmupAt.add(async.elapsed);
          return false;
        },
        shouldContinue: () => true,
        onInfo: infos.add,
        onWarning: warnings.add,
      );

      expect(s, isNotNull);
      expect(warmupAt, [Duration.zero], reason: '초기 1회는 즉시');
      expect(infos, ['라벨 warm-up 실패 — 재시도 예약 (2/4, 3초 후)']);

      for (final d in backoffs) {
        async.elapse(d);
        async.flushMicrotasks();
      }

      expect(warmupAt, [
        Duration.zero,
        const Duration(seconds: 3),
        const Duration(seconds: 11),
        const Duration(seconds: 31),
      ]);
      expect(warnings, ['라벨 warm-up 최종 실패 (4회) — 첫 인쇄 시 lazy 연결로 폴백']);
      expect(s!.isDone, isTrue);

      async.elapse(const Duration(minutes: 10));
      expect(warmupAt.length, 4, reason: '소진 후 타이머가 남으면 주기 폴링이 된다');
    });
  });

  test('재시도 중 포트가 열리면 즉시 멈추고 복구를 1회 보고한다', () {
    fakeAsync((async) {
      var canOpen = false;
      var warmupCount = 0;
      final infos = <String>[];

      final s = runStarter(
        async,
        useLabelPrinter: true,
        autoReplyMode: () => 1,
        warmup: (_) async {
          warmupCount++;
          return canOpen;
        },
        shouldContinue: () => true,
        onInfo: infos.add,
      );

      async.elapse(const Duration(seconds: 3)); // 2회차 — 아직 실패
      async.flushMicrotasks();
      expect(warmupCount, 2);
      expect(s!.isDone, isFalse);

      canOpen = true; // 커널 enumerate 완료 / 권한 승인
      async.elapse(const Duration(seconds: 8)); // 3회차 — 복구
      async.flushMicrotasks();

      expect(warmupCount, 3);
      expect(infos.last, '라벨 warm-up 성공 (재시도 3/4 에서 복구)');
      expect(s.isDone, isTrue);

      async.elapse(const Duration(minutes: 10));
      expect(warmupCount, 3, reason: '복구 후에는 재확인하지 않는다');
    });
  });

  test('autoReplyMode 는 매 시도마다 다시 읽는다', () {
    fakeAsync((async) {
      // 이 계약이 깨지면 재시도가 옛 모드로 포트를 열고, 첫 인쇄가 모드 불일치로
      // 포트를 닫고 다시 열어 warm-up 이 통째로 무효가 된다.
      final modes = <int>[];
      var currentMode = 1;

      runStarter(
        async,
        useLabelPrinter: true,
        autoReplyMode: () => currentMode,
        warmup: (mode) async {
          modes.add(mode);
          return false;
        },
        shouldContinue: () => true,
      );

      expect(modes, [1]);

      currentMode = 0; // 재시도 대기 중 사용자가 설정 화면에서 모드 변경
      async.elapse(const Duration(seconds: 3));
      async.flushMicrotasks();

      expect(modes, [1, 0], reason: '스냅샷이 아니라 매 시도 재조회여야 한다');
    });
  });

  test('대기 중 라벨 토글이 꺼지면 조용히 종료한다', () {
    fakeAsync((async) {
      var warmupCount = 0;
      var useLabel = true;
      final warnings = <String>[];

      final s = runStarter(
        async,
        useLabelPrinter: true,
        autoReplyMode: () => 1,
        warmup: (_) async {
          warmupCount++;
          return false;
        },
        shouldContinue: () => useLabel,
        onWarning: warnings.add,
      );

      expect(warmupCount, 1);

      useLabel = false; // 사용자가 설정에서 라벨 프린터 OFF
      async.elapse(const Duration(seconds: 3));
      async.flushMicrotasks();

      expect(warmupCount, 1, reason: '토글이 꺼졌으면 포트를 열지 않는다');
      expect(warnings, isEmpty, reason: '소진이 아니라 조용한 종료');
      expect(s!.isDone, isTrue);

      async.elapse(const Duration(minutes: 10));
      expect(warmupCount, 1);
    });
  });

  test('기본 backoff 는 시작 창 한정 · 유한 횟수다', () {
    expect(kDefaultLabelWarmupBackoffs, [
      const Duration(seconds: 3),
      const Duration(seconds: 8),
      const Duration(seconds: 20),
      const Duration(seconds: 60),
    ]);
    final total = kDefaultLabelWarmupBackoffs.fold<Duration>(
        Duration.zero, (a, b) => a + b);
    expect(total.inSeconds, lessThan(120),
        reason: '시작 창을 넘어 계속 도는 폴링이 되면 안 된다');
  });
}
