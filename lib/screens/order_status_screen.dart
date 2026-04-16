import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/app_styles.dart';
import '../models/order_model.dart';
import '../providers/order_computed_providers.dart';
import '../widgets/home/order_section_widget.dart';
import '../widgets/order/order_detail_popup.dart';
import '../i18n/strings.g.dart';

class OrderStatusScreen extends ConsumerWidget {
  const OrderStatusScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 필터링+정렬은 orderStatusOrdersProvider에서 캐싱 처리
    final computed = ref.watch(orderStatusOrdersProvider);
    final newOrders = computed.newOrders;
    final confirmedOrders = computed.confirmedOrders;
    final pickupedOrders = computed.pickupedOrders;
    final completedOrders = computed.completedOrders;

    return ColoredBox(
      color: AppStyles.gray1,
      child: Column(
        children: [
          Expanded(
            child: OrderSectionWidget(
              title: t.order_status.tab_new,
              orders: newOrders,
              status: OrderStatus.NEW,
              onOrderTap: (order) => _showOrderDetails(context, order),
            ),
          ),
          Expanded(
            child: OrderSectionWidget(
              title: t.order_status.tab_preparing,
              orders: confirmedOrders,
              status: OrderStatus.PREPARING,
              onOrderTap: (order) => _showOrderDetails(context, order),
            ),
          ),
          Expanded(
            child: OrderSectionWidget(
              title: t.order_status.tab_ready,
              orders: pickupedOrders,
              status: OrderStatus.READY,
              onOrderTap: (order) => _showOrderDetails(context, order),
            ),
          ),
          Expanded(
            child: OrderSectionWidget(
              title: t.order_status.tab_done,
              orders: completedOrders,
              status: OrderStatus.DONE,
              onOrderTap: (order) => _showOrderDetails(context, order),
            ),
          ),
        ],
      ),
    );
  }

  void _showOrderDetails(BuildContext context, OrderModel order) {
    showDialog(
      barrierDismissible: true,
      context: context,
      builder: (context) => OrderDetailPopup(order: order),
    );
  }
}
