import 'package:flutter_test/flutter_test.dart';

import 'package:appfit_order_agent/models/menu_option_model.dart';
import 'package:appfit_order_agent/models/order_menu_model.dart';
import 'package:appfit_order_agent/models/product_model.dart';
import 'package:appfit_order_agent/services/label_printer/label_subinfo_strategy.dart';

// ── 카탈로그 (categoryCode = 옵션그룹 POS 코드) ─────────────────────────────
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
    displayOrder: 0,
  );
}

final _products = <ProductModel>[
  _product(id: 'W1', categoryCode: 'TKP1006'),
  _product(id: 'C1', categoryCode: 'TKP9999'),
  _product(id: 'BEAN', categoryCode: 'TKP012'), // 원두
  _product(id: 'TEMP', categoryCode: 'TKP001'), // 온도
  _product(id: 'SIZE', categoryCode: 'TKP004'), // 사이즈
];

MenuOptionModel _opt(String id, String name, {String? groupPosId}) =>
    MenuOptionModel(
      shopOptionId: id,
      optionName: name,
      optionPrice: 0,
      qty: 1,
      optionGroupPosId: groupPosId,
    );

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

void main() {
  final waffle = _menu('W1');
  final coffee = _menu('C1', options: [
    _opt('BEAN', '다크'),
    _opt('TEMP', 'ICED'),
    _opt('SIZE', 'Large'),
    _opt('X', '샷추가'), // 카탈로그에 없는 옵션
  ]);

  group('TpcpLabelSubInfoStrategy.classifyOptions', () {
    const s = TpcpLabelSubInfoStrategy();

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
      expect(cats.classified, isEmpty);
    });

    // v1 주문상세는 옵션에 optionGroupPosId 를 실어준다. 서버가 상품 경로로
    // 옵션 카테고리를 더 이상 내려주지 않으므로 이 쪽이 분류의 정본이다.
    test('optionGroupPosId 로 분류 — 상품마스터에 없는 옵션도 분류된다', () {
      final menu = _menu('C1', options: [
        _opt('U1', 'ダーク', groupPosId: 'TKP012'),
        _opt('U2', 'ICE', groupPosId: 'TKP001'),
        _opt('U3', 'L', groupPosId: 'TKP004'),
        _opt('U4', 'ショット追加', groupPosId: 'TKP9999'), // 분류 대상 아닌 그룹
      ]);
      final cats = s.classifyOptions(menu, products: _products);
      expect(cats.beanType, 'ダーク');
      expect(cats.temperature, 'ICE');
      expect(cats.sizeOption, 'L');
      expect(cats.classified.length, 3);
    });

    test('그룹ID 가 있으면 상품마스터 조인보다 우선한다', () {
      // shopOptionId 'SIZE' 는 카탈로그상 사이즈(TKP004)지만,
      // 주문이 실어준 그룹은 원두(TKP012) → 그룹 쪽을 따른다.
      final menu = _menu('C1', options: [
        _opt('SIZE', '다크', groupPosId: 'TKP012'),
      ]);
      final cats = s.classifyOptions(menu, products: _products);
      expect(cats.beanType, '다크');
      expect(cats.sizeOption, isNull);
    });

    test('그룹ID 가 없으면(v0 응답) 기존 상품마스터 조인으로 폴백한다', () {
      final menu = _menu('C1', options: [_opt('SIZE', 'Large')]);
      final cats = s.classifyOptions(menu, products: _products);
      expect(cats.sizeOption, 'Large');
    });

    test('동명 옵션이 있어도 분류된 인스턴스만 classified 에 담긴다', () {
      // 사이즈 'L' 과 이름이 같은 별개 옵션이 섞여도 오제외되지 않아야 한다.
      final sized = _opt('U3', 'L', groupPosId: 'TKP004');
      final sameName = _opt('U9', 'L', groupPosId: 'TKP9999');
      final menu = _menu('C1', options: [sized, sameName]);
      final cats = s.classifyOptions(menu, products: _products);
      expect(cats.sizeOption, 'L');
      expect(cats.classified, contains(sized));
      expect(cats.classified, isNot(contains(sameName)));
    });
  });

  group('NoOpLabelSubInfoStrategy (TPCP 외 모든 브랜드)', () {
    const s = NoOpLabelSubInfoStrategy();

    test('분류 없음 — sub-info 영역이 빈다', () {
      final cats = s.classifyOptions(coffee, products: _products);
      expect(cats.beanType, isNull);
      expect(cats.temperature, isNull);
      expect(cats.sizeOption, isNull);
      expect(cats.classified, isEmpty);
    });
  });
}
