import 'package:appfit_order_agent/models/product_model.dart';
import 'package:appfit_order_agent/models/shop_category_model.dart';
import 'package:appfit_order_agent/utils/logger.dart';

/// `GET /v0/shops/{shopCode}/categories/items` 응답 → 앱 모델 변환.
///
/// Dio 를 타지 않는 순수 함수로 둬 응답 형태 변화를 테스트로 고정한다
/// (`product_grouping.dart` 와 같은 규약).
///
/// 응답은 `카테고리 > 상품 > 옵션그룹 > 옵션` 4단 중첩이다. 앱의 상품 목록은
/// 평면이라 두 가지 변환이 필요하다.
///  - 카테고리는 상품과 **분리해** 함께 반환한다. 소속 상품이 0개인 카테고리는
///    평탄화하면 흔적이 남지 않아 사라지기 때문이다(상품관리 좌측 목록 정본).
///  - 옵션은 **상품×옵션그룹마다 반복 등장**한다. 구 `/categories` 의 매장 전역
///    `options[]` 와 달리 같은 `optionId` 가 여러 번 나오므로, 앱의 인공 카테고리
///    '옵션' 버킷을 만들 때 반드시 중복을 접어야 한다.

/// 옵션 전용 인공 카테고리명. 서버가 내려주는 카테고리가 아니라 앱이 만드는
/// 버킷이라 `categories[]` 에는 없고 상품 쪽에만 존재한다.
const String kOptionBucketCategoryName = '옵션';

/// 옵션 버킷의 displayOrder 오프셋.
///
/// 옵션에도 서버 `displayOrder` 가 생겼지만 그건 **옵션그룹 안에서의 순서**라
/// 상품의 카테고리 내 순서와 같은 좌표계가 아니다. 큰 오프셋을 더해 옵션 버킷
/// 전체를 상품 뒤로 보내는 종전 규칙을 유지한다.
const int kOptionDisplayOrderBase = 1000000;

/// AppFit 상태 코드 → [ProductStatus].
///
/// 알 수 없는 값은 hidden 으로 접는다 — 모르는 상태를 판매중으로 노출하는 것보다
/// 안전하다.
ProductStatus productStatusFromAppFit(String appFitStatus) {
  switch (appFitStatus.toUpperCase()) {
    case 'ON_SALE':
    case 'SALE':
      return ProductStatus.sale; // OS
    case 'SOLD_OUT':
      return ProductStatus.soldOut; // SO
    case 'DISCONTINUED':
    case 'HIDDEN':
    case 'PENDING':
    default:
      return ProductStatus.hidden; // HD
  }
}

/// 응답 본문(`response.data['data']`)을 상품/카테고리 목록으로 변환한다.
({List<ProductModel> products, List<ShopCategoryModel> categories})
    parseShopCatalog(Map<String, dynamic> data) {
  final products = <ProductModel>[];
  final categories = <ShopCategoryModel>[];

  // 삽입 순서를 보존하는 Map(LinkedHashMap) — 옵션 버킷의 표시 순서가 된다.
  final options = <String, _OptionAccumulator>{};
  var optionOccurrences = 0;

  final rawCategories = (data['categories'] as List<dynamic>?) ?? const [];
  for (final rawCategory in rawCategories) {
    if (rawCategory is! Map<String, dynamic>) {
      logger.e('[카탈로그] 카테고리 항목이 객체가 아님 — 스킵 ($rawCategory)');
      continue;
    }

    // 항목별 격리 — 1건 손상 시 해당 카테고리만 스킵하고 나머지는 유지.
    final ShopCategoryModel category;
    try {
      category = ShopCategoryModel.fromJson(rawCategory);
    } catch (e) {
      logger.e('[카탈로그] 카테고리 파싱 실패 — 해당 항목 스킵', error: e);
      continue;
    }
    categories.add(category);

    final rawItems = (rawCategory['items'] as List<dynamic>?) ?? const [];
    for (final rawItem in rawItems) {
      if (rawItem is! Map<String, dynamic>) continue;

      final item = _parseItem(rawItem, category);
      if (item != null) products.add(item);

      // 옵션은 상품이 스킵돼도 수집한다 — 옵션 버킷은 상품 소속과 무관한
      // 매장 단위 목록이라, 상품 1건이 손상됐다고 그 옵션들까지 잃을 이유가 없다.
      final rawGroups = (rawItem['optionGroups'] as List<dynamic>?) ?? const [];
      for (final rawGroup in rawGroups) {
        if (rawGroup is! Map<String, dynamic>) continue;
        // 그룹의 POS 코드가 옵션의 categoryCode 가 된다(구 migration 조인 대체).
        final groupPosId = rawGroup['optionGroupPosId']?.toString() ?? '';
        final rawOptions = (rawGroup['options'] as List<dynamic>?) ?? const [];
        for (final rawOption in rawOptions) {
          if (rawOption is! Map<String, dynamic>) continue;
          optionOccurrences++;
          _accumulateOption(options, rawOption, groupPosId);
        }
      }
    }
  }

  // 옵션 버킷 — dedupe 후 등장 순서대로 displayOrder 를 부여한다.
  var optionOrder = 0;
  for (final accumulator in options.values) {
    products.add(accumulator.product
        .copyWith(displayOrder: kOptionDisplayOrderBase + optionOrder++));
  }

  _logDivergence(options.values);
  logger.i('[카탈로그] 파싱 완료: 카테고리 ${categories.length}개 / '
      '상품 ${products.length - options.length}건 / '
      '옵션 원본 $optionOccurrences건 → 고유 ${options.length}건');

  return (products: products, categories: categories);
}

