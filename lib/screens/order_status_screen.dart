import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/order_model.dart';
import '../providers/order_provider.dart';
import '../widgets/home/order_section_widget.dart';
import '../widgets/order/order_detail_popup.dart';
import '../i18n/strings.g.dart';

class OrderStatusScreen extends ConsumerWidget {
  const OrderStatusScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orderState = ref.watch(orderProvider);

    // 에러 상태 처리
    /* if (orderState.error != null && !orderState.isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text(
              '주문 정보를 불러오는 중 오류가 발생했습니다.\n${orderState.error}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('새로고침'),
              onPressed: () {
                ref.read(orderProvider.notifier).refreshOrders();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppStyles.kMainColor,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }*/

    // 로딩 상태 처리 (선택적)
    // if (orderState.isLoading) {
    //   return const Center(child: CircularProgressIndicator());
    // }

    // 정상 상태 처리 (기존 로직)
    final orders = orderState.orders;
    final newOrders = orders.where((o) => o.status == OrderStatus.NEW).toList();
    final confirmedOrders =
        orders.where((o) => o.status == OrderStatus.PREPARING).toList();
    final pickupedOrders =
        orders.where((o) => o.status == OrderStatus.READY).toList();
    final completedOrders = orders
        .where((o) =>
            o.status == OrderStatus.DONE || o.status == OrderStatus.CANCELLED)
        .toList();

    // 각 섹션별 정렬 적용
    // 신규/접수/대기 섹션: 오래된 주문이 앞(왼쪽)에 오도록 주문 시간 기준 오름차순 정렬 (FIFO)
    newOrders.sort((a, b) => a.orderedAt.compareTo(b.orderedAt));
    confirmedOrders.sort((a, b) => a.orderedAt.compareTo(b.orderedAt));
    pickupedOrders.sort((a, b) => a.orderedAt.compareTo(b.orderedAt));

    // 완료 섹션: 최신 주문이 앞(왼쪽)에 오도록 주문 시간 기준 내림차순 정렬 (최근 완료 순)
    completedOrders.sort((a, b) => b.orderedAt.compareTo(a.orderedAt));

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
