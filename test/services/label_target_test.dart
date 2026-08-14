import 'package:appfit_order_agent/models/order_menu_model.dart';
import 'package:appfit_order_agent/models/order_model.dart';
import 'package:appfit_order_agent/models/product_model.dart';
import 'package:appfit_order_agent/services/label_printer/fast_menu_policy.dart';
import 'package:appfit_order_agent/services/label_printer/label_filter_strategy.dart';
import 'package:appfit_order_agent/services/label_printer/label_print_data.dart';
import 'package:appfit_order_agent/services/label_printer/label_target.dart';
import 'package:flutter_test/flutter_test.dart';

// 제조 구역별 프린터 분담(LabelTarget) 의 불변식을 고정한다.
//
// 지키려는 것 3가지:
//  1) partition — 한 메뉴는 정확히 한 타깃. 합치면 전체와 같다(중복 0 / 누락 0).
//  2) 컵 식별자 불변 — orderIndex/orderTotal 은 타깃 분리와 무관하게 주문 전체 기준.
//  3) 폴백 — 미매핑/미상 카테고리는 primary. 어떤 설정에서도 라벨이 사라지지 않는다.

ProductModel _product({required String id, required String categoryCode}) {
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
  _product(id: 'W1', categoryCode: 'TKP1006'), // 디저트(와플)
  _product(id: 'C1', categoryCode: 'TKP9999'), // 음료
  _product(id: 'C2', categoryCode: 'TKP9999'), // 음료
  _product(id: 'TKP0051', categoryCode: 'TKP9999'), // 세트
];