/// 상품 1건. 식별자가 없으면 상태 변경도 매칭도 불가능하므로 해당 건만 버린다.
ProductModel? _parseItem(
  Map<String, dynamic> item,
  ShopCategoryModel category,
) {
  final itemPosId = item['itemPosId']?.toString() ?? '';
  final shopItemId = item['shopItemId']?.toString() ?? '';
  final itemName = item['itemName']?.toString() ?? '';
  if (shopItemId.isEmpty && itemPosId.isEmpty) {
    logger.w('[카탈로그] 상품 식별자 없음 — 스킵 (카테고리 ${category.categoryName}, '
        '이름 "$itemName")');
    return null;
  }

  return ProductModel(
    productId: itemPosId, // prdId 용 (POS ID)
    internalId: shopItemId, // API 용 (UUID)
    productName: itemName,
    categoryName: category.categoryName,
    categoryCode: category.categoryCode,
    menuPrice: (item['salePrice'] as num?)?.toInt() ?? 0,
    status: productStatusFromAppFit(item['status']?.toString() ?? ''),
    type: ProductType.item,
    displayOrder: (item['displayOrder'] as num?)?.toInt() ?? 0,
  );
}

/// 옵션 1건을 dedupe 맵에 누적한다. **첫 등장 값이 정본**이고, 재등장분은
/// 불일치 감시용으로만 기록한다.
void _accumulateOption(
  Map<String, dynamic> accumulated,
  Map<String, dynamic> option,
  String groupPosId,
) {
  final optionId = option['optionId']?.toString() ?? '';
  final optionPosId = option['optionPosId']?.toString() ?? '';
  // 상태 변경 API(`optionIds`)가 쓰는 UUID 가 정본 키다. 비면 POS ID 로 폴백해
  // 서로 다른 옵션이 한 건으로 뭉개지는 것을 막는다.
  final key = optionId.isNotEmpty ? 'o:$optionId' : 'p:$optionPosId';
  if (optionId.isEmpty && optionPosId.isEmpty) {
    logger.w('[카탈로그] 옵션 식별자 없음 — 스킵 (그룹 $groupPosId)');
    return;
  }

  final price = (option['salePrice'] as num?)?.toInt() ?? 0;
  final status = productStatusFromAppFit(option['status']?.toString() ?? '');

  final existing = accumulated[key];
  if (existing != null) {
    existing.record(price: price, status: status, groupPosId: groupPosId);
    return;
  }

  accumulated[key] = _OptionAccumulator(
    // displayOrder 는 dedupe 가 끝난 뒤 등장 순서로 다시 매긴다.
    product: ProductModel(
      productId: optionPosId, // prdId 용 (POS ID)
      internalId: optionId, // API 용 (UUID)
      // 신규 응답의 옵션명 키는 `name` 이다(구 응답의 `optionName` 아님).
      productName: option['name']?.toString() ?? '',
      categoryName: kOptionBucketCategoryName,
      categoryCode: groupPosId,
      menuPrice: price,
      status: status,
      type: ProductType.option,
      displayOrder: 0,
    ),
    price: price,
    status: status,
    groupPosId: groupPosId,
  );
}

/// 같은 옵션이 그룹마다 다른 값으로 등장했는지 한 줄로 요약한다.
///
/// "가격이 다르게 보인다" 문의가 들어왔을 때 첫 등장 값을 쓰고 있다는 근거가
/// 되는 유일한 관측 지점이다.
void _logDivergence(Iterable<_OptionAccumulator> options) {
  final conflicts = <String>[];
  for (final o in options) {
    final parts = <String>[
      if (o.prices.length > 1) '가격 ${(o.prices.toList()..sort()).join('/')}',
      if (o.statuses.length > 1)
        '상태 ${o.statuses.map((s) => s.code).join('/')}',
      if (o.groupPosIds.length > 1) '그룹 ${o.groupPosIds.join('/')}',
    ];
    if (parts.isNotEmpty) {
      conflicts.add('${o.product.productName}(${parts.join(', ')})');
    }
  }
  if (conflicts.isEmpty) return;
  logger.w('[카탈로그] 옵션이 그룹마다 다른 값으로 등장 ${conflicts.length}건 — '
      '첫 등장 값을 유지: ${conflicts.join(', ')}');
}

/// 옵션 dedupe 중간 상태.
class _OptionAccumulator {
  _OptionAccumulator({
    required this.product,
    required int price,
    required ProductStatus status,
    required String groupPosId,
  })  : prices = {price},
        statuses = {status},
        groupPosIds = {groupPosId};

  /// 첫 등장 옵션(정본).
  final ProductModel product;

  final Set<int> prices;
  final Set<ProductStatus> statuses;
  final Set<String> groupPosIds;

  void record({
    required int price,
    required ProductStatus status,
    required String groupPosId,
  }) {
    prices.add(price);
    statuses.add(status);
    groupPosIds.add(groupPosId);
  }
}
