import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/order_model.dart';
import 'kds_unified_providers.dart';
import 'order_state.dart';
import '../utils/logger.dart';
import '../utils/model_parse_utils.dart';
import 'providers.dart';

/// 주문 상태 관리 클래스
/// 주문 목록 업데이트, 활성 주문 수 계산, UI 상태 업데이트 등을 담당합니다.
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

  /// 주문을 상태에 추가하거나 업데이트
  OrderState addOrUpdateOrderInState(
      OrderState currentState, OrderModel order) {
    final index =
        currentState.orders.indexWhere((o) => o.orderId == order.orderId);

    if (index != -1) {
      // 기존 주문 업데이트
      final updatedOrders = List<OrderModel>.from(currentState.orders);
      updatedOrders[index] = order;
      final activeCount = calculateActiveOrderCount(updatedOrders);

      logger.d('주문 정보 업데이트: ${order.orderId}');

      return currentState.copyWith(
        orders: updatedOrders,
        activeOrderCount: activeCount,
      );
    } else if (_shouldShowOrder(order)) {
      // 새로운 주문 추가
      final updatedOrders = [...currentState.orders, order];
      final activeCount = calculateActiveOrderCount(updatedOrders);
      logger.d('새로운 주문 추가: ${order.orderId}');

      return currentState.copyWith(
        orders: updatedOrders,
        activeOrderCount: activeCount,
      );
    }

    return currentState;
  }

  /// UI 즉시 업데이트를 위한 메서드
  OrderState performImmediateUIUpdate(
      OrderState currentState, OrderModel updatedOrder, int existingIndex) {
    // 디버깅을 위한 로그 추가 - 업데이트 전
    logger.d(
        'performImmediateUIUpdate 시작 - 업데이트 전 주문 수: ${currentState.orders.length}');
    logger.d(
        '업데이트 전 주문 ID 목록: ${currentState.orders.map((o) => '${o.orderId}(${o.status})').join(', ')}');
    logger.d(
        '업데이트할 주문: ${updatedOrder.orderId}(${updatedOrder.status}), 인덱스: $existingIndex');

    // KDS 모드에서 상태 변경 시 안정적인 UI 업데이트를 위한 처리
    final isKdsMode = ref.read(kdsModeProvider);
    final isStatusTransition = existingIndex != -1 &&
        currentState.orders[existingIndex].status != updatedOrder.status;

    if (existingIndex != -1) {
      // 기존 주문 업데이트 - 깊은 복사로 안전하게 처리
      final updatedOrders =
          currentState.orders.map((order) => order.copyWith()).toList();
      updatedOrders[existingIndex] = updatedOrder;

      final activeCount = calculateActiveOrderCount(updatedOrders);

      // KDS 모드에서 상태 전환 시 안정적인 UI 업데이트
      if (isKdsMode && isStatusTransition) {
        logger.d(
            'KDS 모드: 상태 전환 시 안정적인 UI 업데이트 - ${updatedOrder.orderId}: ${currentState.orders[existingIndex].status} -> ${updatedOrder.status}');
      }

      logger.d(
          '주문 상태 즉시 화면 업데이트: ${updatedOrder.orderId}, 상태: ${updatedOrder.status}');

      return currentState.copyWith(
        orders: updatedOrders,
        activeOrderCount: activeCount,
      );
    } else if (!currentState.orders
        .any((o) => o.orderId == updatedOrder.orderId)) {
      // 상태 목록에 없는 경우 목록에 추가
      final updatedOrders = [...currentState.orders, updatedOrder];
      final activeCount = calculateActiveOrderCount(updatedOrders);

      logger.d(
          '주문 상태 변경 후 즉시 목록에 추가: ${updatedOrder.orderId}, 상태: ${updatedOrder.status}');

      return currentState.copyWith(
        orders: updatedOrders,
        activeOrderCount: activeCount,
      );
    }

    // 디버깅을 위한 로그 추가 - 업데이트 후
    logger.d(
        'performImmediateUIUpdate 완료 - 현재 주문 수: ${currentState.orders.length}');
    logger.d(
        '업데이트 후 주문 ID 목록: ${currentState.orders.map((o) => '${o.orderId}(${o.status})').join(', ')}');

    return currentState;
  }

  /// 주문 목록에 업데이트하고 변경 여부 반환
  Future<({bool changed, OrderState newState})> updateOrderInStateList(
      OrderState currentState, OrderModel order) async {
    try {
      final existingIndex =
          currentState.orders.indexWhere((o) => o.orderId == order.orderId);
      final bool isNewOrder = existingIndex == -1;
      final String todayDate = todayDateString();

      // 주문의 날짜 필드 확인
      final String orderDate = order.orderedAt.toString().substring(0, 10);
      final bool belongsToToday = orderDate == todayDate;

      if (isNewOrder) {
        // 오늘 날짜에 속하고 && 표시해야 하는 주문만 추가
        if (belongsToToday && _shouldShowOrder(order)) {
          final updatedOrders = [...currentState.orders, order];
          final activeCount = calculateActiveOrderCount(updatedOrders);

          final newState = currentState.copyWith(
            orders: updatedOrders,
            activeOrderCount: activeCount,
          );

          logger
              .i('새 주문 목록에 추가 (오늘 날짜): ${order.orderId}, 상태: ${order.status}');
          return (changed: true, newState: newState);
        } else {
          logger.d(
              '주문 ${order.orderId} (날짜: $orderDate)는 오늘($todayDate) 목록에 추가되지 않음 (신규 처리 중).');
          return (changed: false, newState: currentState);
        }
      } else {
        // 기존 주문 업데이트
        final existingOrder = currentState.orders[existingIndex];

        // 상태 변경이 있는지 확인
        if (existingOrder.status != order.status ||
            existingOrder.updateTime != order.updateTime) {
          logger.d(
              '주문 상태/정보 변경됨: ${order.orderId}, ${existingOrder.status} -> ${order.status}');

          final updatedOrders = List<OrderModel>.from(currentState.orders);
          updatedOrders[existingIndex] = order;
          final activeCount = calculateActiveOrderCount(updatedOrders);

          final newState = currentState.copyWith(
            orders: updatedOrders,
            activeOrderCount: activeCount,
          );

          return (changed: true, newState: newState);
        } else {
          logger.d('주문 상태/정보 변경 없음: ${order.orderId}, 상태: ${order.status}');
          return (changed: false, newState: currentState);
        }
      }
    } catch (e, s) {
      logger.e('주문 목록 업데이트 중 오류', error: e, stackTrace: s);
      return (changed: false, newState: currentState);
    }
  }

  /// 주문을 UI에 표시할지 여부 확인
  bool _shouldShowOrder(OrderModel order) {
    // 모든 주문 표시 (기존 로직 유지)
    return true;
  }

  /// blink 상태 업데이트 (자동 동기화되므로 활성 주문 수 계산만 수행하거나 로그용으로 사용 가능)
  void updateBlinkState(List<OrderModel> orders) {
    final filteredOrders = orders.where(_shouldShowOrder).toList();
    final activeCount = calculateActiveOrderCount(filteredOrders);
    logger.d('Blink 상태 확인: 활성 주문 수 $activeCount');
  }
}
