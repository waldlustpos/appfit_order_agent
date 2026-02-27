import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import '../core/orders/order_queue_service.dart';
import '../models/order_model.dart';
import '../utils/logger.dart';
import 'providers.dart';
import '../services/appfit/appfit_providers.dart';
import '../services/api_service.dart';
import 'package:appfit_core/appfit_core.dart' as appfit_core;
import 'package:appfit_order_agent/utils/socket_event_suppressor.dart';

/// 소켓 관련 기능을 관리하는 클래스
/// 소켓 연결, 구독, 알림 처리 등을 담당합니다.
class OrderSocketManager {
  final Ref ref;

  // 재연결 감지용 플래그 (초기 연결과 재연결 구분)
  bool _hasEverConnected = false;

  // 소켓 관련 구독
  // 소켓 관련 구독
  StreamSubscription<Map<String, dynamic>>? _messageStreamSubscription;

  // 외부 서비스 참조
  // 외부 서비스 참조
  late final OrderQueueService _orderQueueService;

  // 콜백 함수들
  final VoidCallback? onRefreshOrders;
  final Function(String)? onUpdateLastKnownOrderSequence;

  OrderSocketManager(
    this.ref, {
    this.onRefreshOrders,
    this.onUpdateLastKnownOrderSequence,
  }) {
    _orderQueueService = ref.read(orderQueueAppServiceProvider);
  }

  /// 소켓 변경사항 리스닝 시작
  void listenToSocketChanges() {
    // 1. AppFit Notifier Listener
    ref.listen(appFitNotifierServiceProvider, (previous, next) {
      final isConnected = next == appfit_core.ConnectionStatus.connected;
      logger.d('[AppFitNotifier] 상태 변경: 연결됨=$isConnected');

      if (isConnected) {
        // 구독이 필요한지 확인 (이미 구독중이면 스킵?)
        // _messageStreamSubscription 체크로 변경
        if (_messageStreamSubscription == null) {
          logger.i('[OrderSocketManager] AppFit 소켓 연결됨 - 구독 시작');
          _subscribeToAppFitNotifications();
        }
        // 재연결 시 놓친 주문 동기화 (초기 연결 제외)
        if (_hasEverConnected) {
          logger.i('[OrderSocketManager] 소켓 재연결 감지 → 놓친 주문 새로고침');
          onRefreshOrders?.call();
        }
        _hasEverConnected = true;
      } else {
        logger.i('[OrderSocketManager] AppFit 소켓 끊김 - 구독 해제');
        _unsubscribeFromOrderNotifications(); // 공용메서드 사용 가능 여부 확인
      }
    });

    // 앱 시작시 초기 소켓 상태 확인
    Future.microtask(() {
      final isConnected = ref.read(appFitNotifierServiceProvider) == appfit_core.ConnectionStatus.connected;
      logger.d('앱 시작시 AppFit 소켓 상태 확인: 연결됨=$isConnected');
      if (isConnected) {
        _subscribeToAppFitNotifications();
      }
    });
  }

  /// 소켓 연결 상태 확인 및 문제 해결
  void checkAndFixSocketConnection(bool isLoggedOut) {
    if (isLoggedOut) {
      logger.d('로그아웃 상태이므로 소켓 연결을 건너뜁니다.');
      return;
    }

    // AppFit 모드 연결 확인
    final isConnected = ref.read(appFitNotifierServiceProvider) == appfit_core.ConnectionStatus.connected;
    if (!isConnected) {
      // AppFit은 AuthProvider login시 자동 연결되지만,
      // 앱 재시작 등 상황에서 재연결 로직이 필요하다면 여기서 트리거 가능
      // 현재 AppFitNotifierService 내부에 재연결 로직 있음
      logger.d('AppFit 소켓 연결 상태 확인: $isConnected');
      // 필요시 수동 연결 코드 추가 가능 (credential 필요)
    } else if (_messageStreamSubscription == null) {
      logger.d('AppFit 소켓 연결됨 but 구독 없음 - 구독 시작');
      _subscribeToAppFitNotifications();
    }
    return;
  }

  /// AppFit 주문 알림 구독
  void _subscribeToAppFitNotifications() {
    logger.i('AppFit 주문 알림 구독 시작');
    final notifier = ref.read(appFitNotifierServiceProvider.notifier);

    // 기존 구독 해제
    _unsubscribeFromOrderNotifications(); // 변수 재사용

    _messageStreamSubscription = notifier.stream.listen((data) {
      _handleAppFitEvent(data);
    });
  }

