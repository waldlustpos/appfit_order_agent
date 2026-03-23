// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'kds_unified_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$kdsCurrentSortDirectionHash() =>
    r'b89350e3227e65eb792e30713d5499c9b6a83944';

/// 현재 활성 탭의 정렬 방향 (계산된 값)
///
/// Copied from [kdsCurrentSortDirection].
@ProviderFor(kdsCurrentSortDirection)
final kdsCurrentSortDirectionProvider =
    AutoDisposeProvider<OrderSortDirection>.internal(
  kdsCurrentSortDirection,
  name: r'kdsCurrentSortDirectionProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$kdsCurrentSortDirectionHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef KdsCurrentSortDirectionRef = AutoDisposeProviderRef<OrderSortDirection>;
String _$kdsModeHash() => r'b1c86b27cd18dad4f78cb836e0c72c4458030d9d';

/// KDS 모드 상태 관리 (기존 kdsProvider를 @riverpod로 변환)
///
/// Copied from [KdsMode].
@ProviderFor(KdsMode)
final kdsModeProvider = NotifierProvider<KdsMode, bool>.internal(
  KdsMode.new,
  name: r'kdsModeProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$kdsModeHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$KdsMode = Notifier<bool>;
String _$kdsTabIndexHash() => r'7d6c39c46ad57a72da75fc34f562b92e34149d1a';

/// KDS 탭 인덱스 관리 (기본값: 1 = 진행 탭)
///
/// Copied from [KdsTabIndex].
@ProviderFor(KdsTabIndex)
final kdsTabIndexProvider = NotifierProvider<KdsTabIndex, int>.internal(
  KdsTabIndex.new,
  name: r'kdsTabIndexProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$kdsTabIndexHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$KdsTabIndex = Notifier<int>;
String _$kdsSortDirectionHash() => r'7497bb98b5387c92940e8c49d22df425e8878759';

/// KDS 전용 정렬 방향 관리
///
/// Copied from [KdsSortDirection].
@ProviderFor(KdsSortDirection)
final kdsSortDirectionProvider =
    AutoDisposeNotifierProvider<KdsSortDirection, OrderSortDirection>.internal(
  KdsSortDirection.new,
  name: r'kdsSortDirectionProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$kdsSortDirectionHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$KdsSortDirection = AutoDisposeNotifier<OrderSortDirection>;
String _$kdsTabSortDirectionsHash() =>
    r'77e6d0aa75f3b9f20fc78d5ff4006533f99883ae';

/// 탭별 정렬 방향 통합 관리
///
/// Copied from [KdsTabSortDirections].
@ProviderFor(KdsTabSortDirections)
final kdsTabSortDirectionsProvider = NotifierProvider<KdsTabSortDirections,
    Map<int, OrderSortDirection>>.internal(
  KdsTabSortDirections.new,
  name: r'kdsTabSortDirectionsProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$kdsTabSortDirectionsHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$KdsTabSortDirections = Notifier<Map<int, OrderSortDirection>>;
String _$kdsScrollControllerMapHash() =>
    r'53d11386288e2081ccc15816c10bf3ff55d338f7';

/// 스크롤 컨트롤러 통합 관리
///
/// Copied from [KdsScrollControllerMap].
@ProviderFor(KdsScrollControllerMap)
final kdsScrollControllerMapProvider = NotifierProvider<KdsScrollControllerMap,
    Map<String, ScrollController>>.internal(
  KdsScrollControllerMap.new,
  name: r'kdsScrollControllerMapProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$kdsScrollControllerMapHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$KdsScrollControllerMap = Notifier<Map<String, ScrollController>>;
String _$kdsScrollButtonStatesHash() =>
    r'96379aead54cd56c877b6bbb25a14226314377e4';

/// 스크롤 버튼 상태 관리
///
/// Copied from [KdsScrollButtonStates].
@ProviderFor(KdsScrollButtonStates)
final kdsScrollButtonStatesProvider = AutoDisposeNotifierProvider<
    KdsScrollButtonStates, Map<String, ScrollButtonState>>.internal(
  KdsScrollButtonStates.new,
  name: r'kdsScrollButtonStatesProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$kdsScrollButtonStatesHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$KdsScrollButtonStates
    = AutoDisposeNotifier<Map<String, ScrollButtonState>>;
String _$kdsCheckedItemsHash() => r'b0a9e859dbaa76450aca487641beda9324428f85';

/// 체크된 아이템 상태 관리
///
/// Copied from [KdsCheckedItems].
@ProviderFor(KdsCheckedItems)
final kdsCheckedItemsProvider = AutoDisposeNotifierProvider<KdsCheckedItems,
    Map<String, Set<int>>>.internal(
  KdsCheckedItems.new,
  name: r'kdsCheckedItemsProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$kdsCheckedItemsHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$KdsCheckedItems = AutoDisposeNotifier<Map<String, Set<int>>>;
String _$kdsScrollPositionsHash() =>
    r'70677cdd645322b0b9b83c39e44bf879670d2a41';

/// 스크롤 위치 관리
///
/// Copied from [KdsScrollPositions].
@ProviderFor(KdsScrollPositions)
final kdsScrollPositionsProvider =
    NotifierProvider<KdsScrollPositions, Map<String, double>>.internal(
  KdsScrollPositions.new,
  name: r'kdsScrollPositionsProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$kdsScrollPositionsHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$KdsScrollPositions = Notifier<Map<String, double>>;
String _$kdsCardAnimationsHash() => r'23697b9932cb813da1f20b89fc0ee6b5b2816878';

/// 카드 애니메이션 상태 관리 (개선된 버전)
///
/// Copied from [KdsCardAnimations].
@ProviderFor(KdsCardAnimations)
final kdsCardAnimationsProvider = AutoDisposeNotifierProvider<KdsCardAnimations,
    Map<String, CardAnimationState>>.internal(
  KdsCardAnimations.new,
  name: r'kdsCardAnimationsProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$kdsCardAnimationsHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$KdsCardAnimations
    = AutoDisposeNotifier<Map<String, CardAnimationState>>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
