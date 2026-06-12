// fake_async 는 flutter_test 의 전이 의존성(pubspec.lock 에 이미 고정)이며,
// 새 직접 의존성 추가 없이 타이머 검증에 사용한다.
// ignore_for_file: depend_on_referenced_packages
import 'dart:async';

import 'package:appfit_order_agent/providers/order/order_timer_manager.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// OrderTimerManager characterization 테스트.
///
/// 폴링(30s 스타트업 지연 + 주기), restartPolling 간격 전환, 캐시 정리(1h),
/// 자정 새로고침 스케줄의 "현재 동작"을 fakeAsync 로 고정한다.
///
/// 주의: setupPollingTimer 는 AppFitConfig.baseUrl 유효성을 검사하는데,
/// AppFitConfig 기본 환경(live)의 baseUrl 이 비어있지 않으므로 테스트에서
/// 별도 설정 없이 폴링 경로가 진행된다 (전역 정적 상태에 의존하는 현재 구조).
///
/// 주의: scheduleMidnightRefresh 는 DateTime.now() 를 직접 사용하므로
/// fakeAsync 로 시간을 흘려도 벽시계는 고정이다. 테스트는 실제 now 기준으로
/// 다음 자정까지의 간격을 역산해 검증한다.
OrderTimerManager _manager({
  VoidCallback? onPollNewOrders,
  VoidCallback? onRefreshOrders,
  VoidCallback? onCacheCleanup,
}) {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  final provider = Provider<OrderTimerManager>(
    (ref) => OrderTimerManager(
      ref,
      onPollNewOrders: onPollNewOrders,
      onRefreshOrders: onRefreshOrders,
      onCacheCleanup: onCacheCleanup,
    ),
  );
  return container.read(provider);
}

