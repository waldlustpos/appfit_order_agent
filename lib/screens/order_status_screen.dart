import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:appfit_order_agent/constants/app_styles.dart';
import 'package:appfit_order_agent/models/order_model.dart';
import 'package:appfit_order_agent/providers/order/order_computed_providers.dart';
import 'package:appfit_order_agent/widgets/home/order_section_widget.dart';
import 'package:appfit_order_agent/widgets/order/order_detail_popup.dart';
import 'package:appfit_order_agent/i18n/strings.g.dart';

class OrderStatusScreen extends ConsumerWidget {
  const OrderStatusScreen({super.key});

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
