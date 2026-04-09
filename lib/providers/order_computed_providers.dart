import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/order_model.dart';
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

  final newOrders = orders
      .where((o) => o.status == OrderStatus.NEW)
      .toList()
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
      .where(
          (o) => o.status == OrderStatus.DONE || o.status == OrderStatus.CANCELLED)
      .toList()
    ..sort((a, b) => b.orderedAt.compareTo(a.orderedAt));

  return (
    newOrders: newOrders,
    confirmedOrders: confirmedOrders,
    pickupedOrders: pickupedOrders,
    completedOrders: completedOrders,
  );
});
