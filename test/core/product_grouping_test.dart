import 'package:appfit_order_agent/core/products/product_grouping.dart';
import 'package:appfit_order_agent/models/product_group.dart';
import 'package:appfit_order_agent/models/product_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// 상품관리 그룹핑·필터 정책 고정 테스트.
///
/// 상품명이 같고 가격만 다른 레코드를 카드 1장으로 묶어 일괄 품절하는 기능의
/// 근간이다. 특히 아래 두 불변식은 깨지면 곧바로 운영 사고가 된다.
///  - `(이름, 타입)` 이 그룹 키다. 타입이 섞이면 itemIds/optionIds 를 한 요청에
///    섞어 보내게 된다.
///  - 같은 상품이 여러 카테고리에 등록돼 생긴 복제본은 1건으로 접혀야 한다.

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

ProductGroup _byName(List<ProductGroup> groups, String name,
        {ProductType? type}) =>
    groups
        .firstWhere((g) => g.name == name && (type == null || g.type == type));

void main() {
  group('visibleProducts', () {
    test('hidden 은 제외하고 상품명 부분일치로 검색한다(대소문자 무시)', () {
      final products = [
        _p(name: 'Americano', internalId: 'a'),
        _p(name: '아메리카노', internalId: 'b'),
        _p(
            name: 'Americano Ice',
            internalId: 'c',
            status: ProductStatus.hidden),
      ];

      final result = visibleProducts(products, 'ameri').toList();

      expect(result.map((p) => p.internalId), ['a']);
    });

    test('그룹 멤버 중 hidden 만 빠지고 나머지는 남는다', () {
      final products = [
        _p(internalId: 'a', price: 500),
        _p(internalId: 'b', price: 700, status: ProductStatus.hidden),
        _p(internalId: 'c', price: 1000),
      ];

      final groups = buildProductGroups(visibleProducts(products, ''));

      expect(groups, hasLength(1));
      expect(groups.single.prices, [500, 1000],
          reason: '미노출 상품은 일괄 품절 대상에 포함되면 안 된다');
    });

    test('전 멤버가 hidden 이면 그룹 자체가 생기지 않는다', () {
      final products = [
        _p(internalId: 'a', status: ProductStatus.hidden),
        _p(internalId: 'b', status: ProductStatus.hidden),
      ];

      expect(buildProductGroups(visibleProducts(products, '')), isEmpty);
    });
  });

  group('buildProductGroups', () {
    test('빈 입력은 빈 결과', () {
      expect(buildProductGroups(const <ProductModel>[]), isEmpty);
    });

    test('이름과 타입이 같으면 카테고리가 달라도 한 그룹이다', () {
      final groups = buildProductGroups([
        _p(internalId: 'a', categoryName: '커피', price: 3000),
        _p(internalId: 'b', categoryName: '디저트', price: 3500),
      ]);

      expect(groups, hasLength(1));
      expect(groups.single.memberCount, 2);
      expect(groups.single.categoryNames, ['커피', '디저트']);
      expect(groups.single.prices, [3000, 3500]);
    });

    test('이름이 같아도 타입이 다르면 별개 그룹이다', () {
      final groups = buildProductGroups([
        _p(internalId: 'a', type: ProductType.item, categoryName: '커피'),
        _p(internalId: 'b', type: ProductType.option),
      ]);

      expect(groups, hasLength(2),
          reason: '타입이 섞이면 itemIds/optionIds 를 한 요청에 섞어 보내게 된다');
      expect(_byName(groups, '샷 추가', type: ProductType.item).memberCount, 1);
      expect(_byName(groups, '샷 추가', type: ProductType.option).memberCount, 1);
    });

    test('같은 internalId 의 카테고리 복제본은 1건으로 접되 카테고리는 모두 보존한다', () {
      final groups = buildProductGroups([
        _p(internalId: 'same', categoryName: '커피', displayOrder: 3),
        _p(internalId: 'same', categoryName: '신메뉴', displayOrder: 9),
      ]);

      expect(groups.single.memberCount, 1);
      expect(groups.single.internalIds, ['same'],
          reason: '같은 UUID 를 서버에 중복 전송하면 안 된다');
      expect(groups.single.categoryNames, ['커피', '신메뉴'],
          reason: '중복 제거 이전에 카테고리를 모아야 두 번째 카테고리가 유실되지 않는다');
    });

    test('internalId 가 비면 productId 로 폴백해 서로 다른 상품이 뭉개지지 않는다', () {
      final groups = buildProductGroups([
        _p(internalId: '', productId: 'POS-1', price: 500),
        _p(internalId: '', productId: 'POS-2', price: 700),
      ]);

      expect(groups.single.memberCount, 2);
      expect(groups.single.prices, [500, 700]);
      expect(groups.single.internalIds, isEmpty,
          reason: 'UUID 가 없으면 상태변경 대상에서 제외된다');
    });

    test('상품명 앞뒤 공백 차이는 같은 그룹으로 보고 표시명은 trim 한다', () {
      final groups = buildProductGroups([
        _p(name: '샷 추가 ', internalId: 'a', price: 500),
        _p(name: '샷 추가', internalId: 'b', price: 700),
      ]);

      expect(groups, hasLength(1), reason: 'POS 끝공백 때문에 조용히 안 묶이는 사고를 막는다');
      expect(groups.single.name, '샷 추가');
    });
  });

  group('productGroupCategoryCounts', () {
    test('여러 카테고리에 걸친 그룹은 각 카테고리에서 1장으로 센다', () {
      final groups = buildProductGroups([
        _p(name: '아메리카노', internalId: 'a', categoryName: '커피'),
        _p(name: '아메리카노', internalId: 'b', categoryName: '신메뉴'),
        _p(name: '라떼', internalId: 'c', categoryName: '커피'),
      ]);

      final counts = productGroupCategoryCounts(groups);

      expect(counts['커피'], 2);
      expect(counts['신메뉴'], 1);
      expect(counts.values.reduce((a, b) => a + b), greaterThan(groups.length),
          reason: '카테고리 합계가 전체보다 큰 것은 교차 등록 시 정상이다');
    });
  });

  group('filterProductGroups', () {
    List<ProductGroup> fixture() => buildProductGroups([
          // 전원 품절 그룹
          _p(
              name: '샷 추가',
              internalId: 'a',
              price: 500,
              displayOrder: 20,
              status: ProductStatus.soldOut),
          _p(
              name: '샷 추가',
              internalId: 'b',
              price: 1000,
              displayOrder: 21,
              status: ProductStatus.soldOut),
          // 혼합 그룹
          _p(
              name: '시럽 추가',
              internalId: 'c',
              displayOrder: 10,
              status: ProductStatus.soldOut),
          _p(name: '시럽 추가', internalId: 'd', price: 300, displayOrder: 11),
          // 커피 카테고리 단일 상품
          _p(
              name: '아메리카노',
              internalId: 'e',
              categoryName: '커피',
              type: ProductType.item,
              price: 3000,
              displayOrder: 1),
        ]);

    test('전체 탭은 모든 그룹을 카테고리 복제 중복 없이 낸다', () {
      final groups = buildProductGroups([
        _p(internalId: 'same', categoryName: '커피'),
        _p(internalId: 'same', categoryName: '신메뉴'),
      ]);

      final result = filterProductGroups(groups, const AllGroups());

      expect(result, hasLength(1),
          reason: '기존 전체 탭의 internalId 중복 제거를 그룹핑이 대체한다');
    });

    test('품절 탭은 전원 품절 그룹만 내고 혼합 그룹은 제외한다', () {
      final result = filterProductGroups(fixture(), const SoldOutGroups());

      expect(result.map((g) => g.name), ['샷 추가'],
          reason: '혼합 그룹은 카드가 판매중으로 보이므로 품절 탭에 있으면 표기가 모순된다');
    });

    test('카테고리 탭은 그 카테고리를 포함한 그룹만 낸다', () {
      final result = filterProductGroups(fixture(), const CategoryGroups('커피'));

      expect(result.map((g) => g.name), ['아메리카노']);
    });

    test('카테고리 탭은 그 카테고리 안의 displayOrder 로 정렬한다', () {
      // 전역 최소값으로 정렬하면 순서가 뒤집히는 배치:
      //  A 는 '신메뉴'(1)에도 있어 전역 최소가 1이지만, '커피' 안에서는 50이다.
      final groups = buildProductGroups([
        _p(name: 'A', internalId: 'a1', categoryName: '신메뉴', displayOrder: 1),
        _p(name: 'A', internalId: 'a2', categoryName: '커피', displayOrder: 50),
        _p(name: 'B', internalId: 'b1', categoryName: '커피', displayOrder: 10),
      ]);

      final result = filterProductGroups(groups, const CategoryGroups('커피'));

      expect(result.map((g) => g.name), ['B', 'A'],
          reason: '전역 최소값(A=1)으로 정렬하면 A 가 앞서 진열 순서가 어긋난다');
    });

    test('displayOrder 가 같아도 호출마다 순서가 흔들리지 않는다', () {
      final groups = buildProductGroups([
        _p(name: '가', internalId: 'a', displayOrder: 5),
        _p(name: '나', internalId: 'b', displayOrder: 5),
        _p(name: '다', internalId: 'c', displayOrder: 5),
      ]);

      final first = filterProductGroups(groups, const AllGroups());
      final second = filterProductGroups(groups, const AllGroups());

      expect(second.map((g) => g.name), first.map((g) => g.name),
          reason: 'List.sort 는 안정 정렬이 아니라 2차 키가 없으면 카드가 뒤바뀐다');
    });
  });

  group('ProductGroupFilter 동등성 — 좌측 타일 선택 표시가 의존한다', () {
    test('같은 카테고리명이면 같은 필터다', () {
      expect(const CategoryGroups('커피'), const CategoryGroups('커피'));
      expect(const CategoryGroups('커피'), isNot(const CategoryGroups('디저트')));
    });

    test('전체/품절 필터는 각각 자기 자신과만 같다', () {
      expect(const AllGroups(), const AllGroups());
      expect(const SoldOutGroups(), const SoldOutGroups());
      expect(const AllGroups(), isNot(const SoldOutGroups()));
      expect(const AllGroups(), isNot(const CategoryGroups('전체')));
    });
  });
}