  /// AppFit 이벤트 처리
  void _handleAppFitEvent(Map<String, dynamic> data) async {
    try {
      final eventType = data['eventType'];
      final payload = data['payload'] as Map<String, dynamic>?;

      if (payload == null) {
        logger.w('[AppFit Event] Payload가 없습니다: $data');
        return;
      }

      // Payload에서 orderNo를 우선적으로 찾고, 없으면 orderId를 찾음
      String? orderId = payload['orderNo']?.toString();
      if (orderId == null || orderId.isEmpty) {
        orderId = payload['orderId']?.toString();
      }

      if (orderId == null || orderId.isEmpty) {
        logger.w('[AppFit Event] orderNo 또는 orderId가 없습니다: $data');
        return;
      }

      logger.d('[AppFit Event] 수신타입: $eventType, OrderId: $orderId');

      // 자가 발생 이벤트 무시 체크
      if (SocketEventSuppressor().shouldIgnore(orderId, eventType)) {
        return;
      }

      final storeId = ref.read(preferenceServiceProvider).getId();
      final eventShopCode = payload['shopCode']?.toString();

      // shopCode가 제공된 경우 현재 매장과 일치하는지 확인
      if (eventShopCode != null &&
          storeId != null &&
          eventShopCode.toUpperCase() != storeId.toUpperCase()) {
        logger.d(
            '[AppFit Event] 다른 매장의 이벤트입니다. (Current: $storeId, Event: $eventShopCode)');
        return;
      }

      // API 호출 시 사용할 shopCode 결정
      final targetShopCode = eventShopCode ?? storeId;
      if (targetShopCode == null) {
        logger.w('[AppFit Event] shopCode를 특정할 수 없습니다.');
        return;
      }

      // 주문 생성, 취소, 상태 변경 이벤트 처리
      if (eventType == appfit_core.OrderEventType.orderCreated.value ||
          eventType == appfit_core.OrderEventType.orderCancelled.value ||
          eventType == appfit_core.OrderEventType.orderAccepted.value ||
          eventType == appfit_core.OrderEventType.orderPickupRequested.value ||
          eventType == appfit_core.OrderEventType.orderDone.value) {
        logger.i('[AppFit] 주문 실시간 알림 수신 ($eventType): $orderId');

        final isKdsMode = ref.read(kdsModeProvider);

        // 1. KDS에서 ORDER_CREATE 무시
        if (_shouldIgnoreEvent(eventType, isKdsMode)) {
          logger.d('[AppFit] KDS 모드: orderCreated 이벤트 무시 - $orderId');
          return;
        }

        // 2. KDS 타 기기 이벤트 무시 설정
        if (isKdsMode && _shouldIgnoreKdsOtherDeviceEvent(eventType)) {
          logger.i('[AppFit] KDS 모드: 타 기기 이벤트($eventType) 무시 - $orderId');
          return;
        }

        // 3. 상세 조회 여부 결정
        final hasDetail =
            ref.read(orderProvider.notifier).hasDetailCache(orderId);
        final shouldFetchDetail =
            _shouldFetchDetail(eventType, isKdsMode, hasDetail);

        if (shouldFetchDetail) {
          try {
            var orderModel = await ref
                .read(appFitApiServiceProvider)
                .getOrder(orderId, storeId: targetShopCode);

            // [FIX] API 상태가 소켓 이벤트보다 늦게 갱신될 수 있으므로,
            // 이벤트 타입에 따라 강제로 상태를 보정합니다.
            orderModel = _enforceStatusFromEvent(orderModel, eventType);

            // 주문 처리 (큐 추가, 상태 업데이트, 알림/출력 등 공통 로직)
            _processNewOrder(orderModel);
          } catch (e) {
            logger.e('[AppFit] 주문 상세 조회 실패 ($orderId): $e');
          }
        } else {
          logger.d('[AppFit] 상세 조회 생략, 로컬 상태 업데이트 수행 ($eventType)');
          // 로컬 상태 기반 업데이트
          final localOrder =
              ref.read(orderProvider.notifier).getCachedOrderDetail(orderId);
          if (localOrder != null) {
            final updatedOrder =
                _enforceStatusFromEvent(localOrder, eventType).copyWith(
              updateTime: DateTime.now(),
            );

            // 큐 처리를 통해 일관된 UI/알림 흐름 타도록 함
            _processNewOrder(updatedOrder);
          } else {
            // 캐시 미스 시 - state.orders에서 주문 찾아서 상태만 갱신
            final stateOrder =
                ref.read(orderProvider.notifier).getOrderFromState(orderId);
            if (stateOrder != null) {
              final updatedOrder =
                  _enforceStatusFromEvent(stateOrder, eventType).copyWith(
                updateTime: DateTime.now(),
              );
              _processNewOrder(updatedOrder);
            } else {
              // 혹시라도 로컬 오더가 null이면 (위에서 hasDetail 체크했지만 동시성 이슈 등 방어)
              // 재귀적으로 API 호출 시도하지 않고 로그 남기고 종료 (무한 루프 방지) or API 호출
              logger.w(
                  '[AppFit] 로컬 오더 찾을 수 없음 (unexpected), API 호출 시도. ID: $orderId');
              try {
                var orderModel = await ref
                    .read(appFitApiServiceProvider)
                    .getOrder(orderId, storeId: targetShopCode);

                orderModel = _enforceStatusFromEvent(orderModel, eventType);

                _processNewOrder(orderModel);
              } catch (e) {
                logger.e('[AppFit] Fallback 주문 상세 조회 실패: $e');
              }
            }
          }
        }
      } else {
        logger.d('[AppFit Event] 처리되지 않는 이벤트 타입: $eventType');
      }
    } catch (e) {
      logger.e('[AppFit] 이벤트 처리 오류', error: e);
    }
  }

