// fake_async 는 flutter_test 의 전이 의존성(pubspec.lock 에 이미 고정)이며,
// 새 직접 의존성 추가 없이 타이머 검증에 사용한다.
// ignore_for_file: depend_on_referenced_packages
import 'dart:io' show SocketException;

import 'package:appfit_order_agent/core/net/transient_error.dart';
import 'package:appfit_order_agent/dev/net_fault_injector.dart';
import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // static 상태이므로 테스트 간 누수를 막는다. 만료 Timer 를 cancel 하지 않으면
  // fakeAsync 가 "A Timer is still pending" 으로 드러내 준다.
  tearDown(NetFaultInjector.clear);

  NetFault? take(NetFaultTarget t) =>
      NetFaultInjector.take(t, '/v1/orders/test');

  group('대상 필터링', () {
    test('무장하지 않으면 아무것도 돌려주지 않는다', () {
      expect(take(NetFaultTarget.orders), isNull);
    });

    test('무장한 대상만 걸린다', () {
      NetFaultInjector.arm(const NetFaultConfig(
        targets: {NetFaultTarget.orderUpdate},
        kind: NetFaultKind.receiveTimeout,
      ));

      expect(take(NetFaultTarget.orders), isNull);
      expect(take(NetFaultTarget.orderDetail), isNull);
      expect(take(NetFaultTarget.orderUpdate), isNotNull);
    });

    test('여러 대상을 한 번에 무장할 수 있다 (매장 장애 프리셋)', () {
      NetFaultInjector.arm(const NetFaultConfig(
        targets: {
          NetFaultTarget.orders,
          NetFaultTarget.orderDetail,
          NetFaultTarget.orderUpdate,
        },
        kind: NetFaultKind.dnsFailure,
      ));

      expect(take(NetFaultTarget.orders), isNotNull);
      expect(take(NetFaultTarget.orderDetail), isNotNull);
      expect(take(NetFaultTarget.orderUpdate), isNotNull);
    });
  });

  group('카운터', () {
    test('지정 횟수만큼만 주입하고 자동 해제된다', () {
      NetFaultInjector.arm(const NetFaultConfig(
        targets: {NetFaultTarget.orders},
        kind: NetFaultKind.dnsFailure,
        remaining: 2,
      ));

      expect(take(NetFaultTarget.orders), isNotNull);
      expect(take(NetFaultTarget.orders), isNotNull);
      expect(take(NetFaultTarget.orders), isNull, reason: '2회 소진 후 비활성');
      expect(NetFaultInjector.config.isActive, isFalse);
    });

    test('remaining=null 은 무제한', () {
      NetFaultInjector.arm(const NetFaultConfig(
        targets: {NetFaultTarget.orders},
        kind: NetFaultKind.dnsFailure,
      ));

      for (var i = 0; i < 50; i++) {
        expect(take(NetFaultTarget.orders), isNotNull);
      }
      expect(NetFaultInjector.config.isActive, isTrue);
    });

    test('slowOnly 도 카운터를 소모한다', () {
      NetFaultInjector.arm(const NetFaultConfig(
        targets: {NetFaultTarget.orders},
        kind: NetFaultKind.slowOnly,
        remaining: 1,
      ));

      final f = take(NetFaultTarget.orders);
      expect(f, isNotNull);
      expect(f!.error, isNull, reason: 'slowOnly 는 지연만 걸고 요청을 통과시킨다');
      expect(take(NetFaultTarget.orders), isNull);
    });

    test('대상이 아닌 호출은 카운터를 소모하지 않는다', () {
      NetFaultInjector.arm(const NetFaultConfig(
        targets: {NetFaultTarget.orders},
        kind: NetFaultKind.dnsFailure,
        remaining: 1,
      ));

      take(NetFaultTarget.orderUpdate);
      expect(take(NetFaultTarget.orders), isNotNull, reason: '아직 안 소모됐어야 한다');
    });
  });

  group('지연', () {
    test('설정한 지연을 그대로 돌려준다 (실제 대기는 호출부 책임)', () {
      NetFaultInjector.arm(const NetFaultConfig(
        targets: {NetFaultTarget.orders},
        kind: NetFaultKind.slowOnly,
        delay: Duration(seconds: 25),
      ));

      expect(take(NetFaultTarget.orders)!.delay, const Duration(seconds: 25));
    });
  });

  group('kind → DioException 매핑', () {
    DioException errorOf(NetFaultKind kind) {
      NetFaultInjector.arm(NetFaultConfig(
        targets: const {NetFaultTarget.orders},
        kind: kind,
      ));
      final e =
          NetFaultInjector.take(NetFaultTarget.orders, '/v1/orders')!.error;
      NetFaultInjector.clear();
      return e!;
    }

    test('dnsFailure 는 connectionError + SocketException(errno 7)', () {
      final e = errorOf(NetFaultKind.dnsFailure);
      expect(e.type, DioExceptionType.connectionError);
      // [API진단] 의 cause= 가 실제 장애 로그와 같은 문자열로 찍혀야 한다.
      expect(e.error, isA<SocketException>());
      expect((e.error as SocketException).osError?.errorCode, 7);
    });

    test('타임아웃 3종', () {
      expect(errorOf(NetFaultKind.connectTimeout).type,
          DioExceptionType.connectionTimeout);
      expect(errorOf(NetFaultKind.receiveTimeout).type,
          DioExceptionType.receiveTimeout);
      expect(
          errorOf(NetFaultKind.sendTimeout).type, DioExceptionType.sendTimeout);
    });

    test('serverError=503, notFound=404', () {
      expect(errorOf(NetFaultKind.serverError).response?.statusCode, 503);
      expect(errorOf(NetFaultKind.notFound).response?.statusCode, 404);
    });

    test('requestOptions.path 는 호출부가 넘긴 실제 라우트를 쓴다', () {
      NetFaultInjector.arm(const NetFaultConfig(
        targets: {NetFaultTarget.orderUpdate},
        kind: NetFaultKind.serverError,
      ));
      final e =
          NetFaultInjector.take(NetFaultTarget.orderUpdate, '/v0/order/12345')!
              .error!;
      expect(e.requestOptions.path, '/v0/order/12345');
    });
  });

  // injector 와 ApiHealth 의 계약을 여기서 못 박는다. 이 표가 깨지면
  // 프리셋이 의도한 것과 다른 건강도 반응을 일으킨다.
  group('isTransientNetworkError 계약', () {
    DioException errorOf(NetFaultKind kind) {
      NetFaultInjector.arm(NetFaultConfig(
        targets: const {NetFaultTarget.orders},
        kind: kind,
      ));
      final e =
          NetFaultInjector.take(NetFaultTarget.orders, '/v1/orders')!.error!;
      NetFaultInjector.clear();
      return e;
    }

    test('실패 종류 대부분은 transient → 건강도 카운트 대상', () {
      for (final kind in [
        NetFaultKind.dnsFailure,
        NetFaultKind.connectTimeout,
        NetFaultKind.receiveTimeout,
        NetFaultKind.sendTimeout,
        NetFaultKind.serverError,
      ]) {
        expect(isTransientNetworkError(errorOf(kind)), isTrue,
            reason: '${kind.name} 은 transient 여야 한다');
      }
    });

    test('notFound(4xx) 만 transient 가 아니다 → 건강도 카운터 리셋', () {
      expect(isTransientNetworkError(errorOf(NetFaultKind.notFound)), isFalse);
    });
  });

  group('자동 만료', () {
    test('maxArmDuration 이 지나면 스스로 해제된다', () {
      fakeAsync((async) {
        NetFaultInjector.arm(const NetFaultConfig(
          targets: {NetFaultTarget.orders},
          kind: NetFaultKind.dnsFailure,
        ));
        expect(NetFaultInjector.config.isActive, isTrue);

        async.elapse(
            NetFaultInjector.maxArmDuration - const Duration(seconds: 1));
        expect(NetFaultInjector.config.isActive, isTrue);

        async.elapse(const Duration(seconds: 2));
        expect(NetFaultInjector.config.isActive, isFalse,
            reason: '무제한 무장인 채로 매장에 나가는 것을 막는 마지막 방어선');
      });
    });

    test('재무장하면 만료 타이머가 다시 시작된다', () {
      fakeAsync((async) {
        NetFaultInjector.arm(const NetFaultConfig(
          targets: {NetFaultTarget.orders},
          kind: NetFaultKind.dnsFailure,
        ));
        async.elapse(const Duration(minutes: 9));

        NetFaultInjector.arm(const NetFaultConfig(
          targets: {NetFaultTarget.orders},
          kind: NetFaultKind.serverError,
        ));
        async.elapse(const Duration(minutes: 9));
        expect(NetFaultInjector.config.isActive, isTrue);

        async.elapse(const Duration(minutes: 2));
        expect(NetFaultInjector.config.isActive, isFalse);
      });
    });

    test('clear() 는 만료 타이머를 취소한다 (pending timer 누수 방지)', () {
      fakeAsync((async) {
        NetFaultInjector.arm(const NetFaultConfig(
          targets: {NetFaultTarget.orders},
          kind: NetFaultKind.dnsFailure,
        ));
        NetFaultInjector.clear();
        // 여기서 취소가 안 되면 fakeAsync 종료 시 pending timer 로 실패한다.
        async.flushTimers();
        expect(NetFaultInjector.config.isActive, isFalse);
      });
    });
  });

  group('상태 통지', () {
    test('무장/소모/해제가 ValueNotifier 로 통지된다 (리본 실시간 갱신)', () {
      var notifications = 0;
      void listener() => notifications++;
      NetFaultInjector.state.addListener(listener);
      addTearDown(() => NetFaultInjector.state.removeListener(listener));

      NetFaultInjector.arm(const NetFaultConfig(
        targets: {NetFaultTarget.orders},
        kind: NetFaultKind.dnsFailure,
        remaining: 2,
      ));
      expect(notifications, 1);

      take(NetFaultTarget.orders);
      expect(notifications, 2, reason: '잔여 카운트가 줄면 UI 가 알아야 한다');

      NetFaultInjector.clear();
      expect(notifications, 3);
    });
  });
}
