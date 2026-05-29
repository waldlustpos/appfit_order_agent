import 'package:appfit_order_agent/models/menu_option_model.dart';
import 'package:appfit_order_agent/models/order_menu_model.dart';
import 'package:appfit_order_agent/models/order_model.dart';
import 'package:appfit_order_agent/models/product_model.dart';
import 'package:appfit_order_agent/services/label_printer/label_filter_strategy.dart';
import 'package:flutter_test/flutter_test.dart';

// ── 카탈로그 (categoryCode 로 분류) ──────────────────────────────────────────
ProductModel _product({
  required String id,
  required String categoryCode,
}) {
  return ProductModel(
    productId: id,
    productName: id,
    categoryName: categoryCode,
    categoryCode: categoryCode,
    menuPrice: 1000,
    status: ProductStatus.sale,
    type: ProductType.item,
    internalId: 'internal-$id',
  );
}

final _products = <ProductModel>[
  _product(id: 'W1', categoryCode: 'TKP1006'), // 와플
  _product(id: 'C1', categoryCode: 'TKP9999'), // 비와플
  _product(id: 'TKP0051', categoryCode: 'TKP9999'), // 세트(항상 출력)
  _product(id: 'BEAN', categoryCode: 'TKP012'), // 원두
  _product(id: 'TEMP', categoryCode: 'TKP001'), // 온도
  _product(id: 'SIZE', categoryCode: 'TKP004'), // 사이즈
];

MenuOptionModel _opt(String id, String name) =>
    MenuOptionModel(shopOptionId: id, optionName: name, optionPrice: 0, qty: 1);

OrderMenuModel _menu(String shopItemId,
    {List<MenuOptionModel> options = const []}) {
  return OrderMenuModel(
    orderNo: 'o1',
    shopItemId: shopItemId,
    qty: 1,
    itemName: shopItemId,
    itemPrice: 1000,
    totalAmount: 1000,
    discPrc: 0,
    vatPrc: 0,
    options: options,
  );
}

OrderModel _order(List<OrderMenuModel> menus) {
  return OrderModel(
    orderNo: 'o1',
    shopOrderNo: '0001',
    orderStatus: OrderStatus.PREPARING.name,
    orderedAt: DateTime.utc(2026, 1, 1),
    totalAmount: 1000,
    status: OrderStatus.PREPARING,
    storeId: 'store-1',
    userId: 'u1',
    ordererName: 'tester',
    orderCount: '1',
    paymentAmount: 1000,
    discountAmount: 0,
    paymentType: 'CARD',
    paymentCode: 'CARD',
    menus: menus,
    orderType: 'T',
    kdsOrderType: 1,
    kioskId: 'k1',
    updateTime: DateTime.utc(2026, 1, 1),
  );
}

void main() {
  final waffle = _menu('W1');
  final coffee = _menu('C1', options: [
    _opt('BEAN', '다크'),
    _opt('TEMP', 'ICED'),
    _opt('SIZE', 'Large'),
    _opt('X', '샷추가'), // 카탈로그에 없는 옵션
  ]);
  final set = _menu('TKP0051');

  group('TpcpLabelFilterStrategy.selectMenus', () {
    const s = TpcpLabelFilterStrategy();

    List<String> ids(List<OrderMenuModel> m) =>
        m.map((e) => e.shopItemId).toList();

    test('filterMode 0(전체) → 모든 메뉴', () {
      final r = s.selectMenus(_order([waffle, coffee, set]),
          products: _products, filterMode: 0, isReprint: false);
      expect(ids(r), ['W1', 'C1', 'TKP0051']);
    });

    test('재출력 → filterMode 무관 전체', () {
      final r = s.selectMenus(_order([waffle, coffee, set]),
          products: _products, filterMode: 1, isReprint: true);
      expect(ids(r), ['W1', 'C1', 'TKP0051']);
    });

    test('filterMode 1(와플만) → 와플 + 세트(항상)', () {
      final r = s.selectMenus(_order([waffle, coffee, set]),
          products: _products, filterMode: 1, isReprint: false);
      expect(ids(r), ['W1', 'TKP0051']);
    });

    test('filterMode 2(와플제외) → 비와플 + 세트(항상)', () {
      final r = s.selectMenus(_order([waffle, coffee, set]),
          products: _products, filterMode: 2, isReprint: false);
      expect(ids(r), ['C1', 'TKP0051']);
    });
  });

  group('TpcpLabelFilterStrategy.classifyOptions', () {
    const s = TpcpLabelFilterStrategy();

    test('원두/온도/사이즈 분류, 미등록 옵션은 무시', () {
      final cats = s.classifyOptions(coffee, products: _products);
      expect(cats.beanType, '다크');
      expect(cats.temperature, 'ICED');
      expect(cats.sizeOption, 'Large');
    });

    test('분류 대상 없으면 모두 null', () {
      final cats = s.classifyOptions(waffle, products: _products);
      expect(cats.beanType, isNull);
      expect(cats.temperature, isNull);
      expect(cats.sizeOption, isNull);
    });
  });

  group('NoOpLabelFilterStrategy (TPCP 외 모든 브랜드)', () {
    const s = NoOpLabelFilterStrategy();

    test('selectMenus 는 filterMode 무관 전체', () {
      final r = s.selectMenus(_order([waffle, coffee, set]),
          products: _products, filterMode: 1, isReprint: false);
      expect(r.length, 3);
    });

    test('classifyOptions 는 분류 없음', () {
      final cats = s.classifyOptions(coffee, products: _products);
      expect(cats.beanType, isNull);
      expect(cats.temperature, isNull);
      expect(cats.sizeOption, isNull);
    });
  });
}
