import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/order_model.dart';
import '../utils/kds_utils.dart' as kds_utils;
import 'kds_unified_providers.dart';
import 'order_history_provider.dart';
import 'order_provider.dart';

/// OrderStatusScreen 용 필터링+정렬 완료된 주문 목록.
/// build() 내에서 매번 연산하지 않고 provider 레벨에서 캐싱.
final orderStatusOrdersProvider = Provider<
    ({
      List<OrderModel> newOrders,
      List<OrderModel> confirmedOrders,
      List<OrderModel> pickupedOrders,
      List<OrderModel> completedOrders,
    })>((ref) {
  final orders = ref.watch(orderProvider.select((s) => s.orders));

  final newOrders = orders.where((o) => o.status == OrderStatus.NEW).toList()
    ..sort((a, b) => a.orderedAt.compareTo(b.orderedAt));

  final confirmedOrders = orders
      .where((o) => o.status == OrderStatus.PREPARING)
      .toList()
    ..sort((a, b) => a.orderedAt.compareTo(b.orderedAt));

  final pickupedOrders = orders
      .where((o) => o.status == OrderStatus.READY)
      .toList()
    ..sort((a, b) => a.orderedAt.compareTo(b.orderedAt));

  final completedOrders = orders
      .where((o) =>
          o.status == OrderStatus.DONE || o.status == OrderStatus.CANCELLED)
      .toList()
    ..sort((a, b) => b.orderedAt.compareTo(a.orderedAt));

  return (
    newOrders: newOrders,
    confirmedOrders: confirmedOrders,
    pickupedOrders: pickupedOrders,
    completedOrders: completedOrders,
  );
});

/// KDS 모드의 5개 탭(전체 / 진행 / 픽업 / 완료 / 취소)이 한 번에 필요로 하는
/// 필터링·정렬된 리스트 + 카운트 묶음.
///
/// - `orderProvider.select((s) => s.orders)` 만 watch → 무관 필드(`isLoading`,
///   `visibleOrderCount` 등) 변경으로는 재계산하지 않음.
/// - `kdsTabSortDirectionsProvider` watch → 정렬 방향 변경 시 재계산.
/// - `all` 은 **오늘 날짜 기준** 실시간 데이터. 과거 날짜 보기는 화면 측에서
///   `orderHistoryProvider` 분기로 별도 처리.
final kdsTabOrdersProvider = Provider<
    ({
      List<OrderModel> all,
      List<OrderModel> pending,
      List<OrderModel> pickup,
      List<OrderModel> completed,
      List<OrderModel> cancelled,
      int allCount,
      int pendingCount,
      int pickupCount,
      int completedCount,
      int cancelledCount,
    })>((ref) {
  final orders = ref.watch(orderProvider.select((s) => s.orders));
  final sortDirections = ref.watch(kdsTabSortDirectionsProvider);

  final allTabSortDirection = sortDirections[0] ?? OrderSortDirection.ASC;
  final progressTabSortDirection = sortDirections[1] ?? OrderSortDirection.ASC;
  final pickupTabSortDirection = sortDirections[2] ?? OrderSortDirection.DESC;
  final completedTabSortDirection =
      sortDirections[3] ?? OrderSortDirection.DESC;
  final cancelledTabSortDirection =
      sortDirections[4] ?? OrderSortDirection.DESC;

  final all = orders.toList();
  final pending =
      orders.where((o) => o.status == OrderStatus.PREPARING).toList();
  final pickup = orders.where((o) => o.status == OrderStatus.READY).toList();
  final completed = orders.where((o) => o.status == OrderStatus.DONE).toList();
  final cancelled =
      orders.where((o) => o.status == OrderStatus.CANCELLED).toList();

  kds_utils.sortOrders(all, allTabSortDirection);
  kds_utils.sortOrders(pending, progressTabSortDirection);
  kds_utils.sortOrders(pickup, pickupTabSortDirection);
  kds_utils.sortOrders(completed, completedTabSortDirection);
  kds_utils.sortOrders(cancelled, cancelledTabSortDirection);

  return (
    all: all,
    pending: pending,
    pickup: pickup,
    completed: completed,
    cancelled: cancelled,
    allCount: orders.length,
    pendingCount: pending.length,
    pickupCount: pickup.length,
    completedCount: completed.length,
    cancelledCount: cancelled.length,
  );
});

/// 주문 ID 인덱스 — `orderProvider.orders` 를 `{orderId: OrderModel}` 맵으로 변환.
/// P0 의 `OrderState` equality 로 `orders` 미변경 시 select 가 캐싱하므로 맵을
/// 매번 재생성하지 않는다. 카드 단위 조회는 `orderByIdProvider` 경유.
final ordersByIdProvider = Provider<Map<String, OrderModel>>((ref) {
  final orders = ref.watch(orderProvider.select((s) => s.orders));
  return {for (final o in orders) o.orderId: o};
});

/// 주어진 orderId 의 최신 `OrderModel` 을 조회하는 family.
/// `OrderCardWidget` / `KdsOrderCard` 가 카드 단위로 watch 해 자신의 주문 변경만
/// 감지한다(부모 리빌드와 디커플링).
///
/// `autoDispose`: 카드 unmount 후 family entry 가 누적되지 않도록 함.
final orderByIdProvider =
    Provider.autoDispose.family<OrderModel?, String>((ref, id) {
  return ref.watch(ordersByIdProvider.select((map) => map[id]));
});

/// 과거 날짜 KDS 전체 탭용 정렬된 리스트(+ loading 플래그).
/// 오늘 날짜는 `kdsTabOrdersProvider.all` 을 사용한다.
final kdsHistoryAllOrdersProvider = Provider<
    ({
      List<OrderModel> orders,
      bool isLoading,
    })>((ref) {
  final historyAsync = ref.watch(orderHistoryProvider);
  final sortDirection =
      ref.watch(kdsTabSortDirectionsProvider.select((m) => m[0])) ??
          OrderSortDirection.ASC;
  return historyAsync.when(
    data: (history) {
      final list = history.toList();
      kds_utils.sortOrders(list, sortDirection);
      return (orders: list, isLoading: false);
    },
    loading: () => (orders: const <OrderModel>[], isLoading: true),
    error: (_, __) => (orders: const <OrderModel>[], isLoading: false),
  );
});
