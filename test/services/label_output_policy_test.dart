import 'package:flutter_test/flutter_test.dart';

import 'package:appfit_order_agent/models/menu_option_model.dart';
import 'package:appfit_order_agent/models/order_menu_model.dart';
import 'package:appfit_order_agent/models/order_model.dart';
import 'package:appfit_order_agent/models/product_model.dart';
import 'package:appfit_order_agent/services/label_printer/label_output_policy.dart';
import 'package:appfit_order_agent/services/label_printer/label_print_data.dart';
import 'package:appfit_order_agent/utils/label_painter.dart';

// ── 카탈로그 픽스처 ─────────────────────────────────────────────────────────
ProductModel _product({
  required String id,
  required String categoryCode,
  String? categoryName,
  ProductType type = ProductType.item,
  String? name,
}) {
  return ProductModel(
    productId: id,
    productName: name ?? id,
    categoryName: categoryName ?? categoryCode,
    categoryCode: categoryCode,
    menuPrice: 1000,
    status: ProductStatus.sale,
    type: type,
    internalId: 'internal-$id',
    displayOrder: 0,
  );
}

final _products = <ProductModel>[
  _product(id: 'W1', categoryCode: 'CAT_DESSERT', categoryName: '디저트'),
  _product(id: 'C1', categoryCode: 'CAT_COFFEE', categoryName: '커피'),
  // 코드가 빈 카테고리 — 이름 폴백 키로만 지목할 수 있다.
  _product(id: 'N1', categoryCode: '', categoryName: '코드없음'),
  // 옵션 상품(카탈로그 조인 폴백용). categoryCode = 옵션그룹 POS 코드.
  _product(id: 'TEMP1', categoryCode: 'G_TEMP', type: ProductType.option),
];

MenuOptionModel _opt(String id, String name, {String? groupPosId}) =>
    MenuOptionModel(
      shopOptionId: id,
      optionName: name,
      optionPrice: 0,
      qty: 1,
      optionGroupPosId: groupPosId,
    );

