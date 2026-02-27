import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/order_model.dart';
import '../core/orders/cache/order_detail_cache.dart';
import '../services/api_service.dart';
import '../utils/logger.dart';
import 'kds_unified_providers.dart';
import 'providers.dart';

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

  /// 주문 상세 정보를 캐시에 저장
  void putOrderDetailCache(String orderId, OrderModel order) {
    _orderDetailCache.put(orderId, order);
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

  /// 기존 상세 정보를 보존하면서 새 주문 목록과 병합
  List<OrderModel> mergeWithExistingDetails(
      List<OrderModel> newOrders, List<OrderModel> existingOrders) {
    final Map<String, OrderModel> existingDetailsMap = {};

    // 기존 주문들 중 상세 정보가 있는 것들을 맵에 저장
    for (final existingOrder in existingOrders) {
      if (existingOrder.menus.isNotEmpty) {
        existingDetailsMap[existingOrder.orderNo] = existingOrder;
      }
    }

    // 캐시에서도 상세 정보 확인
    for (final newOrder in newOrders) {
      if (newOrder.menus.isEmpty) {
        final cachedDetail = _orderDetailCache.get(newOrder.orderNo);
        if (cachedDetail != null && cachedDetail.menus.isNotEmpty) {
          existingDetailsMap[newOrder.orderNo] = cachedDetail;
        }
      }
    }

    // 새 주문 목록에 기존 상세 정보 병합
    return newOrders.map((newOrder) {
      final existingDetail = existingDetailsMap[newOrder.orderNo];
      if (existingDetail != null && newOrder.menus.isEmpty) {
        // 상세 정보는 기존 것을 사용하되, 상태 정보는 새로운 것 사용
        return existingDetail.copyWith(
          status: newOrder.status,
          orderStatus: newOrder.orderStatus,
          updateTime: newOrder.updateTime.isAfter(existingDetail.updateTime)
              ? newOrder.updateTime
              : existingDetail.updateTime,
        );
      }
      return newOrder;
    }).toList();
  }

  /// 주문 상세 정보를 백그라운드에서 병렬로 로드
  Future<void> loadOrderDetailsInBackground(List<OrderModel> orders) async {
    try {
      // 상세 정보가 없는 주문들만 필터링
      final ordersNeedingDetails = orders
          .where((order) => order.menus.isEmpty && order.orderNo.isNotEmpty)
          .toList();

      if (ordersNeedingDetails.isEmpty) {
        logger.d('상세 정보가 필요한 주문이 없습니다.');
        return;
      }

      logger.d('${ordersNeedingDetails.length}개 주문의 상세 정보를 백그라운드에서 로드합니다.');

      // 저사양 장비 고려한 상세 정보 로드
      final isKdsMode = ref.read(kdsModeProvider);
      final int batchSize = isKdsMode ? 2 : 10; // KDS 모드에서는 더 작은 배치
      final int delayMs = isKdsMode ? 300 : 50; // KDS 모드에서는 더 긴 지연

      for (int i = 0; i < ordersNeedingDetails.length; i += batchSize) {
        final batch = ordersNeedingDetails.skip(i).take(batchSize).toList();

        // 이미 캐시에 있는 주문은 건너뛰기
        final ordersToLoad = batch
            .where((order) => !_orderDetailCache.contains(order.orderNo))
            .toList();

        if (ordersToLoad.isNotEmpty) {
          if (isKdsMode) {
            // KDS 모드에서는 순차적으로 처리 (저사양 장비 고려)
            for (final order in ordersToLoad) {
              try {
                await fetchOrderDetail(order.orderNo);
                // 각 주문 로드 후 휴식
                await Future.delayed(const Duration(milliseconds: 200));
              } catch (e) {
                logger.e('상세 정보 로드 오류: ${order.orderNo}', error: e);
              }
            }
          } else {
            // 일반 모드에서는 병렬 처리
            await Future.wait(
              ordersToLoad.map((order) => fetchOrderDetail(order.orderNo)),
            );
          }
        }

        // 각 배치 완료 후 대기 시간
        if (i + batchSize < ordersNeedingDetails.length) {
          await Future.delayed(Duration(milliseconds: delayMs));
        }
      }

      logger.d('백그라운드 상세 정보 로드 완료');
    } catch (e, s) {
      logger.e('백그라운드 상세 정보 로드 중 오류 발생', error: e, stackTrace: s);
    }
  }
}
