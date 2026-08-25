import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:appfit_order_agent/core/net/transient_error.dart';
import 'package:appfit_order_agent/core/orders/order_queue_service.dart';
import 'package:appfit_order_agent/exceptions/order_detail_fetch_failed_exception.dart';
import 'package:appfit_order_agent/models/order_model.dart';
import 'package:appfit_order_agent/utils/logger.dart';
import 'package:appfit_order_agent/providers/providers.dart';
import 'package:appfit_core/appfit_core.dart' as appfit_core;
import 'package:appfit_order_agent/utils/socket_event_suppressor.dart';

/// 소켓 관련 기능을 관리하는 클래스
/// 소켓 연결, 구독, 알림 처리 등을 담당합니다.
class OrderSocketManager {
  final Ref ref;

  // 소켓 관련 구독
  StreamSubscription<Map<String, dynamic>>? _messageStreamSubscription;

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
      final isConnected = next.isConnected;
      logger.d('[AppFitNotifier] 상태 변경: $next (연결됨=$isConnected)');

      if (isConnected) {
        if (_messageStreamSubscription == null) {
          logger.i('[OrderSocketManager] AppFit 소켓 연결됨 - 구독 시작');
          _subscribeToAppFitNotifications();
        }
        // 재연결 시 놓친 주문 동기화 (initialConnected 제외)
        if (next == appfit_core.ConnectionStatus.reconnected) {
          logger.i('[OrderSocketManager] 소켓 재연결 감지 → 놓친 주문 새로고침');
          onRefreshOrders?.call();
        }
      } else {
        logger.i('[OrderSocketManager] AppFit 소켓 끊김 - 구독 해제');
        _unsubscribeFromOrderNotifications();
      }
    });

    // 앱 시작시 초기 소켓 상태 확인
    Future.microtask(() {
      final status = ref.read(appFitNotifierServiceProvider);
      logger.d('앱 시작시 AppFit 소켓 상태 확인: $status');
      if (status.isConnected) {
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
    final isConnected = ref.read(appFitNotifierServiceProvider).isConnected;
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

  /// 도메인 정책: KDS 모드 분기 + 타 기기 이벤트 무시 설정.
  /// `appfit_core` SocketEventDispatcher 의 shouldIgnore 콜백으로 주입된다.
  bool _shouldIgnoreByDomainPolicy(
      appfit_core.OrderEventType type, appfit_core.SocketEventPayload _) {
    final isKdsMode = ref.read(kdsModeProvider);

    // 1. KDS 모드에서 NEW(ORDER_CREATED) 차단 — appfit_core 정책 진입점.
    //    KDS 자동접수(KEY_KDS_ACCEPT_ORDERS) 토글이 ON 이면 단독 운영 시나리오로 보고
    //    NEW 이벤트를 허용한다(자동접수 파이프라인 통과).
    if (type == appfit_core.OrderEventType.orderCreated &&
        appfit_core.OrderEventIgnorePolicy.ignoreNewOrderInKdsMode(isKdsMode) &&
        !ref.read(preferenceServiceProvider).getKdsAcceptOrders()) {
      return true;
    }

    // 2. KDS "타 기기 이벤트 무시" 설정 (ORDER_ACCEPTED 는 항상 처리).
    if (isKdsMode &&
        type != appfit_core.OrderEventType.orderAccepted &&
        ref.read(preferenceServiceProvider).getIgnoreOtherDeviceTasksKds()) {
      return true;
    }

    return false;
  }

  /// AppFit 이벤트 처리.
  ///
  /// 1) 자가 PUT echo 차단 (`SocketEventSuppressor`, 1회성 소비)
  /// 2) `SocketEventDispatcher` 로 페이로드 파싱·shopCode·정책 ignore 분류
  /// 3) `accepted` 만 도메인 후속(상세 조회 / 캐시 분기 / `_processNewOrder`) 진행
  void _handleAppFitEvent(Map<String, dynamic> data) async {
    try {
      // 1. 자가 PUT echo 차단 — eventType 키 1회성 소비. dispatcher 진입 전에 처리.
      final preEventType = (data['eventType'] as String?) ?? '';
      final prePayload = (data['payload'] as Map<String, dynamic>?) ?? {};
      String? preOrderId = prePayload['orderNo']?.toString();
      if (preOrderId == null || preOrderId.isEmpty) {
        preOrderId = prePayload['orderId']?.toString();
      }
      if (preOrderId != null &&
          preOrderId.isNotEmpty &&
          preEventType.isNotEmpty &&
          SocketEventSuppressor().shouldIgnore(preOrderId, preEventType)) {
        return;
      }

      // 1-b. 기기 호출(DEVICE_CALL_REQUESTED) — 주문 라이프사이클이 아니라 orderId 가
      //      없어 appfit_core dispatcher 가 무효/미처리로 버린다. dispatcher 진입 전에
      //      조기 분기해 앱 내부에서 직접 처리(영수증 알림 슬립 출력). core 미수정.
      if (preEventType == 'DEVICE_CALL_REQUESTED') {
        await _handleDeviceCall(prePayload);
        return;
      }

      // 2. dispatcher classify — 파싱·페이로드·shopCode·정책 단일 진입점.
      final dispatcher = appfit_core.SocketEventDispatcher(
        resolveStoreId: () =>
            ref.read(preferenceServiceProvider).getActiveStoreId(),
        shouldIgnore: _shouldIgnoreByDomainPolicy,
      );
      final outcome = dispatcher.classify(data);

      if (!outcome.isAccepted) {
        // 분류 결과별 로그만 남기고 종료. 도메인 후속 미진행.
        switch (outcome.kind) {
          case appfit_core.SocketDispatchKind.invalidPayload:
            logger.w('[AppFit Event] 무효 페이로드: ${outcome.reason}');
            break;
          case appfit_core.SocketDispatchKind.unknownEventType:
            logger.d('[AppFit Event] 미처리 이벤트 타입: ${outcome.reason}');
            break;
          case appfit_core.SocketDispatchKind.ignoredByShopCode:
            logger.d('[AppFit Event] ${outcome.reason}');
            break;
          case appfit_core.SocketDispatchKind.ignoredByPolicy:
            logger.d('[AppFit Event] 정책 무시: ${outcome.reason}');
            break;
          case appfit_core.SocketDispatchKind.accepted:
            // 도달 불가
            break;
        }
        return;
      }

      final payload = outcome.payload!;
      final orderId = payload.orderId!;
      final eventType = payload.eventTypeRaw!;
      final eventEnum = payload.eventType!;

      logger.i('[AppFit] 주문 실시간 알림 수신 ($eventType): $orderId');

      final isKdsMode = ref.read(kdsModeProvider);
      final targetShopCode = payload.shopCode ??
          ref.read(preferenceServiceProvider).getActiveStoreId();
      if (targetShopCode == null) {
        logger.w('[AppFit Event] shopCode를 특정할 수 없습니다.');
        return;
      }

      // 처리 가능한 이벤트 타입 화이트리스트 (도메인 책임).
      const handled = <appfit_core.OrderEventType>{
        appfit_core.OrderEventType.orderCreated,
        appfit_core.OrderEventType.orderCancelled,
        appfit_core.OrderEventType.orderAccepted,
        appfit_core.OrderEventType.orderPickupRequested,
        appfit_core.OrderEventType.orderDone,
      };
      if (!handled.contains(eventEnum)) {
        logger.d('[AppFit Event] 처리되지 않는 이벤트 타입: $eventType');
        return;
      }

      // 3. 상세 조회 여부 결정
      final hasDetail =
          ref.read(orderProvider.notifier).hasDetailCache(orderId);
      final shouldFetchDetail =
          _shouldFetchDetail(eventType, isKdsMode, hasDetail);

      if (shouldFetchDetail) {
        try {
          var orderModel =
              await _fetchOrderDetailWithRetry(orderId, targetShopCode);

          // [FIX] API 상태가 소켓 이벤트보다 늦게 갱신될 수 있으므로,
          // 이벤트 타입에 따라 강제로 상태를 보정합니다.
          orderModel = _enforceStatusFromEvent(orderModel, eventType);

          // 주문 처리 (큐 추가, 상태 업데이트, 알림/출력 등 공통 로직)
          _processNewOrder(orderModel);
        } catch (e, s) {
          logger.e('[AppFit] 주문 상세 조회 실패 ($orderId): $e');
          _reportDetailFetchFailureAndRecover(
            orderId: orderId,
            eventType: eventType,
            shopCode: targetShopCode,
            source: 'socket',
            error: e,
            stack: s,
          );
        }
      } else {
        logger.d('[AppFit] 상세 조회 생략, 로컬 상태 업데이트 수행 ($eventType)');
        final localOrder =
            ref.read(orderProvider.notifier).getCachedOrderDetail(orderId);
        if (localOrder != null) {
          final updatedOrder =
              _enforceStatusFromEvent(localOrder, eventType).copyWith(
            updateTime: DateTime.now(),
          );
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
            // 동시성 이슈 등 예외적 상황: API fallback 1회 시도.
            logger.w(
                '[AppFit] 로컬 오더 찾을 수 없음 (unexpected), API 호출 시도. ID: $orderId');
            try {
              var orderModel =
                  await _fetchOrderDetailWithRetry(orderId, targetShopCode);
              orderModel = _enforceStatusFromEvent(orderModel, eventType);
              _processNewOrder(orderModel);
            } catch (e, s) {
              logger.e('[AppFit] Fallback 주문 상세 조회 실패: $e');
              _reportDetailFetchFailureAndRecover(
                orderId: orderId,
                eventType: eventType,
                shopCode: targetShopCode,
                source: 'socket_fallback',
                error: e,
                stack: s,
              );
            }
          }
        }
      }
    } catch (e, s) {
      logger.e('[AppFit] 이벤트 처리 오류', error: e, stackTrace: s);
    }
  }

  /// 기기 호출(DEVICE_CALL_REQUESTED) 처리 — 영수증 프린터에 알림 슬립 출력.
  ///
  /// dispatcher 를 우회하므로 매장(shopCode) 검증을 직접 수행(dispatcher 의 대소문자
  /// 무시 비교와 동일). 문구는 [deviceCallType] enum 으로 분기하며 미지 값은 원문
  /// (또는 기본 문구)으로 fallback 해 silent drop 을 방지한다.
  Future<void> _handleDeviceCall(Map<String, dynamic> payload) async {
    final myShop = ref.read(preferenceServiceProvider).getActiveStoreId();
    final eventShop = payload['shopCode']?.toString();
    if (myShop != null &&
        myShop.isNotEmpty &&
        eventShop != null &&
        eventShop.isNotEmpty &&
        myShop.toLowerCase() != eventShop.toLowerCase()) {
      logger.d('[AppFit Event] 타 매장 기기 호출 무시: $eventShop');
      return;
    }

    final deviceId = payload['deviceId']?.toString() ?? '-';
    final rawType = payload['deviceCallType']?.toString() ?? '';
    final phrase = _deviceCallPhrase(rawType);

    logger.i('[AppFit] 기기 호출 수신: deviceId=$deviceId, type=$rawType');

    try {
      await ref
          .read(printServiceProvider)
          .printDeviceCall(deviceId: deviceId, phrase: phrase);
    } catch (e, s) {
      logger.e('[AppFit] 기기 호출 출력 실패', error: e, stackTrace: s);
    }
  }

  /// deviceCallType → 출력 문구 매핑. 미지 값은 원문/기본 문구로 fallback.
  String _deviceCallPhrase(String type) {
    switch (type) {
      case 'PAPER_SHORTAGE':
        return '키오스크 프린터 용지를 확인해주세요';
      case 'STAFF_CALL':
        return '직원 호출';
      default:
        return type.isEmpty ? '기기 호출' : type;
    }
  }

  /// 상세 조회 필요 여부: 일반모드=ORDER_CREATED, KDS=ORDER_ACCEPTED
  bool _shouldFetchDetail(String eventType, bool isKdsMode, bool hasDetail) {
    if (!hasDetail) return true;
    if (!isKdsMode) {
      return eventType == appfit_core.OrderEventType.orderCreated.value;
    }
    // KDS: ORDER_ACCEPTED는 항상 최신 API 조회, 나머지는 캐시 기반 업데이트
    return eventType == appfit_core.OrderEventType.orderAccepted.value;
  }

  /// 소켓 상세조회 재시도 간격 (transient 한정). 첫 시도 즉시 + 0.5s + 1.5s = 총 3회.
  /// printer_job_queue.dart:68 defaultBackoffs 패턴의 축약 — 소켓 이벤트 핸들러를
  /// 길게 점유하지 않도록 누적 cap 을 짧게(~2s) 둔다.
  List<Duration> _detailFetchBackoffs = const [
    Duration.zero,
    Duration(milliseconds: 500),
    Duration(milliseconds: 1500),
  ];

  /// 테스트 전용. 프로덕션에서는 호출하지 않는다. 길이/간격 자유.
  @visibleForTesting
  set detailFetchBackoffs(List<Duration> value) => _detailFetchBackoffs = value;

  /// 소켓 상세조회 전용 transient-only backoff 래퍼.
  ///
  /// 5xx / 타임아웃 / connection 같은 일시적 네트워크 장애만 [_detailFetchBackoffs]
  /// 간격으로 재시도한다. 4xx(주문없음/권한)·취소·파싱 오류는 즉시 rethrow 해
  /// 무한 재시도를 막는다. blast radius 를 소켓 상세조회로 국한하기 위해
  /// ApiService.getOrder 자체가 아닌 이 호출부에서만 감싼다.
  Future<OrderModel> _fetchOrderDetailWithRetry(
      String orderId, String shopCode) async {
    final apiService = ref.read(apiServiceProvider);
    for (var attempt = 0; attempt < _detailFetchBackoffs.length; attempt++) {
      final backoff = _detailFetchBackoffs[attempt];
      if (backoff > Duration.zero) {
        await Future.delayed(backoff);
      }
      try {
        return await apiService.getOrder(orderId, storeId: shopCode);
      } catch (e) {
        final isLast = attempt == _detailFetchBackoffs.length - 1;
        if (isLast || !isTransientError(e)) rethrow;
        logger.w('[AppFit] 상세조회 일시 실패(재시도 ${attempt + 1}/'
            '${_detailFetchBackoffs.length}): $orderId ($e)');
      }
    }
    // 도달 불가 — 루프는 항상 return 또는 rethrow 로 종료된다.
    throw StateError('unreachable: _fetchOrderDetailWithRetry($orderId)');
  }

  /// 테스트 전용 — private 재시도 래퍼를 그대로 노출한다.
  @visibleForTesting
  Future<OrderModel> fetchOrderDetailForTest(String orderId, String shopCode) =>
      _fetchOrderDetailWithRetry(orderId, shopCode);

  /// transient 판정: 일시적 네트워크 장애(타임아웃/연결/5xx)만 재시도 대상.
  /// 4xx·취소·파싱 오류는 재시도해도 동일 실패이므로 false.
  ///
  /// 구현은 [isTransientNetworkError] 로 옮겼다(건강도 판정과 공유). 이 별칭은
  /// 기존 호출부·테스트 호환을 위해 남긴다.
  @visibleForTesting
  static bool isTransientError(Object e) => isTransientNetworkError(e);

  /// 소켓 상세조회 실패 시: Sentry 보고 + 폴링 안전망(refreshOrders) 즉시 트리거.
  ///
  /// _processNewOrder 를 직접 호출하지 않는다 — 메뉴 없는 부분데이터 state 진입과
  /// dedup 우회를 막기 위해 복구는 반드시 기존 폴링 경로(refreshOrders →
  /// _processPollingNewOrders → queueOrderExternal → _outputQueueService.add)로
  /// 위임한다. refreshOrders 의 _isRefreshing 가드가 동시/중복 트리거를 흡수한다.
  void _reportDetailFetchFailureAndRecover({
    required String orderId,
    required String eventType,
    required String shopCode,
    required String source,
    required Object error,
    required StackTrace stack,
  }) {
    appfit_core.MonitoringService.instance.captureError(
      OrderDetailFetchFailedException(
        orderNo: orderId,
        eventType: eventType,
        source: source,
        lastError: error.toString(),
      ),
      stack,
      hint: '소켓 상세조회 실패 — 폴링 안전망 트리거됨',
      extras: {
        'orderId': orderId,
        'eventType': eventType,
        'shopCode': shopCode,
        // 제목에서 뺀 원본 오류 — 여기에 없으면 진단이 사라진다.
        'lastError': error.toString(),
      },
    );
    // 다음 정기 폴링(최대 60s)을 기다리지 않고 즉시 복구를 시도한다.
    onRefreshOrders?.call();
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
    } else if (eventType ==
        appfit_core.OrderEventType.orderPickupRequested.value) {
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
      } catch (e, s) {
        logger.e('Error updating sequence', error: e, stackTrace: s);
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
