import 'package:appfit_order_agent/models/product_model.dart';

/// 상품관리 화면의 카드 1장 = 동일 `productName` + [ProductType] 상품들의 묶음.
///
/// **왜 필요한가**: 이름은 같은데 가격만 다른 레코드가 여러 개 존재한다(주로 옵션.
/// 예: '샷 추가' 500/700/1000원이 별개 레코드). 점주가 하나씩 품절 처리하다
/// 누락하는 사고를 막기 위한 **표시·조작 단위**다.
///
/// 이 타입은 서버 스키마가 아니라 화면 파생물이라 `fromJson`/`toJson` 이 없다.
/// [ProductModel] 목록을 소비하는 다른 경로(출력·라벨·로컬서버)의 계약을 건드리지
/// 않도록 UI 계층에서만 만들어 쓴다.
///
/// 그룹은 all-or-nothing 이 정책 전제라 [status] 는 **전원 품절일 때만** 품절이다.
/// hidden 상품은 그룹에 넣지 않는다 — 생성 전에 걸러야 한다
/// (`visibleProducts` 가 담당).
class ProductGroup {
  /// 그룹 표시명 (= 그룹 키의 이름 성분, `trim()` 적용).
  final String name;

  /// ITEM/OPTION. 상태 변경 엔드포인트가 타입별로 갈리는데, 그룹이 **단일 타입**
  /// 임이 보장되므로 일괄 변경을 PUT 1회로 끝낼 수 있다. 이 전제가 깨지면
  /// itemIds/optionIds 를 한 요청에 섞어 보내게 된다.
  final ProductType type;

  /// `internalId` 기준 중복 제거된 멤버. 같은 상품이 여러 카테고리에 등록되면
  /// 카탈로그 파싱 단계에서 카테고리 수만큼 복제되므로 여기서 1건으로 접는다.
  final List<ProductModel> members;

  /// 멤버가 등장한 **모든** 카테고리명 (등장 순서 보존).
  /// 중복 제거 이전에 수집해야 "여러 카테고리에 함께 등록" 정보가 유실되지 않는다.
  final List<String> categoryNames;

  /// 오름차순 고유 가격. 길이 1이면 단일가격 카드, 2 이상이면 범위 표시.
  final List<int> prices;

  const ProductGroup({
    required this.name,
    required this.type,
    required this.members,
    required this.categoryNames,
    required this.prices,
  });

  /// 위젯 `ValueKey`·로그용. 상품명에 나올 수 없는 제어문자로 구분해 키 충돌을 막는다.
  String get key => '${type.code}\u0001$name';

  int get minPrice => prices.first;
  int get maxPrice => prices.last;

  /// 고유 가격이 2종 이상 — 카드에 "min ~ max" 를 표시할지 판단.
  /// 멤버가 2개여도 가격이 같으면 false(기존과 동일한 단일가격 표기 유지).
  bool get hasPriceRange => prices.length > 1;

  int get memberCount => members.length;

  /// 그룹 상태 — **전원 soldOut 일 때만** 품절. 그 외(일부만 품절 포함)는 판매중.
  ///
  /// 품절이면 그룹 전원이 품절이어야 한다는 것이 운영 정책이라, 일부만 품절인
  /// 상태는 정상 상태가 아니라 정합성이 깨진 상태로 본다. 그런 그룹을 판매중으로
  /// 보여야 '전체 품절' 조작으로 다시 정합을 맞출 수 있다.
  ProductStatus get status => members.isNotEmpty &&
          members.every((m) => m.status == ProductStatus.soldOut)
      ? ProductStatus.soldOut
      : ProductStatus.sale;

  bool get isSoldOut => status == ProductStatus.soldOut;

  /// 멤버 상태가 갈린 상태. 표시에는 쓰지 않지만(정책상 '일부 품절' 배지 없음)
  /// 무의미한 no-op API 호출 차단과 로그에 쓴다.
  bool get isMixed {
    if (members.length < 2) return false;
    final first = members.first.status;
    return members.any((m) => m.status != first);
  }

  /// 상태 변경 API 가 쓰는 플랫폼 UUID 목록(`shopItemId`/`optionId`).
  /// POS ID(`productId`)가 아니다. 빈 값은 서버가 거부하므로 제외한다.
  List<String> get internalIds =>
      members.map((m) => m.internalId).where((id) => id.isNotEmpty).toList();

  /// 전체/품절 탭 정렬 기준 — 멤버 중 최소 `displayOrder`.
  int get displayOrder =>
      members.map((m) => m.displayOrder).reduce((a, b) => a < b ? a : b);

  /// 카테고리 탭 정렬 기준 — **그 카테고리 안에서의** 최소 `displayOrder`.
  ///
  /// 같은 상품이 카테고리마다 다른 displayOrder 를 갖기 때문에, 전역 최소값으로
  /// 정렬하면 카테고리 탭의 기존 진열 순서가 어긋난다.
  int displayOrderIn(String categoryName) {
    int? found;
    for (final m in members) {
      if (m.categoryName != categoryName) continue;
      if (found == null || m.displayOrder < found) found = m.displayOrder;
    }
    return found ?? displayOrder;
  }

  @override
  String toString() =>
      'ProductGroup($name/${type.code}, 멤버 ${members.length}, 가격 $prices, $status)';
}
