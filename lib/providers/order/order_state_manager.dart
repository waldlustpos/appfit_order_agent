import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:appfit_order_agent/models/order_model.dart';
import 'package:appfit_order_agent/providers/kds/kds_unified_providers.dart';
import 'package:appfit_order_agent/models/order_state.dart';
import 'package:appfit_order_agent/utils/logger.dart';

/// 주문 상태 관리 클래스
/// 활성 주문 수 계산과 단일 주문 갱신을 담당합니다.
class OrderStateManager {
  final Ref ref;

  OrderStateManager(this.ref);

  /// 활성 주문 수 계산
  int calculateActiveOrderCount(List<OrderModel> orders) {
    final isKdsMode = ref.read(kdsModeProvider);
    if (isKdsMode) {
      // KDS: 접수(PREPARING)만 신규건수로 간주
      return orders
          .where((order) => order.status == OrderStatus.PREPARING)
          .length;
    }
    // 일반 모드: NEW, PREPARING 상태를 활성 주문으로 간주
    return orders
        .where((order) =>
            order.status == OrderStatus.NEW ||
            order.status == OrderStatus.PREPARING)
        .length;
  }

  /// 주문 목록에서 특정 주문 업데이트
  OrderState updateOrderInList(
      OrderState currentState, OrderModel updatedOrder) {
    final currentOrders = currentState.orders;
    final orderIndex =
        currentOrders.indexWhere((o) => o.orderId == updatedOrder.orderId);

    if (orderIndex != -1) {
      final newOrders = List<OrderModel>.from(currentOrders);
      newOrders[orderIndex] = updatedOrder;
      final activeCount = calculateActiveOrderCount(newOrders);
      logger.d(
          '주문 목록 업데이트 완료: ${updatedOrder.orderId}, 새 상태: ${updatedOrder.status}');

      return currentState.copyWith(
        orders: newOrders,
        activeOrderCount: activeCount,
      );
    } else {
      logger.w('업데이트할 주문을 찾을 수 없음: ${updatedOrder.orderId}');
      return currentState;
    }
  }
}
