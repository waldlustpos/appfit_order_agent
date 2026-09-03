// 라벨 출력 정책 — "무엇을 인쇄하고, 무엇을 서브정보로 올릴 것인가".
//
// 종전에는 이 두 판정이 `TpcpLabelFilterStrategy` 안에 TPCP 매장의 POS 코드
// (TKP1006 = 와플, TKP012/001~003/004… = 원두/온도/사이즈)로 하드코딩돼 있었고,
// `BrandFeature.labelCategoryFilter` 를 가진 브랜드에서만 동작했다. 이제는 매장이
// 설정 화면에서 직접 고른 값이 정본이므로 전략 다형성이 필요 없다 — 값 객체 하나로
// 대체한다.
//
// 두 축은 서로 독립이다.
//  - 카테고리 필터: 이 기기의 라벨 프린터가 어느 카테고리 상품을 인쇄할지.
//  - 서브정보(subInfo): 라벨 상단에 어느 옵션 그룹의 선택값을 올릴지. 순서까지.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:appfit_order_agent/models/menu_option_model.dart';
import 'package:appfit_order_agent/models/order_menu_model.dart';
import 'package:appfit_order_agent/models/product_model.dart';
import 'package:appfit_order_agent/providers/preference_provider.dart';

/// 라벨 서브정보에 올릴 수 있는 최대 항목 수.
///
/// 상한의 실제 근거는 58mm 연속용지 레이아웃이다 — `Continuous58LabelPainter`
/// 의 서브정보 바는 콘텐츠 폭 전체를 쓰는 검정 바에 `maxLines: 1` 이라 넘치면
/// 조용히 잘린다. 갭 라벨(`LabelPainter`)도 줄바꿈/축소가 없어 좌측으로 흘러
/// 인접 요소를 침범한다.
const int kLabelSubInfoMaxCount = 3;

/// 카테고리 매칭 키.
///
/// POS 코드가 정본이지만 서버가 `categoryPosId` 를 안 주면 빈 문자열이 된다
/// ([ShopCategoryModel.categoryCode]). 그 경우까지 선택 불가로 두면 해당 매장은
/// 필터가 통째로 무력해지므로 이름으로 폴백한다. **선택 화면과 판정 로직이 반드시
/// 이 함수 하나를 공유해야** 저장된 키와 조회 키가 어긋나지 않는다.
String labelCategoryKeyOf(String code, String name) =>
    code.isNotEmpty ? 'c:$code' : 'n:$name';

/// 주문 메뉴/옵션 → 상품 카탈로그 조회 인덱스.
///
/// 주문 응답에는 카테고리가 없어([OrderMenuModel] 에 categoryCode 필드가 없다)
/// 카탈로그와 조인해야 하는데, 종전 구현은 메뉴마다 상품 목록을 선형 탐색했다.
/// 주문당 한 번만 만들어 재사용한다.
///
/// **같은 id 로 여러 상품이 잡힐 수 있다** — 한 상품이 여러 카테고리에 등록되면
/// 카탈로그에 사본이 여러 개 존재한다. 첫 매치만 보면 판정이 응답 배열 순서에
/// 좌우되므로 사본 전부를 들고 있는다.
class LabelProductIndex {
  LabelProductIndex._(this._byId);

  final Map<String, List<ProductModel>> _byId;

  static final LabelProductIndex empty = LabelProductIndex._(const {});

  factory LabelProductIndex.build(List<ProductModel> products) {
    if (products.isEmpty) return empty;
    final byId = <String, List<ProductModel>>{};
    void put(String id, ProductModel p) {
      if (id.isEmpty) return;
      (byId[id] ??= <ProductModel>[]).add(p);
    }

    for (final p in products) {
      // 주문의 shopItemId 는 플랫폼 UUID(internalId)로도, POS 코드(productId)로도
      // 들어온다. 종전 `_findProduct` 와 같은 느슨한 OR 매칭을 유지한다.
      put(p.productId, p);
      put(p.internalId, p);
    }
    return LabelProductIndex._(byId);
  }

  List<ProductModel> lookup(String id) => _byId[id] ?? const [];

  bool get isEmpty => _byId.isEmpty;
}

/// 라벨 한 장의 서브정보 추출 결과.
class LabelSubInfoResult {
  const LabelSubInfoResult({
    this.values = const [],
    this.consumed = const {},
  });

  /// 인쇄할 서브정보 문자열 — **설정에서 고른 그룹 순서 그대로**.
  final List<String> values;

  /// 서브정보로 소비된 옵션들. 라벨 하단 옵션 목록에서 제외할 때 **이름 문자열이
  /// 아니라 이 집합으로 걸러야** 동명 옵션이 함께 빠지는 오제외를 피한다.
  final Set<MenuOptionModel> consumed;

  static const LabelSubInfoResult none = LabelSubInfoResult();
}

/// 매장이 설정 화면에서 지정한 라벨 출력 정책.
class LabelOutputPolicy {
  const LabelOutputPolicy({
    this.categoryFilterEnabled = false,
    this.categoryKeys = const {},
    this.subInfoGroupCodes = const [],
  });

  /// 아무것도 지정하지 않은 상태 = 전량 인쇄 + 서브정보 없음.
  static const LabelOutputPolicy disabled = LabelOutputPolicy();

  /// 카테고리 지정 ON/OFF. OFF 면 모든 카테고리가 출력 대상.
  final bool categoryFilterEnabled;

  /// 출력 대상 카테고리 키([labelCategoryKeyOf]). 순서에 의미 없음.
  final Set<String> categoryKeys;

