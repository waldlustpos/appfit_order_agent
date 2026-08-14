import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:appfit_order_agent/constants/order_constants.dart';
import 'package:appfit_order_agent/models/menu_option_model.dart';
import 'package:appfit_order_agent/models/order_menu_model.dart';
import 'package:appfit_order_agent/models/order_model.dart';
import 'package:appfit_order_agent/models/product_model.dart';
import 'package:appfit_order_agent/providers/brand_provider.dart';
import 'package:appfit_order_agent/services/label_printer/label_target.dart';
import 'package:appfit_order_agent/utils/brand_registry.dart';

/// 라벨 한 장의 sub-info 영역에 들어가는 옵션 카테고리 분류 결과.
///
/// 분류 룰이 없는 브랜드는 [none] (모두 null).
class LabelOptionCategories {
  const LabelOptionCategories({
    this.beanType,
    this.temperature,
    this.sizeOption,
    this.classified = const {},
  });

  final String? beanType;
  final String? temperature;
  final String? sizeOption;

  /// sub-info 로 소비된 옵션들. 하단 옵션 목록에서 제외할 때 **이름 문자열이 아니라
  /// 이 집합으로 걸러야** 동명 옵션이 함께 빠지는 오제외를 피할 수 있다.
  final Set<MenuOptionModel> classified;

  static const LabelOptionCategories none = LabelOptionCategories();
}

/// 브랜드별 라벨 필터/분류 동작을 캡슐화하는 전략(파이프라인 변환).
///
/// 게이팅(어느 브랜드가 필터를 쓰는지)은 [labelFilterStrategyProvider] 가
/// capability([BrandFeature.labelCategoryFilter])로 결정한다. 전략 자체는
/// "무엇을 인쇄하고 어떻게 분류하는가"라는 동작만 담는다.
abstract class LabelFilterStrategy {
  const LabelFilterStrategy();

  /// 인쇄 대상 메뉴 선별. 기본 구현은 전체 메뉴.
  List<OrderMenuModel> selectMenus(
    OrderModel order, {
    required List<ProductModel> products,
    required int filterMode,
    required bool isReprint,
  });

  /// 메뉴 옵션을 sub-info(원두/온도/사이즈)로 분류. 기본 구현은 분류 없음.
  LabelOptionCategories classifyOptions(
    OrderMenuModel menu, {
    required List<ProductModel> products,
  });

  /// 이 메뉴의 라벨이 어느 프린터(= 제조 구역)로 갈지.
  ///
  /// 기본 구현은 **상품 카테고리 코드를 [policy] 배정표에 조회**한다. 브랜드
  /// 하드코딩이 아니라 매장 설정이 정본이므로 필터 전략과 무관하게 모든 브랜드에서
  /// 동작한다 — [selectMenus] 처럼 capability 로 게이팅하지 않는다.
  ///
  /// ## [isFastMenu] 는 판정 결과만 받는다
  /// 빠른 메뉴인지 아닌지는 [FastMenuPolicy] 가 정하고 여기는 그 결과만 쓴다.
  /// 배정표를 두 축(카테고리·빠른메뉴) 모두 들고 있는 것은 [policy] 이므로
  /// 우선순위 판단도 거기서 한다([LabelTargetPolicy.resolveTarget]) — 이 메서드는
  /// "무엇을 조회 키로 줄 것인가" 만 안다.
  ///
  /// ## [selectMenus] 와의 관계 — 직교하는 두 축이다
  /// [selectMenus] 는 **인쇄 여부**(이 라벨을 뽑을 것인가), 여기는 **행선지**
  /// (어느 프린터로 보낼 것인가)를 정한다. 재출력(`isReprint`)이 필터를 우회해도
  /// 행선지는 그대로 유지돼야 하므로 이 메서드는 `isReprint` 를 보지 않는다.
  ///
  /// ## 메뉴 하나당 정확히 하나
  /// 반환이 단일 값이라 "한 메뉴가 두 프린터에 배정" 이 **구조적으로 불가능**하다.
  /// 필터 모드를 두 번 돌려 나누는 방식(프린터A=와플만 / 프린터B=와플제외)을 쓰면
  /// 안 되는 이유가 이것이다 — [TpcpLabelFilterStrategy.selectMenus] 의 세트 상품은
  /// 두 모드 모두에서 true 라 양쪽에 중복 인쇄된다.
  LabelTarget assignTarget(
    OrderMenuModel menu, {
    required List<ProductModel> products,
    required LabelTargetPolicy policy,
    bool isFastMenu = false,
  }) =>
      policy.resolveTarget(
        isFastMenu: isFastMenu,
        categoryCode: findProduct(products, menu.shopItemId)?.categoryCode,
      );

