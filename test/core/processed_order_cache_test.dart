import 'package:appfit_order_agent/core/orders/cache/processed_order_cache.dart';
import 'package:appfit_order_agent/models/enums/order_status.dart';
import 'package:flutter_test/flutter_test.dart';

/// I1/I2 불변식의 토대인 dedup 가드의 키 의미론을 검증한다.
///
/// 전체 자동접수 race(소켓↔폴링 인터리빙)는 Order notifier 의 무거운 의존성
/// (API/preference/socket/timer + microtask 부수효과) 때문에 단위 격리가 어렵고,
/// 계획상 실기 시나리오(Verification)로 검증한다. 다만 그 race 를 막는 핵심
/// 자료구조인 ProcessedOrderCache 의 (orderId, status) 키 분리 의미론은
/// 순수하게 검증 가능하며, 이게 깨지면 I1(중복 자동접수)·I2(자가/외부 오인)가 직격된다.
void main() {
  late ProcessedOrderCache cache;

  setUp(() {
    cache = ProcessedOrderCache();
    cache.clear();
  });

  group('ProcessedOrderCache — (orderId, status) 키 분리 [I1/I2 토대]', () {
    test('add 후 contains: 같은 (orderId, status) 는 hit', () {
      cache.addOrderStatus('ORD1', OrderStatus.NEW);
      expect(cache.containsOrderStatus('ORD1', OrderStatus.NEW), isTrue);
    });

    test('미등록 (orderId, status) 는 miss', () {
      expect(cache.containsOrderStatus('ORD1', OrderStatus.NEW), isFalse);
    });

    test('같은 orderId 라도 status 가 다르면 별개 키 (NEW 등록이 PREPARING 을 막지 않음)', () {
      // 자동접수 전 NEW 를 dedup 등록해도, 이후 PREPARING enqueue 는 허용되어야 한다.
      cache.addOrderStatus('ORD1', OrderStatus.NEW);
      expect(cache.containsOrderStatus('ORD1', OrderStatus.NEW), isTrue);
      expect(cache.containsOrderStatus('ORD1', OrderStatus.PREPARING), isFalse);
    });

    test('같은 status 라도 orderId 가 다르면 별개 키 (한 주문 dedup 이 다른 주문을 막지 않음)', () {
      cache.addOrderStatus('ORD1', OrderStatus.PREPARING);
      expect(cache.containsOrderStatus('ORD2', OrderStatus.PREPARING), isFalse);
    });

    test('이중 소스 race 시나리오: NEW 사전등록 후 동일 (orderId,NEW) 후행 enqueue 는 차단', () {
      // 소켓이 자동접수 직전 NEW 를 등록하면, 폴링의 후행 동일 NEW enqueue 가 차단된다.
      expect(cache.containsOrderStatus('ORD1', OrderStatus.NEW), isFalse);
      cache.addOrderStatus('ORD1', OrderStatus.NEW);
      // 폴링 후행 진입:
      expect(cache.containsOrderStatus('ORD1', OrderStatus.NEW), isTrue);
    });

    test('clear 후 모든 키 miss', () {
      cache.addOrderStatus('ORD1', OrderStatus.NEW);
      cache.addOrderStatus('ORD2', OrderStatus.PREPARING);
      cache.clear();
      expect(cache.containsOrderStatus('ORD1', OrderStatus.NEW), isFalse);
      expect(cache.containsOrderStatus('ORD2', OrderStatus.PREPARING), isFalse);
    });
  });
}
