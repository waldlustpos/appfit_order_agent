import 'package:appfit_order_agent/models/order_menu_model.dart';
import 'package:appfit_order_agent/models/order_model.dart';
import 'package:appfit_order_agent/models/order_state.dart';
import 'package:flutter_test/flutter_test.dart';

OrderModel _order({String orderNo = 'order-1'}) {
  return OrderModel(
    orderNo: orderNo,
    shopOrderNo: '0001',
    orderStatus: OrderStatus.PREPARING.name,
    orderedAt: DateTime.utc(2026, 1, 1, 9, 0),
    totalAmount: 9000,
    status: OrderStatus.PREPARING,
    storeId: 'store-1',
    userId: 'user-1',
    ordererName: '홍길동',
    orderCount: '2',
    paymentAmount: 9000,
    discountAmount: 0,
    paymentType: 'CARD',
    paymentCode: 'CARD',
    menus: const <OrderMenuModel>[],
    orderType: 'T',
    kdsOrderType: 1,
    kioskId: 'kiosk-1',
    updateTime: DateTime.utc(2026, 1, 1, 9, 0),
  );
}

void main() {
  group('OrderState equality', () {
    test('동일 필드 → ==', () {
      final a = OrderState(orders: [_order()], isLoading: false);
      final b = OrderState(orders: [_order()], isLoading: false);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('isLoading 변경 → !=', () {
      final a = OrderState(orders: [_order()], isLoading: false);
      final b = OrderState(orders: [_order()], isLoading: true);
      expect(a == b, isFalse);
    });

    test('orders 원소 변경 → !=', () {
      final a = OrderState(orders: [_order(orderNo: 'a')], isLoading: false);
      final b = OrderState(orders: [_order(orderNo: 'b')], isLoading: false);
      expect(a == b, isFalse);
    });

    test('동일 List 참조 → identical short-circuit', () {
      final orders = [_order()];
      final a = OrderState(orders: orders, isLoading: false);
      final b = OrderState(orders: orders, isLoading: false);
      expect(a, equals(b));
    });
  });

  group('OrderState.copyWith 가드', () {
    test('인자 없는 copyWith → this 반환', () {
      final s = OrderState(orders: [_order()], isLoading: false);
      expect(identical(s, s.copyWith()), isTrue);
    });

    test('동일 값 전달 → this 반환', () {
      final orders = [_order()];
      final s = OrderState(orders: orders, isLoading: false);
      expect(
          identical(s, s.copyWith(orders: orders, isLoading: false)), isTrue);
    });

    test('isLoading 변경 → 새 인스턴스', () {
      final s = OrderState(orders: [_order()], isLoading: false);
      expect(identical(s, s.copyWith(isLoading: true)), isFalse);
    });

    test('error: null 명시 전달 시 reset 동작', () {
      const s = OrderState(orders: [], isLoading: false, error: 'oops');
      final reset = s.copyWith(error: null);
      expect(reset.error, isNull);
    });

    test('error 인자 생략 시 기존 error 보존', () {
      const s = OrderState(orders: [], isLoading: false, error: 'oops');
      final kept = s.copyWith(isLoading: true);
      expect(kept.error, equals('oops'));
    });
  });
}
