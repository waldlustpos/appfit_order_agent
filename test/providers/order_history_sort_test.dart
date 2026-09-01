import 'package:appfit_order_agent/models/order_menu_model.dart';
import 'package:appfit_order_agent/models/order_model.dart';
import 'package:appfit_order_agent/models/order_state.dart';
import 'package:appfit_order_agent/providers/order/order_history_provider.dart';
import 'package:flutter_test/flutter_test.dart';

OrderModel _order({
  required String orderNo,
  required DateTime orderedAt,
  OrderStatus status = OrderStatus.PREPARING,
}) {
  return OrderModel(
    orderNo: orderNo,
    shopOrderNo: '0001',
    orderStatus: status.name,
    orderedAt: orderedAt,
    totalAmount: 9000,
    status: status,
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
    updateTime: orderedAt,
  );
}

void main() {
  final t9 = DateTime.utc(2026, 1, 1, 9, 0);
  final t10 = DateTime.utc(2026, 1, 1, 10, 0);
  final t11 = DateTime.utc(2026, 1, 1, 11, 0);
  final t12 = DateTime.utc(2026, 1, 1, 12, 0);

  group('sortOrders 는 입력을 변형하지 않는다 (크래시 회귀)', () {
    // 회귀: OrderState.initial().orders 는 const 리스트라 제자리 정렬 시
    // UnsupportedError(Cannot modify an unmodifiable list) 로 앱이 죽었다.
    // UnmodifiableListMixin.sort 는 길이와 무관하게 무조건 throw 하므로 빈 리스트도 대상.
    test('const 빈 리스트 → throw 없이 빈 리스트 반환', () {
      expect(
          sortOrders(const <OrderModel>[], OrderSortDirection.DESC), isEmpty);
      expect(sortOrders(const <OrderModel>[], OrderSortDirection.ASC), isEmpty);
    });

    test('OrderState.initial().orders (const) 로도 통과', () {
      final orders = OrderState.initial().orders;
      final filtered = filterOrders(orders, OrderFilter.ALL);
      expect(sortOrders(filtered, OrderSortDirection.DESC), isEmpty);
    });

    test('List.unmodifiable 입력 → throw 없이 정렬된 새 리스트 반환', () {
      final source = List<OrderModel>.unmodifiable([
        _order(orderNo: 'b', orderedAt: t11),
        _order(orderNo: 'a', orderedAt: t9),
      ]);

      final sorted = sortOrders(source, OrderSortDirection.ASC);

      expect(sorted.map((o) => o.orderId), ['a', 'b']);
      // 원본은 그대로
      expect(source.map((o) => o.orderId), ['b', 'a']);
    });

    test('수정 가능한 입력도 제자리 변형하지 않음 (상태 오염 방지)', () {
      final source = [
        _order(orderNo: 'b', orderedAt: t11),
        _order(orderNo: 'a', orderedAt: t9),
      ];

      final sorted = sortOrders(source, OrderSortDirection.ASC);

      expect(identical(sorted, source), isFalse);
      expect(source.map((o) => o.orderId), ['b', 'a'], reason: '원본 순서 유지');
      expect(sorted.map((o) => o.orderId), ['a', 'b']);
    });
  });

  group('sortOrders 정렬 순서', () {
    final orders = [
      _order(orderNo: 'mid', orderedAt: t10),
      _order(orderNo: 'new', orderedAt: t11),
      _order(orderNo: 'old', orderedAt: t9),
    ];

    test('ASC → 오래된 주문순', () {
      expect(sortOrders(orders, OrderSortDirection.ASC).map((o) => o.orderId),
          ['old', 'mid', 'new']);
    });

    test('DESC → 최신 주문순', () {
      expect(sortOrders(orders, OrderSortDirection.DESC).map((o) => o.orderId),
          ['new', 'mid', 'old']);
    });

    test('Iterable(where 결과)를 .toList() 없이 받는다', () {
      final sorted = sortOrders(
        orders.where((o) => o.orderedAt.isAfter(t9)),
        OrderSortDirection.ASC,
      );
      expect(sorted.map((o) => o.orderId), ['mid', 'new']);
    });
  });

  group('filterOrders + sortOrders 파이프라인', () {
    final orders = <OrderModel>[
      _order(orderNo: 'done', orderedAt: t9, status: OrderStatus.DONE),
      _order(orderNo: 'ready', orderedAt: t11, status: OrderStatus.READY),
      _order(
          orderNo: 'cancelled', orderedAt: t10, status: OrderStatus.CANCELLED),
      _order(orderNo: 'preparing', orderedAt: t10),
      _order(
          orderNo: 'notpicked',
          orderedAt: t12,
          status: OrderStatus.NOT_PICKED_UP),
    ];

    test('ALL → 전체를 최신순으로', () {
      final result = sortOrders(
          filterOrders(orders, OrderFilter.ALL), OrderSortDirection.DESC);
      expect(result.length, 5);
      expect(result.first.orderId, 'notpicked');
    });

    test('COMPLETED → DONE/READY/미픽업', () {
      final result = sortOrders(
          filterOrders(orders, OrderFilter.COMPLETED), OrderSortDirection.ASC);
      expect(result.map((o) => o.orderId), ['done', 'ready', 'notpicked']);
    });

    test('CANCELLED → 취소 주문만 (미픽업은 섞이지 않는다)', () {
      // 미픽업이 취소 필터에 들어가면 취소 건수 칩 집계가 오염된다.
      final result = sortOrders(
          filterOrders(orders, OrderFilter.CANCELLED), OrderSortDirection.ASC);
      expect(result.map((o) => o.orderId), ['cancelled']);
    });

    test('ALL 파이프라인이 원본 리스트 순서를 건드리지 않음', () {
      final before = orders.map((o) => o.orderId).toList();
      sortOrders(
          filterOrders(orders, OrderFilter.ALL), OrderSortDirection.DESC);
      expect(orders.map((o) => o.orderId).toList(), before);
    });
  });
}
