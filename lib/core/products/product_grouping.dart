import 'package:appfit_order_agent/models/product_group.dart';
import 'package:appfit_order_agent/models/product_model.dart';
import 'package:appfit_order_agent/utils/logger.dart';

/// 상품관리 화면의 그룹핑·필터 정책. UI 없이 테스트할 수 있도록 순수 함수로 둔다
/// (`socket_wake_policy` 와 같은 규약).

/// 상품관리 좌측 목록의 선택 상태.
///
/// 과거에는 번역 문자열(`t.product_mgmt.sold_out`) 자체를 선택 키로 썼다. 로케일을
/// 바꾸면 선택이 조용히 풀리고, '품절'이라는 이름의 실제 카테고리가 있으면 품절
/// 탭에 하이재킹된다. 값 타입으로 분리해 두 결함을 함께 제거한다.
sealed class ProductGroupFilter {
  const ProductGroupFilter();
}

/// 전체 탭.
final class AllGroups extends ProductGroupFilter {
  const AllGroups();

  @override
  bool operator ==(Object other) => other is AllGroups;

  @override
  int get hashCode => (AllGroups).hashCode;
}

/// 품절 탭 — **전원 품절인 그룹만**.
final class SoldOutGroups extends ProductGroupFilter {
  const SoldOutGroups();

  @override
  bool operator ==(Object other) => other is SoldOutGroups;

  @override
  int get hashCode => (SoldOutGroups).hashCode;
}

/// 카테고리 탭. 좌측 타일의 선택 표시가 동등성에 의존한다.
final class CategoryGroups extends ProductGroupFilter {
  final String categoryName;
  const CategoryGroups(this.categoryName);

  @override
  bool operator ==(Object other) =>
      other is CategoryGroups && other.categoryName == categoryName;

  @override
  int get hashCode => categoryName.hashCode;
}

/// 화면에 노출될 수 있는 상품의 공통 base — hidden 제외 + 상품명 검색.
///
/// 그룹핑 **이전** 단계다. 검색어는 상품명에만 걸리고 그룹 멤버는 이름이 모두
/// 같으므로 그룹이 검색으로 부분만 잘리는 일은 없다. 반면 hidden 멤버만 골라
/// 빠지는 것은 의도된 동작이다 — 미노출 상품을 일괄 품절 대상에 포함시키면 안 된다.
Iterable<ProductModel> visibleProducts(
  List<ProductModel> products,
  String searchQuery,
) {
  final query = searchQuery.toLowerCase();
  return products.where((p) =>
      p.status != ProductStatus.hidden &&
      p.productName.toLowerCase().contains(query));
}

/// `(상품명, 타입)` 이 같으면 한 그룹으로 묶는다. 카테고리는 넘나든다.
///
/// 상품명은 `trim()` 후 비교한다 — POS 데이터의 끝공백 차이로 "왜 안 묶이지"가
/// 되는 사고를 막는다. 표시명도 trim 된 이름을 쓴다.
List<ProductGroup> buildProductGroups(Iterable<ProductModel> products) {
  // Dart 3 record 는 구조적 동등성이라 그대로 Map 키로 쓸 수 있다(구분자 충돌 없음).
  final acc = <(String, ProductType), _GroupAccumulator>{};
  var total = 0;
  for (final p in products) {
    total++;
    final key = (p.productName.trim(), p.type);
    (acc[key] ??= _GroupAccumulator(key.$1, key.$2)).add(p);
  }

  final groups = acc.values.map((a) => a.build()).toList();
  logger.d('[상품관리] 그룹핑: 상품 $total건 → 카드 ${groups.length}장 '
      '(다중가격 ${groups.where((g) => g.hasPriceRange).length}장)');
  return groups;
}

