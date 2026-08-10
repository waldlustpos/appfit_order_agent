import 'package:appfit_order_agent/models/order_menu_model.dart';
import 'package:appfit_order_agent/models/order_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// [OrderModel.withDetailsFrom] 회귀 잠금.
///
/// 배경: `order_provider` 4곳이 `order.copyWith(menus:…, isDetailLoaded: true,
/// kdsOrderType:…)` 로 병합하고 있었다. base 가 목록/소켓 주문이라 **상세 전용
/// 필드는 기본값으로 리셋되는데 `isDetailLoaded` 만 true** 로 남았고, 팝업은
/// `isDetailLoaded == true` 면 재조회를 건너뛴다. 그래서 "팝업 열어 결제수단
/// 확인 → 접수 → 다시 열면 결제수단이 사라짐" 이 재현됐다(기존 discountTypes 도
/// 같은 증상). 병합을 이 메서드 하나로 모았으므로, 상세 전용 필드가 늘어날 때
/// 여기만 고치면 된다.
OrderModel _order({
  required bool isDetailLoaded,
  OrderStatus status = OrderStatus.NEW,
  String orderStatus = 'NEW',
  List<OrderMenuModel> menus = const [],
  List<OrderPaymentModel> payments = const [],
  List<OrderDiscountModel> discounts = const [],
  int kdsOrderType = 0,
}) {
  return OrderModel(
    orderNo: 'ORD-1',
    shopOrderNo: '42',
    orderStatus: orderStatus,
    orderedAt: DateTime(2026, 8, 10, 14, 32),
    totalAmount: 12000,
    status: status,
    storeId: 'TPCP00001',
    userId: 'u-1',
    ordererName: '아메리카노 외 1건',
    orderCount: '2',
    paymentAmount: 10000,
    discountAmount: 2000,
    paymentType: 'MULTI',
    paymentCode: '1',
    menus: menus,
    orderType: 'TAKE_OUT',
    kdsOrderType: kdsOrderType,
    kioskId: '',
    isDetailLoaded: isDetailLoaded,
    payments: payments,
    discounts: discounts,
  );
}

OrderMenuModel _menu() => OrderMenuModel(
      orderNo: 'ORD-1',
      shopItemId: 'sku-1',
      qty: 1,
      itemName: '아메리카노',
      itemPrice: 4500,
      totalAmount: 4500,
      discPrc: 0,
      vatPrc: 409,
      options: const [],
    );

void main() {
  group('OrderModel.withDetailsFrom', () {
    late OrderModel detail;

    setUp(() {
      detail = _order(
        isDetailLoaded: true,
        status: OrderStatus.NEW,
        orderStatus: 'NEW',
        menus: [_menu()],
        kdsOrderType: 2,
        payments: const [
          OrderPaymentModel(
              paymentMethod: 'CREDIT_CARD', amount: 7000, status: 'DONE'),
          OrderPaymentModel(
              paymentMethod: 'CASH', amount: 3000, status: 'DONE'),
        ],
        discounts: const [
          OrderDiscountModel(
              discountType: 'COUPON',
              discountAmount: 2000,
              discountScope: 'ORDER'),
        ],
      );
    });

    test('상세 전용 필드를 전부 이식한다', () {
      final wsOrder = _order(isDetailLoaded: false);
      expect(wsOrder.payments, isEmpty); // 사전 조건

      final merged = wsOrder.withDetailsFrom(detail);

      expect(merged.payments, hasLength(2));
      expect(merged.payments.first.paymentMethod, 'CREDIT_CARD');
      expect(merged.discounts, hasLength(1));
      expect(merged.discountTypes, ['COUPON']); // 파생 getter 도 함께 살아난다
      expect(merged.menus, hasLength(1));
      expect(merged.kdsOrderType, 2);
      expect(merged.isDetailLoaded, isTrue);
    });

    test('상태는 base(소켓/목록)를 유지한다 — 상세 응답이 더 오래됐을 수 있다', () {
      final wsOrder = _order(
        isDetailLoaded: false,
        status: OrderStatus.PREPARING,
        orderStatus: 'ACCEPTED',
      );

      final merged = wsOrder.withDetailsFrom(detail);

      expect(merged.status, OrderStatus.PREPARING);
      expect(merged.orderStatus, 'ACCEPTED');
    });

    test('상태 변경이 반복돼도 상세 전용 필드가 유실되지 않는다 (원 버그 재현 시나리오)', () {
      // 팝업에서 상세 로드 → 접수 → 준비완료 … 상태 이벤트가 연달아 와도
      // 매번 withDetailsFrom 을 타면 결제수단이 계속 살아있어야 한다.
      var current = _order(isDetailLoaded: false).withDetailsFrom(detail);

      for (final s in [
        OrderStatus.PREPARING,
        OrderStatus.READY,
        OrderStatus.DONE
      ]) {
        final incoming = _order(isDetailLoaded: false, status: s);
        current = incoming.withDetailsFrom(current);
      }

      expect(current.status, OrderStatus.DONE);
      expect(current.payments, hasLength(2));
      expect(current.discounts, hasLength(1));
    });
  });

  group('discountTypes 파생 getter', () {
    test('중복 종류는 distinct, 빈 문자열은 제외', () {
      final o = _order(isDetailLoaded: true, discounts: const [
        OrderDiscountModel(
            discountType: 'COUPON',
            discountAmount: 500,
            discountScope: 'ORDER'),
        OrderDiscountModel(
            discountType: 'COUPON', discountAmount: 300, discountScope: 'ITEM'),
        OrderDiscountModel(
            discountType: 'POINT', discountAmount: 200, discountScope: 'ORDER'),
        OrderDiscountModel(
            discountType: '', discountAmount: 0, discountScope: 'ORDER'),
      ]);

      expect(o.discountTypes, ['COUPON', 'POINT']);
    });

    test('discounts 가 비면 빈 목록', () {
      expect(_order(isDetailLoaded: true).discountTypes, isEmpty);
    });
  });
}