  /// KDS에서 무시할 이벤트 타입인지 확인 (ORDER_CREATE는 KDS에서 무시)
  bool _shouldIgnoreEvent(String eventType, bool isKdsMode) {
    return isKdsMode && eventType == appfit_core.OrderEventType.orderCreated.value;
  }

  /// KDS "타 기기 이벤트 무시" 설정 적용 (ORDER_ACCEPTED는 항상 처리)
  bool _shouldIgnoreKdsOtherDeviceEvent(String eventType) {
    final ignore =
        ref.read(preferenceServiceProvider).getIgnoreOtherDeviceTasksKds();
    return ignore && eventType != appfit_core.OrderEventType.orderAccepted.value;
  }

  /// 상세 조회 필요 여부: 일반모드=ORDER_CREATED, KDS=ORDER_ACCEPTED
  bool _shouldFetchDetail(String eventType, bool isKdsMode, bool hasDetail) {
    if (!hasDetail) return true;
    if (!isKdsMode) return eventType == appfit_core.OrderEventType.orderCreated.value;
    // KDS: ORDER_ACCEPTED는 항상 최신 API 조회, 나머지는 캐시 기반 업데이트
    return eventType == appfit_core.OrderEventType.orderAccepted.value;
  }

  /// 이벤트 타입에 따라 주문 모델의 상태를 강제로 보정하는 메서드
  OrderModel _enforceStatusFromEvent(OrderModel order, String eventType) {
    OrderStatus newStatus = order.status;
    String statusCode = order.orderStatus;

    if (eventType == appfit_core.OrderEventType.orderCreated.value) {
      newStatus = OrderStatus.NEW;
      statusCode = '2003';
    } else if (eventType == appfit_core.OrderEventType.orderAccepted.value) {
      newStatus = OrderStatus.PREPARING;
      statusCode = '2007';
    } else if (eventType == appfit_core.OrderEventType.orderPickupRequested.value) {
      newStatus = OrderStatus.READY;
      statusCode = '2009'; // 픽업 요청 -> 준비 완료
    } else if (eventType == appfit_core.OrderEventType.orderDone.value) {
      newStatus = OrderStatus.DONE;
      statusCode = '2020';
    } else if (eventType == appfit_core.OrderEventType.orderCancelled.value) {
      newStatus = OrderStatus.CANCELLED;
      statusCode = '9001';
    }

    // 상태가 실제 변경된 경우에만 로그 (너무 빈번한 로그 방지)
    if (order.status != newStatus) {
      logger.d(
          '[SocketManager] 상태 보정 적용 ($eventType): ${order.status} -> $newStatus');
    }

    return order.copyWith(
      status: newStatus,
      orderStatus: statusCode,
    );
  }

  /// 주문 처리 (공통 로직 분리)
  void _processNewOrder(OrderModel orderData) {
    try {
      // 큐에 추가
      _orderQueueService.enqueueAll([orderData]);

      // 시퀀스 업데이트
      try {
        final bool isOrderSimpleNumNumeric =
            int.tryParse(orderData.shopOrderNo) != null;
        if (isOrderSimpleNumNumeric) {
          onUpdateLastKnownOrderSequence?.call(orderData.shopOrderNo);
        }
      } catch (e) {
        logger.e('Error updating sequence', error: e);
      }

      // KDS 모드인 경우 추가 처리?
      // 기존 로직: socketOrderService.subscribe 내부에서 kdsMode check후 return했음.
      // 하지만 AppFit에서는 KDS도 소켓을 써야 하므로 체크 생략 (통합).
    } catch (e, stack) {
      logger.e('주문 처리 중 오류 발생', error: e, stackTrace: stack);
    }
  }

  /// 주문 알림 구독 해제
  void _unsubscribeFromOrderNotifications() {
    _messageStreamSubscription?.cancel();
    _messageStreamSubscription = null;
  }

  /// 구독 정리
  void clearSubscriptions() {
    _messageStreamSubscription?.cancel();
    _messageStreamSubscription = null;
    logger.d('[OrderSocketManager] 구독 정리 완료');
  }

  /// 로그아웃 시 정리
  void clearOnLogout() {
    _hasEverConnected = false;
    _unsubscribeFromOrderNotifications();
    clearSubscriptions();
    logger.d('[OrderSocketManager] 로그아웃 시 정리 완료');
  }

  /// Dispose
  void dispose() {
    clearSubscriptions();
    logger.d('[OrderSocketManager] dispose 완료');
  }
}