/// 카테고리별 카드 수 — 해당 카테고리 탭을 눌렀을 때 그리드에 실제로 뜨는 수.
///
/// 한 그룹이 여러 카테고리에 걸쳐 있으면 **각 카테고리에서 1장**으로 센다.
/// 카테고리 탭 = "이 카테고리 상품을 포함하는 카드 목록" 이고 그리드도 같은 기준
/// 으로 뽑으므로, 이 규칙이라야 "N개라고 써 있는데 눌러보면 개수가 다름"이 안 난다.
/// 그 결과 카테고리 카운트의 합이 전체 카운트보다 클 수 있고, 그게 정상이다
/// (그룹핑 이전 상품 단위에서도 동일한 성질이었다).
Map<String, int> productGroupCategoryCounts(List<ProductGroup> groups) {
  final counts = <String, int>{};
  for (final group in groups) {
    for (final name in group.categoryNames) {
      counts[name] = (counts[name] ?? 0) + 1;
    }
  }
  return counts;
}

/// [filter] 를 선택했을 때 그리드에 표시되는 그룹 목록.
///
/// 좌측 타일 카운트도 이 결과의 길이와 일치해야 한다(그리드 = 카운트 단일 정본).
List<ProductGroup> filterProductGroups(
  List<ProductGroup> groups,
  ProductGroupFilter filter,
) {
  final List<ProductGroup> result = switch (filter) {
    AllGroups() => groups.toList(),
    // 그룹 상태 = 전원 품절일 때만 품절이므로, 일부만 품절인 그룹은 카드가
    // '판매중'으로 보인다 — 품절 탭에도 넣지 않아야 탭과 카드 표기가 어긋나지
    // 않는다("품절 탭에 있는데 판매중이라고 뜬다" 방지).
    SoldOutGroups() => groups.where((g) => g.isSoldOut).toList(),
    CategoryGroups(:final categoryName) =>
      groups.where((g) => g.categoryNames.contains(categoryName)).toList(),
  };

  // 카테고리 탭은 그 카테고리 안에서의 displayOrder 로 정렬해 기존 진열 순서를
  // 보존한다. Dart 의 List.sort 는 안정 정렬이 아니므로 동점일 때 이름·타입으로
  // 2차 정렬해, 일괄 변경 직후 재빌드에서 카드 순서가 뒤바뀌는 것을 막는다.
  int orderOf(ProductGroup g) => switch (filter) {
        CategoryGroups(:final categoryName) => g.displayOrderIn(categoryName),
        _ => g.displayOrder,
      };
  result.sort((a, b) {
    final byOrder = orderOf(a).compareTo(orderOf(b));
    if (byOrder != 0) return byOrder;
    final byName = a.name.compareTo(b.name);
    return byName != 0 ? byName : a.type.index.compareTo(b.type.index);
  });
  return result;
}

/// 그룹 1개를 조립하는 동안의 중간 상태.
class _GroupAccumulator {
  _GroupAccumulator(this.name, this.type);

  final String name;
  final ProductType type;

  /// dedupe 키 → 첫 등장 멤버.
  final Map<String, ProductModel> _members = {};

  /// 등장 순서를 보존하는 카테고리명 집합(LinkedHashSet).
  final Set<String> _categories = {};

  void add(ProductModel p) {
    // 카테고리는 **중복 제거 이전** 원본에서 모은다 — dedupe 후에 모으면 같은
    // 상품이 등록된 두 번째 카테고리가 통째로 사라진다.
    _categories.add(p.categoryName);

    // internalId 가 정본. 빈 값이면 productId 로 폴백해 서로 다른 상품이 한
    // 멤버로 뭉개지는 것을 막는다(빈 internalId 는 상태변경 대상에서 제외됨).
    final key =
        p.internalId.isNotEmpty ? 'i:${p.internalId}' : 'p:${p.productId}';
    _members.putIfAbsent(key, () => p);
  }

  ProductGroup build() {
    final members = _members.values.toList();
    final prices = members.map((m) => m.menuPrice).toSet().toList()..sort();

    final missing = members.where((m) => m.internalId.isEmpty).length;
    if (missing > 0) {
      logger.w('[상품관리] 그룹 "$name"(${type.code}) 에 internalId 없는 멤버 $missing건 '
          '— 일괄 상태변경 대상에서 제외됨');
    }

    return ProductGroup(
      name: name,
      type: type,
      members: members,
      categoryNames: _categories.toList(),
      prices: prices,
    );
  }
}
