// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_health_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$apiHealthNotifierHash() => r'c5885893bdca5cbb9b8bdf18e7e0f78cbd9a2fc4';

/// HTTP 계층 건강도. [ApiService] 가 요청 결과마다 기록하고,
/// 복구 트리거(회복 시 즉시 재동기화)와 원격 관제가 구독한다.
/// 화면에 지연을 알리던 동기화 배너는 제거돼 UI 구독자는 없다.
///
/// 앱 전역 상태이므로 keepAlive. 화면 전환으로 리셋되면 안 된다.
///
/// Copied from [ApiHealthNotifier].
@ProviderFor(ApiHealthNotifier)
final apiHealthNotifierProvider =
    NotifierProvider<ApiHealthNotifier, ApiHealth>.internal(
  ApiHealthNotifier.new,
  name: r'apiHealthNotifierProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$apiHealthNotifierHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$ApiHealthNotifier = Notifier<ApiHealth>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
