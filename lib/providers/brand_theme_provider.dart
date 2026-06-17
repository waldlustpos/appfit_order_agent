import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:appfit_order_agent/constants/app_styles.dart';
import 'package:appfit_order_agent/constants/brand_theme.dart';
import 'package:appfit_order_agent/providers/preference_provider.dart';
import 'package:appfit_order_agent/utils/brand_registry.dart';
import 'package:appfit_order_agent/utils/logger.dart';

part 'brand_theme_provider.g.dart';

/// 현재 세션의 활성 브랜드 테마.
///
/// 부팅 시 [AppStyles.applyBrand]로 정적 색상 값이 이미 고정된 상태이며,
/// [selectTheme] 호출은 PreferenceService 에만 저장한다(UI 즉시 반영 X).
/// 실제 색상 교체는 앱 재시작 이후 main() 의 applyBrand 로 이뤄진다.
@Riverpod(keepAlive: true)
class BrandThemeNotifier extends _$BrandThemeNotifier {
  @override
  BrandTheme build() => AppStyles.activeBrand;

  Future<void> selectTheme(BrandTheme theme) async {
    await ref.read(preferenceServiceProvider).setBrandThemeId(theme.id);
    state = theme;
    logger.i('[BrandThemeNotifier] 테마 선택 저장: ${theme.id}');
  }

  /// 로그인 매장이 바뀌어 저장된 테마가 새 브랜드와 호환되지 않으면(= 이전 브랜드
  /// 전용 테마가 남은 경우) 기본 테마로 되돌린다.
  ///
  /// 호환 = 기본 테마이거나 그 브랜드의 고유 테마([BrandMeta.selectableThemes]).
  /// 로그아웃→다른 브랜드 로그인 시 이전 브랜드 색상이 새 매장에 남는 것을 방지.
  /// 같은 브랜드 재로그인/호환 테마면 no-op(저장 쓰기 없음).
  ///
  /// 색상의 실제 화면 반영은 다음 앱 시작의 [AppStyles.applyBrand] 시점이다
  /// (테마 변경은 재시작 기반 — main() 이 부팅 시 1회 적용). 여기서는 저장값과
  /// 노티파이어 state(설정 picker 선택 표시)만 즉시 일관되게 맞춘다.
  Future<void> reconcileForStore(String? storeId) async {
    final prefs = ref.read(preferenceServiceProvider);
    final brand = BrandRegistry.resolveOrNull(storeId);
    final saved = BrandTheme.fromId(prefs.getBrandThemeId());
    final allowed = brand?.selectableThemes ?? const [BrandTheme.appfitDefault];
    if (allowed.contains(saved)) return;

    await prefs.setBrandThemeId(BrandTheme.appfitDefault.id);
    state = BrandTheme.appfitDefault;
    logger.i('[BrandThemeNotifier] 브랜드 전환 — 테마 기본값으로 리셋 '
        '(store=$storeId, prev=${saved.id})');
  }
}
