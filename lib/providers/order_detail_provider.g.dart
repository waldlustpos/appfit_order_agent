// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'order_detail_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$orderDetailHash() => r'75576145ead113ad125face95967577a7b26d2c1';

/// See also [OrderDetail].
@ProviderFor(OrderDetail)
final orderDetailProvider = AutoDisposeNotifierProvider<
    OrderDetail,
    ({
      OrderModel? order,
      bool isLoading,
      String? errorMessage,
      String? loadingActionId
    })>.internal(
  OrderDetail.new,
  name: r'orderDetailProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$orderDetailHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$OrderDetail = AutoDisposeNotifier<
    ({
      OrderModel? order,
      bool isLoading,
      String? errorMessage,
      String? loadingActionId
    })>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
