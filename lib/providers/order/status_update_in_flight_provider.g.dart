// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'status_update_in_flight_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$statusUpdateInFlightHash() =>
    r'4a25225cfdc621d71c7684b03d756b83754495e8';

/// 주문별 상태변경(PUT) in-flight 집합.
///
/// 원래 `OrderNotifier` 의 private `Set<String>` 이었는데 provider 로 승격했다.
/// 이유(2026-08-08 에뮬레이터 실검증에서 발견된 버그): KDS 카드는
/// `isDetailLoaded`/`kdsOrderType` 에 따라 서브트리를 통째로 교체하므로, 진행
/// 중에 버튼 위젯의 State 가 재생성되면 로컬 busy 플래그가 리셋돼 재탭이
/// 관통했다. **UI 의 busy 표시가 State 수명과 무관하려면 진실이 위젯 밖에
/// 있어야 한다** — 그 진실이 이 provider 다.
///
/// - 쓰기: `OrderNotifier.updateOrderStatus` 만 (진입 [tryAcquire] / 종료 [release])
/// - 읽기: KDS 카드 버튼이 주문별 `contains` 를 select 해 `externalBusy` 로 사용
///
/// Copied from [StatusUpdateInFlight].
@ProviderFor(StatusUpdateInFlight)
final statusUpdateInFlightProvider =
    NotifierProvider<StatusUpdateInFlight, Set<String>>.internal(
  StatusUpdateInFlight.new,
  name: r'statusUpdateInFlightProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$statusUpdateInFlightHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$StatusUpdateInFlight = Notifier<Set<String>>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
