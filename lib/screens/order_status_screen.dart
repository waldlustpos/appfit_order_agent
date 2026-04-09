import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

    return Column(
      children: [
        Expanded(
          child: OrderSectionWidget(
            title: t.order_status.tab_new,
            orders: newOrders,
            color: Colors.orange,
            status: OrderStatus.NEW,
            onOrderTap: (order) => _showOrderDetails(context, order),
          ),
        ),
        Expanded(
          child: OrderSectionWidget(
            title: t.order_status.tab_preparing,
            orders: confirmedOrders,
            color: Colors.blue,
            status: OrderStatus.PREPARING,
            onOrderTap: (order) => _showOrderDetails(context, order),
          ),
        ),
        Expanded(
          child: OrderSectionWidget(
            title: t.order_status.tab_ready,
            orders: pickupedOrders,
            color: Colors.purple,
            status: OrderStatus.READY,
            onOrderTap: (order) => _showOrderDetails(context, order),
          ),
        ),
        Expanded(
          child: OrderSectionWidget(
            title: t.order_status.tab_done,
            orders: completedOrders,
            color: Colors.green,
            status: OrderStatus.DONE,
            onOrderTap: (order) => _showOrderDetails(context, order),
          ),
        ),
      ],
    );
  }

  // _showOrderDetails 메서드 수정 (context를 인자로 받도록)
  void _showOrderDetails(BuildContext context, OrderModel order) {
    showDialog(
      barrierDismissible: true,
      context: context, // 전달받은 context 사용
      builder: (context) => OrderDetailPopup(order: order),
    ).then((_) {
      // OrderDetailPopup에서 상태가 변경됐을 수 있으므로
      // 참조해서 쓰는 방식으로 구현된 ConsumerWidget은
      // 상태 변경을 자동 감지해서 rebuild되므로 추가 로직 필요없음
    });
  }
}

// 전역 키 제거 (사용하지 않음)
// final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
