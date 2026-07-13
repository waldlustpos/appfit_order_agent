import 'package:appfit_order_agent/models/menu_option_model.dart';
import 'package:appfit_order_agent/models/order_menu_model.dart';
import 'package:appfit_order_agent/models/order_model.dart';
import 'package:flutter_test/flutter_test.dart';

OrderMenuModel _menu({
  String shopItemId = 'sku-1',
  int qty = 2,
  List<MenuOptionModel> options = const [],
}) {
  return OrderMenuModel(
    orderNo: 'order-1',
    shopItemId: shopItemId,
    qty: qty,
    itemName: '아메리카노',
    itemPrice: 4500,
    totalAmount: 4500.0 * qty,
    discPrc: 0,
    vatPrc: 0,
    options: options,
  );
}

OrderModel _build({
  String orderNo = 'order-1',
  OrderStatus status = OrderStatus.PREPARING,
  double paymentAmount = 9000,
  DateTime? updateTime,
  List<OrderMenuModel>? menus,
  String orderType = 'T',
}) {
  return OrderModel(
    orderNo: orderNo,
    shopOrderNo: '0001',
    orderStatus: status.name,
    orderedAt: DateTime.utc(2026, 1, 1, 9, 0),
    totalAmount: paymentAmount,
    status: status,
    storeId: 'store-1',
    userId: 'user-1',
    ordererName: '홍길동',
    orderCount: '2',
    paymentAmount: paymentAmount,
    discountAmount: 0,
    paymentType: 'CARD',
    paymentCode: 'CARD',
    menus: menus ?? [_menu()],
    orderType: orderType,
    kdsOrderType: 1,
    kioskId: 'kiosk-1',
    updateTime: updateTime ?? DateTime.utc(2026, 1, 1, 9, 0),
  );
}

void main() {
  group('OrderModel equality', () {
    test('동일 필드 → ==', () {
      expect(_build(), equals(_build()));
      expect(_build().hashCode, equals(_build().hashCode));
    });

    test('paymentAmount 변경 → !=', () {
      expect(
          _build(paymentAmount: 9000) == _build(paymentAmount: 10000), isFalse);
    });

    test('status 변경 → !=', () {
      expect(
          _build(status: OrderStatus.PREPARING) ==
              _build(status: OrderStatus.READY),
          isFalse);
    });

    test('menus 원소 변경 → !=', () {
      final a = _build(menus: [_menu(shopItemId: 'a')]);
      final b = _build(menus: [_menu(shopItemId: 'b')]);
      expect(a == b, isFalse);
    });

    test('menus 동일 → == + hashCode 동일', () {
      final a = _build(menus: [_menu(), _menu(shopItemId: 'sku-2')]);
      final b = _build(menus: [_menu(), _menu(shopItemId: 'sku-2')]);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('menus의 옵션 내용만 다르면 != (개수 동일, 깊은 비교)', () {
      final optA = MenuOptionModel(
          shopOptionId: 'opt-a', optionName: '샷 추가', optionPrice: 500, qty: 1);
      final optB = MenuOptionModel(
          shopOptionId: 'opt-b', optionName: '시럽 추가', optionPrice: 300, qty: 1);
      final a = _build(menus: [
        _menu(options: [optA])
      ]);
      final b = _build(menus: [
        _menu(options: [optB])
      ]);
      expect(a == b, isFalse);
    });
  });

  group('OrderModel.copyWith updateTime 가드', () {
    test('copyWith() 단독 호출 시 == 보존 (updateTime 자동 갱신 X)', () {
      final original = _build(updateTime: DateTime.utc(2026, 1, 1, 9, 0));
      final copy = original.copyWith();
      expect(original.updateTime, equals(copy.updateTime));
      expect(original, equals(copy));
      expect(original.hashCode, equals(copy.hashCode));
    });

    test('copyWith(updateTime: ...) 명시 전달 시 갱신됨', () {
      final original = _build(updateTime: DateTime.utc(2026, 1, 1, 9, 0));
      final newTime = DateTime.utc(2026, 1, 1, 10, 0);
      final copy = original.copyWith(updateTime: newTime);
      expect(copy.updateTime, equals(newTime));
      expect(original == copy, isFalse);
    });

    test('copyWith(status: ...) 시 다른 필드 보존', () {
      final original = _build(status: OrderStatus.PREPARING);
      final copy = original.copyWith(status: OrderStatus.READY);
      expect(copy.status, OrderStatus.READY);
      expect(copy.updateTime, equals(original.updateTime));
      expect(copy.paymentAmount, equals(original.paymentAmount));
    });
  });

  group('OrderModel.detectSpecialProductType (목록 orderType 기반)', () {
    // 핵심: 메인 모드 카드는 상세(menus)를 프리페치하지 않으므로, 목록의 orderType 만으로
    // 매장/포장 프리픽스를 판별할 수 있어야 한다(menus 비어있어도).
    test('TAKE_OUT → takeout (menus 없이도)', () {
      expect(
          _build(orderType: 'TAKE_OUT', menus: []).detectSpecialProductType(),
          SpecialProductType.takeout);
    });

    test('IN_SHOP → dineIn (menus 없이도)', () {
      expect(_build(orderType: 'IN_SHOP', menus: []).detectSpecialProductType(),
          SpecialProductType.dineIn);
    });

    test('레거시 T → takeout', () {
      expect(_build(orderType: 'T', menus: []).detectSpecialProductType(),
          SpecialProductType.takeout);
    });

    test('레거시 H → dineIn', () {
      expect(_build(orderType: 'H', menus: []).detectSpecialProductType(),
          SpecialProductType.dineIn);
    });

    test('레거시 C → both', () {
      expect(_build(orderType: 'C', menus: []).detectSpecialProductType(),
          SpecialProductType.both);
    });

    test('orderType 빈 값 + menus 없음 → none', () {
      expect(_build(orderType: '', menus: []).detectSpecialProductType(),
          SpecialProductType.none);
    });

    test('알 수 없는 orderType + menus 없음 → none (폴백)', () {
      expect(_build(orderType: 'XYZ', menus: []).detectSpecialProductType(),
          SpecialProductType.none);
    });
  });
}
