import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/order_model.dart';
import '../core/orders/cache/order_detail_cache.dart';
import '../utils/logger.dart';
import 'kds_unified_providers.dart';
import 'providers.dart';

/// 주문 관련 헬퍼 메서드들을 담는 클래스
class OrderHelperMethods {
  final Ref ref;

  OrderHelperMethods(this.ref);

  /// 주문이 키오스크 주문인지 확인하는 Helper
  bool isKioskOrder(OrderModel order) {
    return order.userId == '3740002700000000' ||
        order.paymentType.contains('KIOSK');
  }

  /// 주문을 UI에 표시할지 여부 확인 (모든 주문 통일 처리)
  bool shouldShowOrder(OrderModel order, bool isKioskOrderVisible) {
    // 오늘 날짜가 아닌 주문은 표시하지 않음
    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);
    final orderDate = DateTime(
        order.orderedAt.year, order.orderedAt.month, order.orderedAt.day);

    if (orderDate.isBefore(todayStart)) {
      logger
          .d('[Filter] 오늘 날짜가 아닌 주문 제외: ${order.orderNo} (${order.orderedAt})');
      return false;
    }

    // KDS 모드일 때는 NEW는 숨기고, 나머지 상태는 표시
    final isKdsMode = ref.read(kdsModeProvider);
    if (isKdsMode) {
      final show = order.status != OrderStatus.NEW;
      return show;
    }

    // 일반 모드: 모든 주문을 동일하게 처리
    if (order.status != OrderStatus.NEW) {
      return true; // 상태가 변경된 주문은 항상 표시
    }

    // NEW 상태 주문은 항상 표시

    return true;
  }

  /// 주문에 대해 소리/알림/인쇄를 할지 여부 확인 (모든 주문 통일 처리)
  bool shouldNotifyForOrder(OrderModel order, bool isKioskOrderSoundEnabled) {
    // KDS 모드일 때는 모든 주문에 대해 항상 알림/출력
    final isKdsMode = ref.read(kdsModeProvider);
    if (isKdsMode) {
      logger.d(
          '[Notify] shouldNotifyForOrder isKdsMode=true -> notify (orderId=${order.orderNo})');
      return true; // KDS 모드에서는 모든 주문에 대해 항상 알림/출력
    }

    // 일반 모드에서도 상태 변경 알림은 항상 받음
    if (order.status != OrderStatus.NEW) {
      logger.d(
          '[Notify] shouldNotifyForOrder status=${order.status} -> notify (orderId=${order.orderNo})');
      return true; // 상태가 변경된 주문은 항상 알림
    }

    // NEW 상태 주문은 항상 알림/출력
    logger.d(
        '[Notify] shouldNotifyForOrder status=NEW -> notify (orderId=${order.orderNo})');
    return true; // 모든 NEW 주문은 항상 알림/출력
  }

  /// 주문 상태가 활성 상태인지 확인
  bool isActiveOrderStatus(OrderStatus status) {
    return status == OrderStatus.NEW || status == OrderStatus.PREPARING;
  }

  /// 주문이 완료 상태인지 확인
  bool isCompletedOrderStatus(OrderStatus status) {
    return status == OrderStatus.READY ||
        status == OrderStatus.DONE ||
        status == OrderStatus.CANCELLED;
  }

  /// 기존 상세 정보를 보존하면서 새 주문 목록과 병합
  List<OrderModel> mergeWithExistingDetails(
    List<OrderModel> newOrders,
    List<OrderModel> existingOrders,
    OrderDetailCache orderDetailCache,
  ) {
    final mergedOrders = <OrderModel>[];

    for (final newOrder in newOrders) {
      // 기존 상태에서 같은 주문 ID를 가진 주문 찾기
      final existingOrder = existingOrders.firstWhere(
        (existing) => existing.orderNo == newOrder.orderNo,
        orElse: () => newOrder,
      );

      // 기존 주문에 상세 정보가 있으면 그것을 사용하되, 새 주문의 상태 정보는 보존
      if (existingOrder.menus.isNotEmpty) {
        logger.d('기존 상세 정보 보존 + 새 상태 정보 적용: ${newOrder.orderNo}');
        // 기존 상세 정보를 유지하되, 새 주문의 상태 정보(상태, 업데이트 시간 등)는 적용
        final mergedOrder = existingOrder.copyWith(
          status: newOrder.status,
          orderStatus: newOrder.orderStatus,
          updateTime: newOrder.updateTime.isAfter(existingOrder.updateTime)
              ? newOrder.updateTime
              : existingOrder.updateTime,
        );

        mergedOrders.add(mergedOrder);
      } else {
        // 캐시에서도 확인
        final cachedOrder = orderDetailCache.get(newOrder.orderNo);
        if (cachedOrder != null && cachedOrder.menus.isNotEmpty) {
          logger.d('캐시된 상세 정보 사용 + 새 상태 정보 적용: ${newOrder.orderNo}');
          // 캐시된 상세 정보를 유지하되, 새 주문의 상태 정보는 적용
          final mergedOrder = cachedOrder.copyWith(
            status: newOrder.status,
            orderStatus: newOrder.orderStatus,
            updateTime: newOrder.updateTime.isAfter(cachedOrder.updateTime)
                ? newOrder.updateTime
                : cachedOrder.updateTime,
          );

          mergedOrders.add(mergedOrder);
        } else {
          mergedOrders.add(newOrder);
        }
      }
    }

    return mergedOrders;
  }
}
