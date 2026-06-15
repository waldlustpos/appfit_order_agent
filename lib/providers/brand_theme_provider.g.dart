// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'brand_theme_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$brandThemeNotifierHash() =>
    r'9be900f24c64ccf124e9db9678f5344b2a56b026';

/// 현재 세션의 활성 브랜드 테마.
///
/// 부팅 시 [AppStyles.applyBrand]로 정적 색상 값이 이미 고정된 상태이며,
/// [selectTheme] 호출은 PreferenceService 에만 저장한다(UI 즉시 반영 X).
/// 실제 색상 교체는 앱 재시작 이후 main() 의 applyBrand 로 이뤄진다.
///
/// Copied from [BrandThemeNotifier].
@ProviderFor(BrandThemeNotifier)
final brandThemeNotifierProvider =
    NotifierProvider<BrandThemeNotifier, BrandTheme>.internal(
  BrandThemeNotifier.new,
  name: r'brandThemeNotifierProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$brandThemeNotifierHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$BrandThemeNotifier = Notifier<BrandTheme>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
