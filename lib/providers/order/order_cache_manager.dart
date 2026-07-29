import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:appfit_order_agent/models/order_model.dart';
import 'package:appfit_order_agent/core/orders/cache/order_detail_cache.dart';
import 'package:appfit_order_agent/utils/logger.dart';
import 'package:appfit_order_agent/providers/providers.dart';

/// 주문 캐시 관리 클래스
/// 주문 상세 정보 캐시, 출력 이력 캐시 등을 관리합니다.
class OrderCacheManager {
  final Ref ref;
  final OrderDetailCache _orderDetailCache;

  // 현재 로딩 중인 주문 ID들을 추적하는 Set
  final Set<String> _loadingOrderIds = <String>{};

  OrderCacheManager(this.ref, this._orderDetailCache);

  /// 주문 상세 정보 캐시에서 조회
  OrderModel? getCachedOrderDetail(String orderId) {
    return _orderDetailCache.get(orderId);
  }

  /// 주문 상세 정보 캐시 존재 여부 확인
  bool hasDetailCache(String orderId) {
    return _orderDetailCache.contains(orderId);
  }

  /// 캐시 정리 (만료된 항목들)
  void cleanupExpiredEntries() {
    logger.d('Running periodic cache cleanup...');
    _orderDetailCache.cleanupExpiredEntries();
  }

  /// 주문 상세 정보가 현재 로딩 중인지 확인
  bool isOrderDetailLoading(String orderId) {
    return _loadingOrderIds.contains(orderId);
  }

  /// 주문 상세 정보 조회 (API 호출 포함)
  Future<OrderModel?> fetchOrderDetail(String orderId) async {
    try {
      // 이미 로딩 중인 경우 중복 호출 방지
      if (_loadingOrderIds.contains(orderId)) {
        logger.d('이미 로딩 중인 주문, 중복 호출 방지: $orderId');
        return null;
      }

      // 캐시에서 먼저 확인
      final cachedOrder = _orderDetailCache.get(orderId);
      if (cachedOrder != null) {
        return cachedOrder;
      }

      // 로딩 상태로 표시
      _loadingOrderIds.add(orderId);

      // 현재 매장 정보 가져오기
      final storeState = ref.read(storeProvider);
      if (!storeState.hasValue || storeState.value == null) {
        logger.e('매장 정보가 없습니다.');
        _loadingOrderIds.remove(orderId);
        return null;
      }
      final storeId = storeState.value!.storeId;

      // API 호출
      final apiService = ref.read(apiServiceProvider);
      final orderDetail = await apiService.getOrder(orderId, storeId: storeId);

      // 캐시에 저장
      _orderDetailCache.put(orderId, orderDetail);

      return orderDetail;
    } catch (e, s) {
      logger.e('주문 상세 정보 조회 실패', error: e, stackTrace: s);
      return null;
    } finally {
      // 로딩 상태 해제
      _loadingOrderIds.remove(orderId);
    }
  }

  /// 주문 상세 정보를 가져오되 상태 정보는 최신으로 유지
  Future<OrderModel> getOrderDetail(
      String orderId, String storeId, List<OrderModel> currentOrders) async {
    final cachedOrder = _orderDetailCache.get(orderId);
    if (cachedOrder != null) {
      // 캐시된 주문이 있으면 상태 업데이트만 확인
      final orderIndex = currentOrders.indexWhere((o) => o.orderNo == orderId);
      if (orderIndex != -1) {
        final latestOrderInState = currentOrders[orderIndex];
        if (latestOrderInState.updateTime.isAfter(cachedOrder.updateTime)) {
          logger.d(
              'Returning cached detail with updated status from state list: $orderId');
          return cachedOrder.copyWith(
            status: latestOrderInState.status,
            orderStatus: latestOrderInState.orderStatus,
            updateTime: latestOrderInState.updateTime,
          );
        }
      }
      logger.d('Returning cached detail: $orderId');
      return cachedOrder;
    }

    try {
      logger.d('Fetching order detail from API: $orderId');
      final apiService = ref.read(apiServiceProvider);
      final detailedOrder =
          await apiService.getOrder(orderId, storeId: storeId);

      _orderDetailCache.put(orderId, detailedOrder);
      logger.d('Saved fetched order detail to cache: $orderId');

      // 상태 목록에서 최신 상태 확인
      final orderIndex = currentOrders.indexWhere((o) => o.orderNo == orderId);
      if (orderIndex != -1) {
        final latestOrderInState = currentOrders[orderIndex];
        if (latestOrderInState.updateTime.isAfter(detailedOrder.updateTime)) {
          logger.d(
              'Returning API detail with updated status from state list: $orderId');
          return detailedOrder.copyWith(
            status: latestOrderInState.status,
            orderStatus: latestOrderInState.orderStatus,
            updateTime: latestOrderInState.updateTime,
          );
        }
      }
      logger.d('Returning API detail: $orderId');
      return detailedOrder;
    } catch (e, s) {
      logger.e('Error fetching order detail ($orderId)',
          error: e, stackTrace: s);
      rethrow;
    }
  }

  /// 주문 캐시에서 상태 업데이트
  void updateOrderInCache(
      String orderId, OrderStatus newStatus, String statusCode) {
    if (_orderDetailCache.contains(orderId)) {
      final cachedOrder = _orderDetailCache.get(orderId);
      if (cachedOrder != null) {
        final updatedOrder = cachedOrder.copyWith(
          status: newStatus,
          orderStatus: statusCode,
          updateTime: DateTime.now(),
        );
        _orderDetailCache.put(orderId, updatedOrder);
      }
    }
  }
}
