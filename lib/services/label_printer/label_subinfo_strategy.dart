// 라벨 sub-info 영역(라벨 위쪽 강조 줄)에 무엇을 올릴지 정하는 브랜드 전략.
//
// **이 축만 브랜드 하드코딩으로 남는다.** 같은 클래스에 있던 "어느 상품을 인쇄할
// 것인가"(카테고리 필터)는 2026-09 에 매장 설정(`LabelOutputPolicy`)으로 빠져나갔다.
// sub-info 는 그러지 않았는데, 매장이 옵션 그룹을 직접 고르게 해 보니 ① 점주가
// 골라야 하는 조작 부담이 크고 ② 그룹 이름·구성이 매장마다 제각각이라 화면만 보고
// 무엇을 골라야 할지 알기 어려웠다. 라벨에 무엇을 크게 찍을지는 매장 취향보다
// 브랜드 운영 정책에 가깝다는 판단.
//
// 게이팅(어느 브랜드가 sub-info 를 쓰는지)은 [labelSubInfoStrategyProvider] 가
// capability([BrandFeature.labelSubInfo])로 결정한다. 전략 자체는 "무엇을 어떻게
// 분류하는가"라는 동작만 담는다.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:appfit_order_agent/constants/order_constants.dart';
import 'package:appfit_order_agent/models/menu_option_model.dart';
import 'package:appfit_order_agent/models/order_menu_model.dart';
import 'package:appfit_order_agent/models/product_model.dart';
import 'package:appfit_order_agent/providers/brand_provider.dart';
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

/// 브랜드별 라벨 sub-info 분류 동작.
abstract class LabelSubInfoStrategy {
  const LabelSubInfoStrategy();

  /// 메뉴 옵션을 sub-info(원두/온도/사이즈)로 분류. 기본 구현은 분류 없음.
  LabelOptionCategories classifyOptions(
    OrderMenuModel menu, {
    required List<ProductModel> products,
  });
}

/// 분류를 하지 않는 기본 전략 (TPCP 외 모든 브랜드).
///
/// sub-info 영역은 비어 나가고, 모든 옵션이 라벨 하단 옵션 목록에 남는다.
class NoOpLabelSubInfoStrategy extends LabelSubInfoStrategy {
  const NoOpLabelSubInfoStrategy();

  @override
  LabelOptionCategories classifyOptions(
    OrderMenuModel menu, {
    required List<ProductModel> products,
  }) =>
      LabelOptionCategories.none;
}

/// TPCP(tokyoplatz) 전용 sub-info 분류 전략.
///
/// 원두/온도/사이즈 옵션그룹 코드를 뽑아 sub-info 로 올린다.
/// 코드 목록은 [OrderCategoryCodes] 참조.
class TpcpLabelSubInfoStrategy extends LabelSubInfoStrategy {
  const TpcpLabelSubInfoStrategy();

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
          : _findProduct(products, opt.shopOptionId)?.categoryCode;
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

  ProductModel? _findProduct(List<ProductModel> products, String id) {
    for (final p in products) {
      if (p.productId == id || p.internalId == id) return p;
    }
    return null;
  }
}

/// 현재 브랜드에 맞는 [LabelSubInfoStrategy] 를 제공한다.
///
/// capability [BrandFeature.labelSubInfo] 를 가진 브랜드만
/// [TpcpLabelSubInfoStrategy], 그 외는 [NoOpLabelSubInfoStrategy].
final labelSubInfoStrategyProvider = Provider<LabelSubInfoStrategy>((ref) {
  final brand = ref.watch(currentBrandProvider);
  return (brand?.has(BrandFeature.labelSubInfo) ?? false)
      ? const TpcpLabelSubInfoStrategy()
      : const NoOpLabelSubInfoStrategy();
});