  /// 서브정보로 올릴 옵션그룹 POS 코드 — **순서 = 인쇄 순서**.
  final List<String> subInfoGroupCodes;

  /// 필터가 실제로 무언가를 걸러내는 상태인가.
  ///
  /// ON 인데 선택이 0개면 **전량 인쇄**다. "전체 선택"과 "전체 해제"가 같은 결과가
  /// 되는 건 의도적이다 — 라벨을 아예 안 내는 것은 라벨 프린터 사용 스위치를 OFF
  /// 하는 쪽이 맞고, 설정 실수로 매장의 라벨이 통째로 멈추는 사고를 막는다.
  bool get isCategoryFilterActive =>
      categoryFilterEnabled && categoryKeys.isNotEmpty;

  /// 이 메뉴를 라벨로 인쇄할 것인가.
  ///
  /// **fail-open** — 카탈로그가 비었거나(조회 실패 시 `shopCatalogProvider` 는
  /// 예외 대신 빈 목록을 반환한다) 주문 상품이 카탈로그에 없으면 인쇄한다.
  /// "매칭 실패 = 스킵"으로 짜면 카탈로그 조회 한 번 실패에 매장 라벨이 통째로
  /// 사라진다. 안 나오는 것보다 더 나오는 편이 복구 가능하다.
  bool shouldPrintMenu(OrderMenuModel menu, LabelProductIndex index) {
    if (!isCategoryFilterActive) return true;
    if (index.isEmpty) return true;

    final matches = index.lookup(menu.shopItemId);
    if (matches.isEmpty) return true;

    // any-match: 사본 중 하나라도 선택된 카테고리면 인쇄한다.
    for (final p in matches) {
      if (categoryKeys
          .contains(labelCategoryKeyOf(p.categoryCode, p.categoryName))) {
        return true;
      }
    }
    return false;
  }

  /// 메뉴 옵션에서 서브정보를 뽑는다. 반환 순서는 [subInfoGroupCodes] 순서.
  LabelSubInfoResult buildSubInfo(
    OrderMenuModel menu,
    LabelProductIndex index,
  ) {
    if (subInfoGroupCodes.isEmpty || menu.options.isEmpty) {
      return LabelSubInfoResult.none;
    }

    // 그룹코드 → 그 그룹의 첫 옵션. 같은 그룹의 옵션이 여러 개 선택된 주문에서는
    // **첫 값을 유지**한다(종전 구현은 마지막 값이 덮어썼다 — 같은 주문을 두 번
    // 봐도 같은 라벨이 나오도록 첫 값으로 고정).
    final picked = <String, MenuOptionModel>{};
    for (final opt in menu.options) {
      final code = _groupCodeOf(opt, index);
      if (code == null || code.isEmpty) continue;
      if (!subInfoGroupCodes.contains(code)) continue;
      picked.putIfAbsent(code, () => opt);
    }
    if (picked.isEmpty) return LabelSubInfoResult.none;

    final values = <String>[];
    final consumed = <MenuOptionModel>{};
    for (final code in subInfoGroupCodes) {
      final opt = picked[code];
      if (opt == null) continue;
      if (opt.optionName.isEmpty) continue;
      values.add(opt.optionName);
      consumed.add(opt);
      if (values.length >= kLabelSubInfoMaxCount) break;
    }
    if (values.isEmpty) return LabelSubInfoResult.none;
    return LabelSubInfoResult(values: values, consumed: consumed);
  }

  /// 옵션의 소속 그룹 POS 코드.
  ///
  /// 정본은 주문 응답에 실려오는 옵션 그룹(v1). 서버가 상품 경로로 옵션 카테고리를
  /// 더 이상 내려주지 않으므로 이 쪽이 우선이다. 값이 없으면(v0 응답 등) 기존
  /// 상품마스터 조인으로 폴백해 종전 동작을 보존한다.
  String? _groupCodeOf(MenuOptionModel opt, LabelProductIndex index) {
    final groupCode = opt.optionGroupPosId;
    if (groupCode != null && groupCode.isNotEmpty) return groupCode;
    final matches = index.lookup(opt.shopOptionId);
    for (final p in matches) {
      if (p.categoryCode.isNotEmpty) return p.categoryCode;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LabelOutputPolicy &&
          other.categoryFilterEnabled == categoryFilterEnabled &&
          _setEquals(other.categoryKeys, categoryKeys) &&
          _listEquals(other.subInfoGroupCodes, subInfoGroupCodes);

  @override
  int get hashCode => Object.hash(
        categoryFilterEnabled,
        Object.hashAllUnordered(categoryKeys),
        Object.hashAll(subInfoGroupCodes),
      );

  @override
  String toString() => 'LabelOutputPolicy(filter: $categoryFilterEnabled, '
      'categories: ${categoryKeys.length}, subInfo: $subInfoGroupCodes)';
}

bool _setEquals(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);

bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// 현재 매장의 라벨 출력 정책.
///
/// SharedPreferences 는 변경 알림이 없으므로 **설정을 저장한 화면이
/// `ref.invalidate(labelOutputPolicyProvider)` 를 호출하는 것이 계약**이다.
final labelOutputPolicyProvider = Provider<LabelOutputPolicy>((ref) {
  final prefs = ref.watch(preferenceServiceProvider);
  return LabelOutputPolicy(
    categoryFilterEnabled: prefs.getLabelCategoryFilterOn(),
    categoryKeys: prefs.getLabelCategoryKeys(),
    subInfoGroupCodes: prefs.getLabelSubInfoGroups(),
  );
});
