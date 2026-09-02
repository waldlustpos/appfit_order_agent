import 'package:appfit_order_agent/models/order_menu_model.dart';
import 'package:appfit_order_agent/models/order_model.dart';
import 'package:appfit_order_agent/providers/order/order_history_provider.dart';
import 'package:flutter_test/flutter_test.dart';

// 회귀: 주문내역의 오늘 목록은 OrderProvider 가 유입 시점에 노출 설정으로 걸러
// 넣지만, 과거 날짜는 API 결과를 그대로 그려서 "노출 OFF 인 키오스크 주문이 과거
// 조회에서만 보이는" 날짜별 비대칭이 있었다.

OrderModel _order({
  required String orderNo,
  required String source,
  OrderStatus status = OrderStatus.DONE,
}) {
  final at = DateTime.utc(2026, 1, 1, 10, 0);
  return OrderModel(
    orderNo: orderNo,
    shopOrderNo: '0001',
    orderStatus: status.name,
    orderedAt: at,
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
    updateTime: at,
    source: source,
  );
}

void main() {
  final orders = <OrderModel>[
    _order(orderNo: 'app', source: 'WALD_APPFIT'),
    _order(orderNo: 'kiosk', source: 'NICE_KIOSK'),
    _order(orderNo: 'pos', source: 'WALD_POS'),
  ];

  group('filterOrdersBySourceVisibility', () {
    test('둘 다 ON → 입력 리스트를 그대로(복사 없이) 반환', () {
      final result = filterOrdersBySourceVisibility(orders, true, true);
      expect(identical(result, orders), isTrue);
    });

    test('키오스크 OFF → 키오스크 주문만 제외', () {
      final result = filterOrdersBySourceVisibility(orders, false, true);
      expect(result.map((o) => o.orderId), ['app', 'pos']);
    });

    test('POS OFF → POS 주문만 제외', () {
      final result = filterOrdersBySourceVisibility(orders, true, false);
      expect(result.map((o) => o.orderId), ['app', 'kiosk']);
    });

    test('둘 다 OFF → 앱 주문만 남는다', () {
      final result = filterOrdersBySourceVisibility(orders, false, false);
      expect(result.map((o) => o.orderId), ['app']);
    });

    test('원본 리스트를 변형하지 않는다', () {
      final before = orders.map((o) => o.orderId).toList();
      filterOrdersBySourceVisibility(orders, false, false);
      expect(orders.map((o) => o.orderId).toList(), before);
    });
  });

  group('filterOrdersBySourceVisibility + filterOrders 파이프라인', () {
    // 상태 필터와 축이 다르다 — 취소 필터로 좁혀도 노출 OFF 는 그대로 적용돼야
    // 목록과 상단 취소 건수 칩이 어긋나지 않는다.
    test('취소 필터에서도 노출 OFF 인 출처는 빠진다', () {
      final cancelled = <OrderModel>[
        _order(
            orderNo: 'app-c',
            source: 'WALD_APPFIT',
            status: OrderStatus.CANCELLED),
        _order(
            orderNo: 'kiosk-c',
            source: 'NICE_KIOSK',
            status: OrderStatus.CANCELLED),
      ];

      final result = filterOrders(
        filterOrdersBySourceVisibility(cancelled, false, true),
        OrderFilter.CANCELLED,
      );

      expect(result.map((o) => o.orderId), ['app-c']);
    });
  });
}
