import 'package:appfit_order_agent/models/product_group.dart';
import 'package:appfit_order_agent/models/product_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// [ProductGroup] 파생 속성 고정 테스트.
///
/// 그룹 조립(중복 제거·카테고리 수집·정렬)은 `product_grouping_test.dart` 가
/// 담당하고, 여기서는 조립된 그룹이 화면·API 에 무엇을 노출하는지를 고정한다.

ProductModel _p({
  String name = '샷 추가',
  String productId = 'POS-1',
  String internalId = 'uuid-1',
  String categoryName = '옵션',
  int price = 500,
  ProductStatus status = ProductStatus.sale,
  ProductType type = ProductType.option,
  int displayOrder = 0,
}) =>
    ProductModel(
      productId: productId,
      productName: name,
      categoryName: categoryName,
      categoryCode: 'CAT',
      menuPrice: price,
      status: status,
      type: type,
      internalId: internalId,
      displayOrder: displayOrder,
    );

ProductGroup _group(
  List<ProductModel> members, {
  String name = '샷 추가',
  ProductType type = ProductType.option,
  List<String>? categoryNames,
}) =>
    ProductGroup(
      name: name,
      type: type,
      members: members,
      categoryNames:
          categoryNames ?? members.map((m) => m.categoryName).toSet().toList(),
      prices: members.map((m) => m.menuPrice).toSet().toList()..sort(),
    );

void main() {
  group('가격', () {
    test('고유 가격이 2종 이상이면 범위 표시 대상이고 min/max 가 양 끝이다', () {
      final g = _group([
        _p(internalId: 'a', price: 1000),
        _p(internalId: 'b', price: 500),
        _p(internalId: 'c', price: 700),
      ]);

      expect(g.hasPriceRange, isTrue);
      expect(g.prices, [500, 700, 1000]);
      expect(g.minPrice, 500);
      expect(g.maxPrice, 1000);
    });

    test('멤버가 여럿이어도 가격이 같으면 단일가격 표기를 유지한다', () {
      final g = _group([
        _p(internalId: 'a', price: 500),
        _p(internalId: 'b', price: 500),
      ]);

      expect(g.hasPriceRange, isFalse,
          reason: '가격이 같으면 "500 ~ 500원" 대신 기존 단일가격 표기여야 함');
      expect(g.minPrice, 500);
    });
  });

  group('상태 — 전원 품절일 때만 품절 (all-or-nothing 정책)', () {
    test('전원 품절이면 그룹도 품절이고 혼합이 아니다', () {
      final g = _group([
        _p(internalId: 'a', status: ProductStatus.soldOut),
        _p(internalId: 'b', status: ProductStatus.soldOut),
      ]);

      expect(g.status, ProductStatus.soldOut);
      expect(g.isSoldOut, isTrue);
      expect(g.isMixed, isFalse);
    });

    test('일부만 품절이면 판매중으로 보고 혼합으로 표시한다', () {
      final g = _group([
        _p(internalId: 'a', status: ProductStatus.soldOut),
        _p(internalId: 'b', status: ProductStatus.sale),
      ]);

      expect(g.status, ProductStatus.sale,
          reason: '판매중이라야 "전체 품절" 조작으로 정합성을 되돌릴 수 있다');
      expect(g.isSoldOut, isFalse);
      expect(g.isMixed, isTrue);
    });

    test('전원 판매중이면 판매중이고 혼합이 아니다', () {
      final g = _group([
        _p(internalId: 'a'),
        _p(internalId: 'b'),
      ]);

      expect(g.status, ProductStatus.sale);
      expect(g.isMixed, isFalse);
    });

    test('멤버가 1개면 혼합일 수 없다', () {
      expect(_group([_p(status: ProductStatus.soldOut)]).isMixed, isFalse);
      expect(_group([_p()]).isMixed, isFalse);
    });
  });

  group('internalIds — 상태변경 API 인자', () {
    test('빈 internalId 멤버는 제외한다', () {
      final g = _group([
        _p(internalId: 'uuid-a'),
        _p(internalId: '', productId: 'POS-2'),
        _p(internalId: 'uuid-c'),
      ]);

      expect(g.internalIds, ['uuid-a', 'uuid-c'], reason: '빈 UUID 는 서버가 거부한다');
      expect(g.memberCount, 3, reason: '표시 멤버 수는 줄지 않는다');
    });
  });

  group('displayOrder', () {
    test('전체 탭 정렬은 멤버 중 최소값을 쓴다', () {
      final g = _group([
        _p(internalId: 'a', displayOrder: 30),
        _p(internalId: 'b', displayOrder: 10),
      ]);

      expect(g.displayOrder, 10);
    });

    test('카테고리 탭 정렬은 그 카테고리 안의 최소값을 쓴다', () {
      final g = _group([
        _p(internalId: 'a', categoryName: '커피', displayOrder: 5),
        _p(internalId: 'b', categoryName: '디저트', displayOrder: 40),
        _p(internalId: 'c', categoryName: '디저트', displayOrder: 20),
      ]);

      expect(g.displayOrderIn('커피'), 5);
      expect(g.displayOrderIn('디저트'), 20,
          reason: '전역 최소값(5)이 아니라 해당 카테고리 내 최소값이어야 진열 순서가 보존된다');
    });

    test('소속되지 않은 카테고리를 물으면 전역 최소값으로 폴백한다', () {
      final g = _group([_p(internalId: 'a', displayOrder: 7)]);

      expect(g.displayOrderIn('없는카테고리'), 7);
    });
  });

  test('key 는 타입과 이름을 제어문자로 구분해 충돌을 피한다', () {
    final option = _group([_p()], name: '샷 추가', type: ProductType.option);
    final item = _group([_p(type: ProductType.item)],
        name: '샷 추가', type: ProductType.item);

    expect(option.key, isNot(item.key), reason: '이름이 같아도 타입이 다르면 별개 카드다');
    expect(option.key.contains(''), isTrue);
  });
}