OrderMenuModel _menu(
  String shopItemId, {
  int qty = 1,
  List<MenuOptionModel> options = const [],
}) {
  return OrderMenuModel(
    orderNo: 'o1',
    shopItemId: shopItemId,
    qty: qty,
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

LabelProductIndex get _index => LabelProductIndex.build(_products);

void main() {
  const coffeeKey = 'c:CAT_COFFEE';

  group('카테고리 키 — 코드 우선, 빈 코드는 이름 폴백', () {
    test('코드가 있으면 코드 키', () {
      expect(labelCategoryKeyOf('CAT_COFFEE', '커피'), 'c:CAT_COFFEE');
    });

    test('코드가 비면 이름 키 (선택 화면과 판정이 같은 함수를 써야 어긋나지 않는다)', () {
      expect(labelCategoryKeyOf('', '코드없음'), 'n:코드없음');
    });
  });

  group('카테고리 필터 — shouldPrintMenu', () {
    test('OFF 면 전부 인쇄', () {
      const policy = LabelOutputPolicy(
        categoryFilterEnabled: false,
        categoryKeys: {coffeeKey},
      );
      expect(policy.shouldPrintMenu(_menu('W1'), _index), isTrue);
    });

    test('ON + 선택 0개는 전부 인쇄 (전체 해제 == 전체 선택)', () {
      const policy = LabelOutputPolicy(categoryFilterEnabled: true);
      expect(policy.isCategoryFilterActive, isFalse);
      expect(policy.shouldPrintMenu(_menu('W1'), _index), isTrue);
    });

    test('선택된 카테고리만 인쇄', () {
      const policy = LabelOutputPolicy(
        categoryFilterEnabled: true,
        categoryKeys: {coffeeKey},
      );
      expect(policy.shouldPrintMenu(_menu('C1'), _index), isTrue);
      expect(policy.shouldPrintMenu(_menu('W1'), _index), isFalse);
    });

    test('shopItemId 가 internalId 로 와도 매칭된다', () {
      const policy = LabelOutputPolicy(
        categoryFilterEnabled: true,
        categoryKeys: {coffeeKey},
      );
      expect(policy.shouldPrintMenu(_menu('internal-C1'), _index), isTrue);
      expect(policy.shouldPrintMenu(_menu('internal-W1'), _index), isFalse);
    });

    test('빈 categoryCode 카테고리는 이름 폴백 키로 지목된다', () {
      const policy = LabelOutputPolicy(
        categoryFilterEnabled: true,
        categoryKeys: {'n:코드없음'},
      );
      expect(policy.shouldPrintMenu(_menu('N1'), _index), isTrue);
      expect(policy.shouldPrintMenu(_menu('C1'), _index), isFalse);
    });

    test('fail-open — 카탈로그가 비면 전부 인쇄 (조회 실패에 라벨이 통째로 사라지면 안 된다)', () {
      const policy = LabelOutputPolicy(
        categoryFilterEnabled: true,
        categoryKeys: {coffeeKey},
      );
      expect(
        policy.shouldPrintMenu(_menu('C1'), LabelProductIndex.build(const [])),
        isTrue,
      );
    });

    test('fail-open — 카탈로그에 없는 상품은 인쇄', () {
      const policy = LabelOutputPolicy(
        categoryFilterEnabled: true,
        categoryKeys: {coffeeKey},
      );
      expect(policy.shouldPrintMenu(_menu('UNKNOWN'), _index), isTrue);
    });

    test('다중 카테고리 상품은 any-match — 사본 하나만 선택돼도 인쇄', () {
      // 같은 상품이 커피/디저트 두 카테고리에 등록된 상황(카탈로그 사본 2개).
      final dup = LabelProductIndex.build([
        _product(id: 'DUP', categoryCode: 'CAT_DESSERT', categoryName: '디저트'),
        _product(id: 'DUP', categoryCode: 'CAT_COFFEE', categoryName: '커피'),
      ]);
      const policy = LabelOutputPolicy(
        categoryFilterEnabled: true,
        categoryKeys: {coffeeKey},
      );
      // 첫 매치(디저트)만 봤다면 false 가 됐을 것 — 배열 순서에 좌우되면 안 된다.
      expect(policy.shouldPrintMenu(_menu('DUP'), dup), isTrue);
    });
  });

  group('fromOrder — 필터 적용과 컵 식별자', () {
    const policy = LabelOutputPolicy(
      categoryFilterEnabled: true,
      categoryKeys: {coffeeKey},
    );

    test('선택 카테고리 라벨만 나온다', () {
      final order = _order([_menu('W1'), _menu('C1')]);
      final labels =
          LabelPrintData.fromOrder(order, products: _products, policy: policy);
      expect(labels.length, 1);
      expect(labels.single.menuName, 'C1');
    });

    test('컵 식별자 불변 — orderIndex/orderTotal 은 주문 전체 기준을 유지한다', () {
      // 디저트 2잔 + 커피 2잔. 커피만 인쇄돼도 번호는 3, 4 이고 분모는 4다.
      final order = _order([_menu('W1', qty: 2), _menu('C1', qty: 2)]);
      final labels =
          LabelPrintData.fromOrder(order, products: _products, policy: policy);
      expect(labels.map((l) => l.orderIndex), [3, 4]);
      expect(labels.map((l) => l.orderTotal), [4, 4]);
    });

    test('재출력은 필터를 우회해 전체를 인쇄한다', () {
      final order = _order([_menu('W1'), _menu('C1')]);
      final labels = LabelPrintData.fromOrder(
        order,
        products: _products,
        policy: policy,
        isReprint: true,
      );
      expect(labels.map((l) => l.menuName), ['W1', 'C1']);
    });

    test('전부 걸러지면 빈 목록 (호출부가 조용히 스킵한다)', () {
      final order = _order([_menu('W1')]);
      final labels =
          LabelPrintData.fromOrder(order, products: _products, policy: policy);
      expect(labels, isEmpty);
    });

    test('정책 미설정이면 종전대로 전량 인쇄 + 서브정보 없음', () {
      final order = _order([_menu('W1'), _menu('C1')]);
      final labels = LabelPrintData.fromOrder(order, products: _products);
      expect(labels.length, 2);
      expect(labels.every((l) => l.subInfo.isEmpty), isTrue);
    });
  });

  group('서브정보 — buildSubInfo', () {
    test('고른 순서대로 나온다 (설정 순서 = 인쇄 순서)', () {
      final menu = _menu('C1', options: [
        _opt('o-size', 'R', groupPosId: 'G_SIZE'),
        _opt('o-temp', 'ICE', groupPosId: 'G_TEMP'),
      ]);
      const forward =
          LabelOutputPolicy(subInfoGroupCodes: ['G_TEMP', 'G_SIZE']);
      const reverse =
          LabelOutputPolicy(subInfoGroupCodes: ['G_SIZE', 'G_TEMP']);
      expect(forward.buildSubInfo(menu, _index).values, ['ICE', 'R']);
      expect(reverse.buildSubInfo(menu, _index).values, ['R', 'ICE']);
    });

    test('지정하지 않은 그룹은 무시된다', () {
      final menu = _menu('C1', options: [
        _opt('o-temp', 'ICE', groupPosId: 'G_TEMP'),
        _opt('o-shot', '샷 추가', groupPosId: 'G_EXTRA'),
      ]);
      const policy = LabelOutputPolicy(subInfoGroupCodes: ['G_TEMP']);
      expect(policy.buildSubInfo(menu, _index).values, ['ICE']);
    });

    test('상한 3개 — 4개를 지정해도 3개까지만', () {
      final menu = _menu('C1', options: [
        _opt('a', 'A', groupPosId: 'G1'),
        _opt('b', 'B', groupPosId: 'G2'),
        _opt('c', 'C', groupPosId: 'G3'),
        _opt('d', 'D', groupPosId: 'G4'),
      ]);
      const policy =
          LabelOutputPolicy(subInfoGroupCodes: ['G1', 'G2', 'G3', 'G4']);
      final result = policy.buildSubInfo(menu, _index);
      expect(result.values, ['A', 'B', 'C']);
      expect(result.values.length, kLabelSubInfoMaxCount);
    });

    test('같은 그룹이 여러 번 오면 첫 값을 쓴다 (같은 주문은 항상 같은 라벨)', () {
      final menu = _menu('C1', options: [
        _opt('t1', 'ICE', groupPosId: 'G_TEMP'),
        _opt('t2', 'HOT', groupPosId: 'G_TEMP'),
      ]);
      const policy = LabelOutputPolicy(subInfoGroupCodes: ['G_TEMP']);
      expect(policy.buildSubInfo(menu, _index).values, ['ICE']);
    });

    test('optionGroupPosId 가 없으면 카탈로그 조인으로 폴백한다 (v0 응답)', () {
      // shopOptionId 가 카탈로그의 옵션 상품 TEMP1(categoryCode=G_TEMP)과 매칭.
      final menu = _menu('C1', options: [_opt('TEMP1', 'ICE')]);
      const policy = LabelOutputPolicy(subInfoGroupCodes: ['G_TEMP']);
      expect(policy.buildSubInfo(menu, _index).values, ['ICE']);
    });

    test('서브정보로 쓴 옵션은 라벨 하단 옵션 목록에서 빠진다', () {
      final order = _order([
        _menu('C1', options: [
          _opt('t1', 'ICE', groupPosId: 'G_TEMP'),
          _opt('x1', '샷 추가', groupPosId: 'G_EXTRA'),
        ])
      ]);
      final labels = LabelPrintData.fromOrder(
        order,
        products: _products,
        policy: const LabelOutputPolicy(subInfoGroupCodes: ['G_TEMP']),
      );
      expect(labels.single.subInfo, ['ICE']);
      expect(labels.single.options, ['샷 추가']);
    });

    test('동명 옵션 오제외 없음 — 소비된 옵션 객체만 빠진다', () {
      // 같은 이름의 옵션이 서로 다른 그룹에 있을 때, 이름으로 걸러면 둘 다 빠진다.
      final order = _order([
        _menu('C1', options: [
          _opt('a1', '추가', groupPosId: 'G_TEMP'),
          _opt('a2', '추가', groupPosId: 'G_EXTRA'),
        ])
      ]);
      final labels = LabelPrintData.fromOrder(
        order,
        products: _products,
        policy: const LabelOutputPolicy(subInfoGroupCodes: ['G_TEMP']),
      );
      expect(labels.single.subInfo, ['추가']);
      expect(labels.single.options, ['추가']);
    });
  });

  group('갭 라벨 painter 의 그리기 순서 반전', () {
    test('오른쪽부터 그리므로 목록을 뒤집어야 화면상 좌→우가 목록 순서가 된다', () {
      expect(LabelPainter.subInfoDrawOrder(['A', 'B', 'C']), ['C', 'B', 'A']);
    });

    test('빈 문자열은 자리를 차지하지 않는다', () {
      expect(LabelPainter.subInfoDrawOrder(['A', '', 'C']), ['C', 'A']);
    });
  });
}
