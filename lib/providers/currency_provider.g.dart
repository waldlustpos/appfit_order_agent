// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'currency_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$currencySymbolHash() => r'9d4099211d70843330df3236d08c44710b293530';

/// 현재 언어 + 화폐단위 설정에 따라 표시할 통화 기호 문자열을 반환합니다.
/// - KRW 선택 시: "원" (언어 무관)
/// - JPY 선택 시: 일본어 → "円", 그 외 → "¥"
///
/// Copied from [currencySymbol].
@ProviderFor(currencySymbol)
final currencySymbolProvider = Provider<String>.internal(
  currencySymbol,
  name: r'currencySymbolProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$currencySymbolHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef CurrencySymbolRef = ProviderRef<String>;
String _$currencyNotifierHash() => r'597207ac739b93be4febee351864a57f6aeef791';

/// See also [CurrencyNotifier].
@ProviderFor(CurrencyNotifier)
final currencyNotifierProvider =
    NotifierProvider<CurrencyNotifier, CurrencyUnit>.internal(
  CurrencyNotifier.new,
  name: r'currencyNotifierProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$currencyNotifierHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$CurrencyNotifier = Notifier<CurrencyUnit>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
