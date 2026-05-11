import 'package:appfit_order_agent/models/order_menu_model.dart';
import 'package:flutter_test/flutter_test.dart';

OrderMenuModel _build({
  String shopItemId = 'sku-1',
  int qty = 2,
  String itemName = '아메리카노',
  double itemPrice = 4500,
}) {
  return OrderMenuModel(
    orderNo: 'order-1',
    shopItemId: shopItemId,
    qty: qty,
    itemName: itemName,
    itemPrice: itemPrice,
    totalAmount: itemPrice * qty,
    discPrc: 0,
    vatPrc: 0,
    options: const [],
  );
}

void main() {
  group('OrderMenuModel equality', () {
    test('동일 필드 → ==', () {
      expect(_build(), equals(_build()));
      expect(_build().hashCode, equals(_build().hashCode));
    });

    test('qty 변경 → !=', () {
      expect(_build(qty: 2) == _build(qty: 3), isFalse);
    });

    test('itemPrice 변경 → !=', () {
      expect(_build(itemPrice: 4500) == _build(itemPrice: 5000), isFalse);
    });

    test('shopItemId 변경 → !=', () {
      expect(_build(shopItemId: 'a') == _build(shopItemId: 'b'), isFalse);
    });
  });
}