OrderMenuModel _menu(String shopItemId, {int qty = 1}) {
  return OrderMenuModel(
    orderNo: 'o1',
    shopItemId: shopItemId,
    qty: qty,
    itemName: shopItemId,
    itemPrice: 1000,
    totalAmount: 1000,
    discPrc: 0,
    vatPrc: 0,
    options: const [],
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

/// 디저트는 dessert 프린터, 음료는 매핑 없음(=primary).
const _policy = LabelTargetPolicy(
  assignment: {'TKP1006': 'dessert'},
  localTargets: <String>{},
);

/// 위 정책 + "빠른 메뉴는 zone2 로". 카테고리 배정과 **충돌하도록** 짜 둔다 —
/// 우선순위를 세우는 것이 이 배정의 존재 이유라, 겹치지 않는 예시로는 검증이 안 된다.
const _fastToZone2 = LabelTargetPolicy(
  assignment: {'TKP1006': 'dessert'},
  localTargets: <String>{},
  fastMenuTarget: 'zone2',
);

/// 'C1'(음료) 만 빠른 메뉴. 정렬은 하지 않고 멤버십 판정만 쓰는 구성.
const _fastC1 = FastMenuPolicy(
  mode: FastMenuMode.off,
  showMarker: false,
  fastIds: {'C1'},
);

void main() {
  group('LabelTargetPolicy.targetForCategory', () {
    test('매핑된 카테고리는 그 타깃으로 간다', () {
      expect(
          _policy.targetForCategory('TKP1006'), const LabelTarget('dessert'));
    });

    test('미매핑·null·빈 문자열은 전부 primary 폴백', () {
      expect(_policy.targetForCategory('TKP9999'), LabelTarget.primary);
      expect(_policy.targetForCategory(null), LabelTarget.primary);
      expect(_policy.targetForCategory(''), LabelTarget.primary);
    });

    test('배정표가 비면 무엇을 물어도 primary (미설정 매장 = 종전 동작)', () {
      expect(LabelTargetPolicy.disabled.targetForCategory('TKP1006'),
          LabelTarget.primary);
    });
  });

  group('LabelTargetPolicy.handles', () {
    test('담당 타깃이 비어 있으면 전부 담당한다 (기본값 = 라벨 소실 0)', () {
      expect(LabelTargetPolicy.disabled.handles(LabelTarget.primary), isTrue);
      expect(LabelTargetPolicy.disabled.handles(const LabelTarget('dessert')),
          isTrue);
    });

    test('담당 타깃이 지정되면 그 집합만 담당한다', () {
      const p = LabelTargetPolicy(
        assignment: {'TKP1006': 'dessert'},
        localTargets: {'dessert'},
      );
      expect(p.handles(const LabelTarget('dessert')), isTrue);
      expect(p.handles(LabelTarget.primary), isFalse);
    });
  });

  group('LabelFilterStrategy.assignTarget', () {
    test('기본 구현은 상품 카테고리 코드를 배정표에 조회한다', () {
      const s = NoOpLabelFilterStrategy();
      expect(
        s.assignTarget(_menu('W1'), products: _products, policy: _policy),
        const LabelTarget('dessert'),
      );
      expect(
        s.assignTarget(_menu('C1'), products: _products, policy: _policy),
        LabelTarget.primary,
      );
    });

    test('TPCP 전략도 같은 기본 구현을 쓴다 (필터와 행선지는 직교 축)', () {
      const s = TpcpLabelFilterStrategy();
      expect(
        s.assignTarget(_menu('W1'), products: _products, policy: _policy),
        const LabelTarget('dessert'),
      );
    });

    test('빠른 메뉴 배정이 카테고리 배정을 이긴다 (점이 면을 덮는다)', () {
      const s = NoOpLabelFilterStrategy();
      // W1 은 카테고리상 dessert 인데 빠른 메뉴로 들어오면 zone2 로 간다.
      expect(
        s.assignTarget(_menu('W1'),
            products: _products, policy: _fastToZone2, isFastMenu: true),
        LabelTarget.zone2,
      );
      // 같은 메뉴라도 빠른 메뉴가 아니면 종전대로 카테고리 배정.
      expect(
        s.assignTarget(_menu('W1'), products: _products, policy: _fastToZone2),
        const LabelTarget('dessert'),
      );
    });

    test('fastMenuTarget 미설정이면 isFastMenu 여부가 행선지를 바꾸지 않는다', () {
      const s = NoOpLabelFilterStrategy();
      expect(
        s.assignTarget(_menu('W1'),
            products: _products, policy: _policy, isFastMenu: true),
        const LabelTarget('dessert'),
      );
      expect(
        s.assignTarget(_menu('C1'),
            products: _products, policy: _policy, isFastMenu: true),
        LabelTarget.primary,
      );
    });

    test('카탈로그에 없는 상품이어도 빠른 메뉴면 그 구역으로 간다', () {
      // 빠른 메뉴 판정은 ID 집합 멤버십이라 상품 카탈로그 조회와 무관하다.
      // 신상품이 카탈로그에 늦게 들어와도 배정이 흔들리지 않는다는 뜻.
      const s = NoOpLabelFilterStrategy();
      expect(
        s.assignTarget(_menu('UNKNOWN'),
            products: _products, policy: _fastToZone2, isFastMenu: true),
        LabelTarget.zone2,
      );
    });

    test('카탈로그에 없는 상품은 primary 폴백 — 신상품이 라벨을 잃지 않는다', () {
      const s = NoOpLabelFilterStrategy();
      expect(
        s.assignTarget(_menu('UNKNOWN'), products: _products, policy: _policy),
        LabelTarget.primary,
      );
    });

    test('internalId 로 들어온 shopItemId 도 매칭된다', () {
      const s = NoOpLabelFilterStrategy();
      expect(
        s.assignTarget(_menu('internal-W1'),
            products: _products, policy: _policy),
        const LabelTarget('dessert'),
      );
    });
  });

  group('fromOrder 의 타깃 배정 불변식', () {
    final order = _order([_menu('W1', qty: 2), _menu('C1'), _menu('C2')]);

    test('partition — 타깃별 라벨 수의 합이 전체와 같다 (중복 0 / 누락 0)', () {
      final labels = LabelPrintData.fromOrder(order,
          products: _products, targetPolicy: _policy);

      expect(labels.length, 4); // 와플 2 + 음료 2
      final byTarget = <LabelTarget, int>{};
      for (final d in labels) {
        byTarget[d.target] = (byTarget[d.target] ?? 0) + 1;
      }
      expect(byTarget[const LabelTarget('dessert')], 2);
      expect(byTarget[LabelTarget.primary], 2);
      expect(byTarget.values.reduce((a, b) => a + b), labels.length);
    });

    test('같은 메뉴의 qty 장은 전부 같은 프린터로 간다', () {
      final labels = LabelPrintData.fromOrder(order,
          products: _products, targetPolicy: _policy);
      final waffleTargets =
          labels.where((d) => d.menuName == 'W1').map((d) => d.target).toSet();
      expect(waffleTargets, {const LabelTarget('dessert')});
    });

    test('컵 식별자 불변 — 타깃 정책 유무가 orderIndex/orderTotal 을 바꾸지 않는다', () {
      final without = LabelPrintData.fromOrder(order, products: _products);
      final with_ = LabelPrintData.fromOrder(order,
          products: _products, targetPolicy: _policy);

      expect(with_.map((d) => d.orderIndex).toList(),
          without.map((d) => d.orderIndex).toList());
      expect(with_.map((d) => d.orderTotal).toSet(), {4});
      // 타깃을 나눠도 orderTotal 은 주문 전체 기준을 유지한다 (QR cupIdx 정본).
      expect(with_.every((d) => d.orderTotal == 4), isTrue);
    });

    test('재출력도 행선지를 그대로 유지한다 (필터만 우회, 라우팅은 불변)', () {
      final labels = LabelPrintData.fromOrder(order,
          products: _products, targetPolicy: _policy, isReprint: true);
      expect(labels.length, 4);
      expect(
          labels.where((d) => d.target == const LabelTarget('dessert')).length,
          2);
    });

    test('정책 미설정이면 전량 primary — 종전 동작과 동일', () {
      final labels = LabelPrintData.fromOrder(order, products: _products);
      expect(labels.every((d) => d.target == LabelTarget.primary), isTrue);
    });

    test('빠른 메뉴 구역이 fromOrder 까지 이어진다 — C1 만 zone2', () {
      final labels = LabelPrintData.fromOrder(
        order,
        products: _products,
        targetPolicy: _fastToZone2,
        fastMenuPolicy: _fastC1,
      );

      expect(labels.length, 4);
      final zone2 = labels.where((d) => d.target == LabelTarget.zone2).toList();
      expect(zone2.map((d) => d.menuName).toList(), ['C1']);
      // 나머지는 종전 배정 그대로 — 새 규칙이 다른 메뉴를 건드리지 않는다.
      expect(
          labels.where((d) => d.target == const LabelTarget('dessert')).length,
          2);
      expect(labels.where((d) => d.target == LabelTarget.primary).length, 1);
    });

    test('빠른 메뉴 구역을 켜도 컵 식별자는 불변 (QR 정본)', () {
      final without = LabelPrintData.fromOrder(order, products: _products);
      final with_ = LabelPrintData.fromOrder(
        order,
        products: _products,
        targetPolicy: _fastToZone2,
        fastMenuPolicy: _fastC1,
      );

      expect(with_.map((d) => d.orderIndex).toList(),
          without.map((d) => d.orderIndex).toList());
      expect(with_.every((d) => d.orderTotal == 4), isTrue);
    });

    test('빠른 메뉴 정렬(모드 1)과 구역 배정을 함께 걸어도 컵 번호는 원본 순서 기준', () {
      const sortAndMark = FastMenuPolicy(
        mode: FastMenuMode.withinOrder,
        showMarker: false,
        fastIds: {'C1'},
      );
      final labels = LabelPrintData.fromOrder(
        order,
        products: _products,
        targetPolicy: _fastToZone2,
        fastMenuPolicy: sortAndMark,
      );

      // 인쇄 순서는 C1 이 앞으로 나오지만(정렬), 컵 번호는 원본 순서 채번이라
      // W1 이 1,2 / C1 이 3 / C2 가 4 를 유지한다.
      expect(labels.first.menuName, 'C1');
      expect(labels.first.orderIndex, 3);
      expect(labels.first.target, LabelTarget.zone2);
      expect(
        {for (final d in labels) d.menuName: d.orderIndex}['C2'],
        4,
      );
    });

    test('담당 타깃으로 걸러도 남은 라벨의 orderIndex 는 원본 값 그대로다', () {
      const dessertOnly = LabelTargetPolicy(
        assignment: {'TKP1006': 'dessert'},
        localTargets: {'dessert'},
      );
      final labels = LabelPrintData.fromOrder(order,
          products: _products, targetPolicy: dessertOnly);
      final mine = labels.where((d) => dessertOnly.handles(d.target)).toList();

      expect(mine.length, 2);
      // 와플이 주문의 첫 메뉴(qty 2)라 컵 번호는 1,2 — 그리고 총량은 4로 유지.
      expect(mine.map((d) => d.orderIndex).toList(), [1, 2]);
      expect(mine.every((d) => d.orderTotal == 4), isTrue);
    });
  });
}