  /// 상품 카탈로그에서 ID 로 상품을 찾는다.
  ///
  /// `productId` 와 `internalId` 를 **둘 다** 보는 이유: 주문 응답의
  /// [OrderMenuModel.shopItemId] / [MenuOptionModel.shopOptionId] 가 둘 중
  /// 어느 쪽으로도 올 수 있다.
  ProductModel? findProduct(List<ProductModel> products, String id) {
    for (final p in products) {
      if (p.productId == id || p.internalId == id) return p;
    }
    return null;
  }
}

/// 필터/분류를 하지 않는 기본 전략 (TPCP 외 모든 브랜드).
///
/// 기존 kokonut 등의 "단순 평면화" 동작을 보존한다.
class NoOpLabelFilterStrategy extends LabelFilterStrategy {
  const NoOpLabelFilterStrategy();

  @override
  List<OrderMenuModel> selectMenus(
    OrderModel order, {
    required List<ProductModel> products,
    required int filterMode,
    required bool isReprint,
  }) =>
      order.menus;

  @override
  LabelOptionCategories classifyOptions(
    OrderMenuModel menu, {
    required List<ProductModel> products,
  }) =>
      LabelOptionCategories.none;
}

/// TPCP(tokyoplatz) 전용 라벨 필터/분류 전략.
///
/// - 카테고리 필터: filterMode 0=전체, 1=와플만, 2=와플제외. 세트 상품은 항상 포함.
/// - 옵션 분류: 원두/온도/사이즈 카테고리 코드를 sub-info 로 추출.
/// 와플/세트/옵션 카테고리 코드는 [OrderCategoryCodes] 참조.
class TpcpLabelFilterStrategy extends LabelFilterStrategy {
  const TpcpLabelFilterStrategy();

  @override
  List<OrderMenuModel> selectMenus(
    OrderModel order, {
    required List<ProductModel> products,
    required int filterMode,
    required bool isReprint,
  }) {
    // 재출력은 항상 전체 인쇄, filterMode 0 도 전체.
    if (isReprint || filterMode == 0) return order.menus;

    return order.menus.where((menu) {
      final product = findProduct(products, menu.shopItemId);
      // 세트 상품(TKP0051/52)은 필터 모드 무관 항상 출력.
      if (product != null &&
          OrderCategoryCodes.setItemCodes.contains(product.productId)) {
        return true;
      }
      final isWaffle = OrderCategoryCodes.waffleCategoryCodes
          .contains(product?.categoryCode);
      return filterMode == 1 ? isWaffle : !isWaffle;
    }).toList();
  }

  @override
  LabelOptionCategories classifyOptions(
    OrderMenuModel menu, {
    required List<ProductModel> products,
  }) {
    String? beanType;
    String? temperature;
    String? sizeOption;
    final classified = <MenuOptionModel>{};
    for (final opt in menu.options) {
      // 정본은 주문 응답에 실려오는 옵션 그룹(v1). 서버가 상품 경로로 옵션
      // 카테고리를 더 이상 내려주지 않으므로 이 쪽이 우선이다. 값이 없으면
      // (v0 응답 등) 기존 상품마스터 조인으로 폴백해 종전 동작을 보존한다.
      final groupCode = opt.optionGroupPosId;
      final categoryCode = (groupCode != null && groupCode.isNotEmpty)
          ? groupCode
          : findProduct(products, opt.shopOptionId)?.categoryCode;
      if (categoryCode == null) continue;
      if (OrderCategoryCodes.beanTypeCodes.contains(categoryCode)) {
        beanType = opt.optionName;
        classified.add(opt);
      } else if (OrderCategoryCodes.temperatureCodes.contains(categoryCode)) {
        temperature = opt.optionName;
        classified.add(opt);
      } else if (OrderCategoryCodes.sizeOptionCodes.contains(categoryCode)) {
        sizeOption = opt.optionName;
        classified.add(opt);
      }
    }
    return LabelOptionCategories(
      beanType: beanType,
      temperature: temperature,
      sizeOption: sizeOption,
      classified: classified,
    );
  }
}

/// 현재 브랜드에 맞는 [LabelFilterStrategy] 를 제공한다.
///
/// capability [BrandFeature.labelCategoryFilter] 를 가진 브랜드만
/// [TpcpLabelFilterStrategy], 그 외는 [NoOpLabelFilterStrategy].
final labelFilterStrategyProvider = Provider<LabelFilterStrategy>((ref) {
  final brand = ref.watch(currentBrandProvider);
  return (brand?.has(BrandFeature.labelCategoryFilter) ?? false)
      ? const TpcpLabelFilterStrategy()
      : const NoOpLabelFilterStrategy();
});