void main() {
  group('폴링 간격 상수 (appfit_core 공용 상수 위임)', () {
    test('소켓 연결 시 60s / 단절 시 15s', () {
      expect(OrderTimerManager.socketConnectedIntervalSeconds, 60);
      expect(OrderTimerManager.socketDisconnectedIntervalSeconds, 15);
    });
  });

  group('setupPollingTimer', () {
    test('로그아웃 상태면 폴링 타이머를 만들지 않음', () {
      fakeAsync((async) {
        var refreshCount = 0;
        final m = _manager(onRefreshOrders: () => refreshCount++);
        m.setupPollingTimer(true);
        async.elapse(const Duration(minutes: 10));
        expect(refreshCount, 0);
        m.dispose();
      });
    });

    test('30s 스타트업 지연 후 기본 60s 주기로 onRefreshOrders 호출', () {
      fakeAsync((async) {
        var refreshCount = 0;
        final m = _manager(onRefreshOrders: () => refreshCount++);
        m.setupPollingTimer(false);

        // 스타트업 30s + 첫 주기 60s = 90s 전에는 미호출
        async.elapse(const Duration(seconds: 89));
        expect(refreshCount, 0);
        async.elapse(const Duration(seconds: 2)); // 91s
        expect(refreshCount, 1);
        async.elapse(const Duration(seconds: 60)); // 151s
        expect(refreshCount, 2);
        m.dispose();
      });
    });

    test('현재 동작 고정(버그 의심): onPollNewOrders 콜백은 어떤 타이머에서도 호출되지 않음', () {
      // order_provider 는 onPollNewOrders 를 주입하지만 OrderTimerManager 내부에는
      // 이를 호출하는 코드가 없다 (폴링은 항상 onRefreshOrders 만 호출). dead callback.
      fakeAsync((async) {
        var pollCount = 0;
        var refreshCount = 0;
        final m = _manager(
          onPollNewOrders: () => pollCount++,
          onRefreshOrders: () => refreshCount++,
        );
        m.setupPollingTimer(false);
        m.setupCacheCleanupTimer();
        async.elapse(const Duration(hours: 2));
        expect(refreshCount, greaterThan(0));
        expect(pollCount, 0); // 주입돼도 영원히 미사용
        m.dispose();
      });
    });
  });

  group('restartPolling — 소켓 상태에 따른 간격 전환', () {
    test('스타트업 지연 없이 즉시 지정 간격(15s) 주기 시작', () {
      fakeAsync((async) {
        var refreshCount = 0;
        final m = _manager(onRefreshOrders: () => refreshCount++);
        m.restartPolling(
            OrderTimerManager.socketDisconnectedIntervalSeconds); // 15s

        async.elapse(const Duration(seconds: 14));
        expect(refreshCount, 0);
        async.elapse(const Duration(seconds: 2)); // 16s
        expect(refreshCount, 1);
        async.elapse(const Duration(seconds: 15)); // 31s
        expect(refreshCount, 2);
        m.dispose();
      });
    });

    test('대기 중인 스타트업 타이머를 취소하고 새 주기로 대체 (이중 폴링 없음)', () {
      fakeAsync((async) {
        var refreshCount = 0;
        final m = _manager(onRefreshOrders: () => refreshCount++);
        m.setupPollingTimer(false); // 30s 스타트업 대기 시작
        async.elapse(const Duration(seconds: 10));
        m.restartPolling(15); // 스타트업 취소 + 15s 주기

        async.elapse(const Duration(seconds: 90));
        // 15s 간격만 동작: 90/15 = 6회. (스타트업이 살아있었다면 추가 발화 발생)
        expect(refreshCount, 6);
        m.dispose();
      });
    });

    test('간격 전환(15s→60s): 이전 주기 타이머는 취소되고 새 간격만 적용', () {
      fakeAsync((async) {
        var refreshCount = 0;
        final m = _manager(onRefreshOrders: () => refreshCount++);
        m.restartPolling(15);
        async.elapse(const Duration(seconds: 16)); // 1회
        expect(refreshCount, 1);

        m.restartPolling(60); // 소켓 재연결 시나리오
        async.elapse(const Duration(seconds: 59));
        expect(refreshCount, 1); // 15s 타이머가 살아있다면 이미 +3회 됐을 구간
        async.elapse(const Duration(seconds: 2));
        expect(refreshCount, 2);
        m.dispose();
      });
    });

    test('restartPolling 으로 바꾼 간격은 이후 setupPollingTimer 재호출에도 유지됨', () {
      fakeAsync((async) {
        var refreshCount = 0;
        final m = _manager(onRefreshOrders: () => refreshCount++);
        m.restartPolling(15); // _currentPollingIntervalSeconds = 15 로 변경
        m.setupPollingTimer(false); // 기존 주기 취소, 30s 스타트업 후 "현재 간격" 사용

        // 30s 스타트업 + 15s 주기 = 45s 에 첫 발화
        async.elapse(const Duration(seconds: 44));
        expect(refreshCount, 0);
        async.elapse(const Duration(seconds: 2)); // 46s
        expect(refreshCount, 1);
        m.dispose();
      });
    });
  });

  group('setupCacheCleanupTimer', () {
    test('1시간 주기로 onCacheCleanup 호출', () {
      fakeAsync((async) {
        var cleanupCount = 0;
        final m = _manager(onCacheCleanup: () => cleanupCount++);
        m.setupCacheCleanupTimer();

        async.elapse(const Duration(minutes: 59));
        expect(cleanupCount, 0);
        async.elapse(const Duration(minutes: 2));
        expect(cleanupCount, 1);
        async.elapse(const Duration(hours: 1));
        expect(cleanupCount, 2);
        m.dispose();
      });
    });
  });

  group('scheduleMidnightRefresh', () {
    test('다음 자정(00:00:01) 에 onRefreshOrders 1회 발화 후 재스케줄', () {
      fakeAsync((async) {
        var refreshCount = 0;
        final m = _manager(onRefreshOrders: () => refreshCount++);

        // 매니저와 동일한 방식으로 다음 자정까지의 간격을 역산.
        final now = DateTime.now();
        final nextMidnight =
            DateTime(now.year, now.month, now.day + 1, 0, 0, 1);
        final untilMidnight = nextMidnight.difference(now);

        m.scheduleMidnightRefresh();

        // 자정 2초 전까지는 미발화 (역산/실측 미세 오차 마진 2s)
        async.elapse(untilMidnight - const Duration(seconds: 2));
        expect(refreshCount, 0);

        // 자정 통과 → 1회 발화
        async.elapse(const Duration(seconds: 4));
        expect(refreshCount, 1);

        // 재스케줄 확인: 콜백 내부에서 실제 벽시계 기준으로 다시 ~하루 뒤 타이머를 건다.
        // (fakeAsync 에서 DateTime.now() 는 고정이므로 두 번째 간격도 untilMidnight 근처)
        async.elapse(untilMidnight);
        expect(refreshCount, 2);
        m.dispose();
      });
    });
  });

  group('구독 관리', () {
    test('set → has true, cancel → has false', () async {
      final m = _manager();
      expect(m.hasOrderNotificationSubscription, isFalse);

      final controller = StreamController<int>();
      m.setOrderNotificationSubscription(controller.stream.listen((_) {}));
      expect(m.hasOrderNotificationSubscription, isTrue);

      m.cancelOrderNotificationSubscription();
      expect(m.hasOrderNotificationSubscription, isFalse);
      expect(controller.hasListener, isFalse);
      await controller.close();
    });

    test('새 구독 set 시 이전 구독은 자동 cancel', () async {
      final m = _manager();
      final c1 = StreamController<int>();
      final c2 = StreamController<int>();

      m.setOrderNotificationSubscription(c1.stream.listen((_) {}));
      m.setOrderNotificationSubscription(c2.stream.listen((_) {}));

      expect(c1.hasListener, isFalse); // 이전 구독 cancel 됨
      expect(c2.hasListener, isTrue);

      m.cancelOrderNotificationSubscription();
      await c1.close();
      await c2.close();
    });

    test('isPaused: 구독 없으면 false, pause 후 true, resume 으로 해제', () async {
      final m = _manager();
      expect(m.isOrderNotificationSubscriptionPaused, isFalse);

      final controller = StreamController<int>();
      final sub = controller.stream.listen((_) {});
      m.setOrderNotificationSubscription(sub);
      expect(m.isOrderNotificationSubscriptionPaused, isFalse);

      sub.pause();
      expect(m.isOrderNotificationSubscriptionPaused, isTrue);

      m.resumeOrderNotificationSubscription();
      expect(m.isOrderNotificationSubscriptionPaused, isFalse);

      m.cancelOrderNotificationSubscription();
      await controller.close();
    });

    test('메시지 스트림 구독도 교체 시 이전 구독 cancel', () async {
      final m = _manager();
      final c1 = StreamController<Map<String, dynamic>>();
      final c2 = StreamController<Map<String, dynamic>>();

      m.setMessageStreamSubscription(c1.stream.listen((_) {}));
      m.setMessageStreamSubscription(c2.stream.listen((_) {}));
      expect(c1.hasListener, isFalse);
      expect(c2.hasListener, isTrue);

      m.cancelMessageStreamSubscription();
      expect(c2.hasListener, isFalse);
      await c1.close();
      await c2.close();
    });
  });

  group('dispose / cleanupOnLogout', () {
    test('dispose 후에는 모든 타이머 콜백이 더 이상 발화하지 않음', () {
      fakeAsync((async) {
        var refreshCount = 0;
        var cleanupCount = 0;
        final m = _manager(
          onRefreshOrders: () => refreshCount++,
          onCacheCleanup: () => cleanupCount++,
        );
        m.setupPollingTimer(false);
        m.setupCacheCleanupTimer();
        m.scheduleMidnightRefresh();

        m.dispose();

        async.elapse(const Duration(days: 2));
        expect(refreshCount, 0);
        expect(cleanupCount, 0);
      });
    });

    test('cleanupOnLogout 은 dispose 와 동일하게 타이머/구독을 모두 정리', () {
      fakeAsync((async) {
        var refreshCount = 0;
        final m = _manager(onRefreshOrders: () => refreshCount++);
        m.restartPolling(15);
        m.cleanupOnLogout();

        async.elapse(const Duration(minutes: 10));
        expect(refreshCount, 0);
        expect(m.hasOrderNotificationSubscription, isFalse);
      });
    });
  });
}
