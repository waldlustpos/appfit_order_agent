import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:appfit_order_agent/constants/app_styles.dart';
import 'package:appfit_order_agent/constants/brand_theme.dart';
import 'package:appfit_order_agent/providers/preference_provider.dart';
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
}
