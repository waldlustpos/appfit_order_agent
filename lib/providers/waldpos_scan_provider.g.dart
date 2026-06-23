// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'waldpos_scan_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$waldposScanServiceHash() =>
    r'e8f2dd7d4d2f928b12ba11c4cd92735cdae81a5c';

/// 서비스 Provider. UI 는 이 provider 를 통해서만 서비스에 접근한다.
///
/// Copied from [waldposScanService].
@ProviderFor(waldposScanService)
final waldposScanServiceProvider = Provider<WaldposScanService>.internal(
  waldposScanService,
  name: r'waldposScanServiceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$waldposScanServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef WaldposScanServiceRef = ProviderRef<WaldposScanService>;
String _$waldposScanHash() => r'a2484fbb292bab9b2e785bcd36b50a1dd4df3c31';

/// 스캔 트리거 + 진행상태 Notifier.
///
/// Copied from [WaldposScan].
@ProviderFor(WaldposScan)
final waldposScanProvider =
    AutoDisposeNotifierProvider<WaldposScan, WaldposScanState>.internal(
  WaldposScan.new,
  name: r'waldposScanProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$waldposScanHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$WaldposScan = AutoDisposeNotifier<WaldposScanState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
