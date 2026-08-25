import 'package:appfit_order_agent/models/menu_option_model.dart';
import 'package:appfit_order_agent/models/order_menu_model.dart';
import 'package:flutter_test/flutter_test.dart';

MenuOptionModel _option({
  String shopOptionId = 'opt-1',
  String optionName = '샷 추가',
  double optionPrice = 500,
  int qty = 1,
}) {
  return MenuOptionModel(
    shopOptionId: shopOptionId,
    optionName: optionName,
    optionPrice: optionPrice,
    qty: qty,
  );
}

OrderMenuModel _build({
  String shopItemId = 'sku-1',
  int qty = 2,
  String itemName = '아메리카노',
  double itemPrice = 4500,
  List<MenuOptionModel> options = const [],
  String? itemPosId,
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
    options: options,
    itemPosId: itemPosId,
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

    test('itemPosId 변경 → !=', () {
      expect(_build(itemPosId: 'M009000') == _build(itemPosId: 'M009001'),
          isFalse);
      expect(_build(itemPosId: 'M009000') == _build(itemPosId: null), isFalse);
    });

    test('options 내용만 다르면 != (개수 동일, 깊은 비교)', () {
      final a = _build(options: [_option(shopOptionId: 'opt-a')]);
      final b = _build(options: [_option(shopOptionId: 'opt-b')]);
      expect(a == b, isFalse);
    });

    test('options 동일 내용 → == + hashCode 동일', () {
      final a = _build(options: [_option(), _option(shopOptionId: 'opt-2')]);
      final b = _build(options: [_option(), _option(shopOptionId: 'opt-2')]);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('options 개수 다르면 !=', () {
      final a = _build(options: [_option()]);
      final b = _build(options: [_option(), _option(shopOptionId: 'opt-2')]);
      expect(a == b, isFalse);
    });
  });

  group('MenuOptionModel equality', () {
    test('동일 필드 → == + hashCode 동일', () {
      expect(_option(), equals(_option()));
      expect(_option().hashCode, equals(_option().hashCode));
    });

    test('optionPrice 변경 → !=', () {
      expect(_option(optionPrice: 500) == _option(optionPrice: 700), isFalse);
    });

    test('qty 변경 → !=', () {
      expect(_option(qty: 1) == _option(qty: 2), isFalse);
    });
  });
}
