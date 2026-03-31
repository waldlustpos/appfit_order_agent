import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart'; // Generator import
import '../services/preference_service.dart';
import '../services/platform_service.dart';
import '../services/api_service.dart';
import '../models/order_model.dart';
import '../exceptions/api_exceptions.dart';

import 'kds_unified_providers.dart';
import 'order_cache_manager.dart';
import 'order_settings_manager.dart';
import 'order_state_manager.dart';
import 'order_timer_manager.dart';
import 'order_queue_manager.dart';
import 'order_socket_manager.dart';
import 'providers.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:appfit_order_agent/core/orders/sound_service.dart';
import 'package:appfit_order_agent/core/orders/blink_service.dart';
import 'package:appfit_order_agent/core/orders/output_service.dart';
import 'package:appfit_order_agent/core/orders/order_queue_service.dart';
import 'package:appfit_order_agent/services/output_queue_service.dart'; // [NEW]

import 'package:appfit_order_agent/core/orders/cache/order_detail_cache.dart';
import 'package:appfit_order_agent/core/orders/cache/processed_order_cache.dart';
import 'package:appfit_order_agent/services/appfit/appfit_providers.dart';
import 'package:appfit_order_agent/utils/logger.dart';
import 'order_state.dart';
import 'package:appfit_order_agent/utils/socket_event_suppressor.dart';
import 'package:appfit_core/appfit_core.dart' as appfit_core;
import 'order_helper_methods.dart';

import 'package:intl/intl.dart';
// Actually ApiVersion enum is in config/api_version.dart

part 'order_provider.g.dart'; // Generator part file

// moved to core/orders/cache/printed_order_cache.dart

// OrderState 클래스는 order_state.dart로 이동됨

@Riverpod(keepAlive: true)
class Order extends _$Order {
  late ApiService _apiService;
  late PreferenceService _preferenceService;
  late OrderSettingsManager _settingsManager;
  late OrderStateManager _stateManager;
  late OrderCacheManager _cacheManager;
  late OrderTimerManager _timerManager;

  late OrderQueueManager _queueManager;
  late OrderSocketManager _socketManager;

  AudioPlayer _audioPlayer = AudioPlayer();
  final OrderDetailCache _orderDetailCache = OrderDetailCache();
  final ProcessedOrderCache _processedOrderCache = ProcessedOrderCache();
  bool _isAudioPlayerDisposed = false; // AudioPlayer dispose 상태 추적
  String _lastKnownOrderSequence = "0";
  List<OrderModel> _unfilteredOrders = []; // 필터링되지 않은 전체 주문 목록
  // 성능 최적화: 주문 ID 기반 빠른 검색을 위한 Map 인덱스
  final Map<String, int> _orderIndexMap = <String, int>{};
  Timer? _batchProcessingTimer; // 일부는 QueueManager로 이동, 일부는 여전히 필요

  bool _isInitialLoadComplete = false; // 초기 로딩 완료 여부 플래그

  // 타이머들은 OrderTimerManager로 이동됨
  // Timer? _pollingTimer;  // -> _timerManager
  // Timer? _cacheCleanupTimer;  // -> _timerManager
  // Timer? _midnightRefreshTimer;  // -> _timerManager
  Timer? _queueProcessingTimer;
  // 소켓 구독들은 OrderSocketManager로 이동됨
  // StreamSubscription<OrderNotification>? _orderNotificationSubscription;  // -> _socketManager
  // StreamSubscription<Map<String, dynamic>>? _messageStreamSubscription;  // -> _socketManager
  // final int _currentPollingIntervalSeconds = 60; // -> OrderTimerManager로 이동됨
  var tag = '주문';

  // FirestoreSyncService로 이전됨: 개별 구독 핸들 보관 불필요
  // StreamSubscription? _serviceStatusSubscription; // 서비스 스트림 구독 변수

  // 앱 초기화시 알람 재생 여부 플래그
  bool _shouldPlayInitialAlarm = true;
  bool _isLoggedOut = false; // 로그아웃 상태 추적

  // 현재 설치 유형 저장 (향후 사용 예정)
  // InstallType? _currentInstallType; // unused

  // Step 2: Blink service (external)
  late final BlinkService _blinkService;
  // Step 3: Queue/Sync services (external) – reserved for next step
  late final OutputService _outputService;
  late final OutputQueueService _outputQueueService; // [NEW]
  late final OrderQueueService _orderQueueService;
  // late final SocketOrderService _socketOrderService;  // -> OrderSocketManager로 이동됨

  @override
  OrderState build() {
    _apiService = ref.watch(apiServiceProvider);
    _preferenceService = ref.read(preferenceServiceProvider);

    // 관리자 클래스들 초기화
    _settingsManager = OrderSettingsManager(ref, _preferenceService);
    _stateManager = OrderStateManager(ref);
    _cacheManager = OrderCacheManager(ref, _orderDetailCache);
    _queueManager =
        OrderQueueManager(ref, onProcessSingleOrder: _processSingleOrder);

    // [NEW] OutputQueueService 초기화
    _outputQueueService = ref.read(outputQueueServiceProvider);

    _socketManager = OrderSocketManager(
      ref,
      onRefreshOrders: () => refreshOrders(),
      onUpdateLastKnownOrderSequence: (simpleNum) {
        final currentSeqNum = int.tryParse(_lastKnownOrderSequence) ?? 0;
        final orderSimpleNum = int.tryParse(simpleNum) ?? 0;
        if (orderSimpleNum > currentSeqNum) {
          _lastKnownOrderSequence = simpleNum;
        }
      },
    );
    _timerManager = OrderTimerManager(
      ref,
      onPollNewOrders: _pollNewOrders,
      onRefreshOrders: () => refreshOrders(),
      onCacheCleanup: () => _cacheManager.cleanupExpiredEntries(),
    );

    logger.d('Order Provider initializing...');

    // AudioPlayer dispose 상태 초기화 (로그아웃 후 재로그인 시 재초기화)
    if (_isAudioPlayerDisposed) {
      logger.d('[OrderProvider] AudioPlayer 재초기화');
      try {
        _audioPlayer.dispose();
      } catch (_) {}
      _audioPlayer = AudioPlayer();
      _isAudioPlayerDisposed = false;
    }

    // 설정값 로드
    final initialIsAutoReceipt = _preferenceService.getAutoReceipt();

    logger.d('OrderProvider 초기화 - 자동접수 설정: $initialIsAutoReceipt');

    // 설치 유형 감지 및 적절한 초기화 메서드 호출 - 비동기 작업
    Future.microtask(() => _orderDataInitialize());

    _loadSoundSettings();
    _setupPollingTimer();
    _setupCacheCleanupTimer();
    // 내부 타이머 비활성화: OrderQueueService로 대체
    _scheduleMidnightRefresh();
    _socketManager.listenToSocketChanges();

    ref.listen<bool>(kdsModeProvider, (previous, next) {
      if (previous != next) {
        logger.d('[OrderProvider] KDS 모드 변경 감지 ($previous -> $next): 카운트 재계산');
        final activeCount = _calculateActiveOrderCount(state.orders);
        state = state.copyWith(activeOrderCount: activeCount);
      }
    });

    // 소켓 연결 상태에 따른 adaptive polling 간격 조정
    ref.listen(appFitNotifierServiceProvider, (previous, isConnected) {
      if (previous == isConnected) return;
      final isEmergency = _preferenceService.getForceSocketReconnect();
      if (isConnected.isConnected) {
        // 긴급 모드가 ON이면 연결돼도 10s 유지
        if (!isEmergency) {
          logger.d(
              '[OrderProvider] 소켓 연결됨 → 폴링 간격 ${OrderTimerManager.socketConnectedIntervalSeconds}s');
          _timerManager
              .restartPolling(OrderTimerManager.socketConnectedIntervalSeconds);
        }
      } else {
        logger.d(
            '[OrderProvider] 소켓 단절됨 → 폴링 간격 ${OrderTimerManager.socketDisconnectedIntervalSeconds}s');
        _timerManager.restartPolling(
            OrderTimerManager.socketDisconnectedIntervalSeconds);
      }
    });

    // 서버에서 먼저 주문 정보를 가져온 후 Firestore 리스너 설정
    // 중복 호출 방지를 위해 _detectAndInitializeByInstallType에서 처리하도록 수정
    // Future.microtask(() async {
    //   final storeId = ref.read(storeProvider).value?.storeId ?? '';
    //   if (storeId.isNotEmpty && !_isInitialLoadComplete) {
    //     logger.d('[OrderProvider] 서버에서 초기 주문 정보를 가져옵니다.');
    //     await refreshOrders();
    //     _isInitialLoadComplete = true; // 초기 로딩 완료 표시

    //     // 서버에서 주문 정보를 가져온 후 Firestore 리스너 설정
    //     _setupFirestoreServiceListener();
    //   }
    // });

    // 소켓 연결 상태 확인 및 필요시 재연결 실행 (KDS 모드에서는 미사용)
    // 로그인 후 재연결 시에는 지연 시간 단축
    final delayDuration = _isLoggedOut
        ? const Duration(seconds: 2)
        : const Duration(milliseconds: 500);
    Future.delayed(delayDuration, () {
      _socketManager.checkAndFixSocketConnection(_isLoggedOut);
    });

    // Step 2: BlinkService from external provider (로그아웃 상태가 아닐 때만 초기화)
    if (!_isLoggedOut) {
      _blinkService = ref.read(blinkAppServiceProvider);
      // PrintService 조기 초기화를 통해 USB 연결 확인 시작
      ref.read(printServiceProvider);
      _outputService = OutputService(ref, this);
      _orderQueueService = ref.read(orderQueueAppServiceProvider);
      // _socketOrderService는 OrderSocketManager에서 관리됨
      _orderQueueService.start();
    }
    // Step 3: OrderQueue/FirestoreSync services from external providers (wire later)

    ref.onDispose(() {
      logger.d('Order Provider disposing...');
      // 각 관리자들의 dispose 호출
      _timerManager.dispose();
      _socketManager.dispose();
      _queueProcessingTimer?.cancel();

      // 로그아웃 상태가 아닐 때만 서비스 정지
      if (!_isLoggedOut) {
        _orderQueueService.stop();
      }

      _isAudioPlayerDisposed = true;
      _audioPlayer.dispose();
      _batchProcessingTimer?.cancel(); // 배치 처리 타이머 취소 추가
    });

    // 초기 상태 반환 시 설정값 반영
    return OrderState.initial().copyWith(
      isAutoReceipt: initialIsAutoReceipt,
    );
  }

  // Firestore 서비스 리스너는 OrderFirestoreManager로 이동됨

  // Firestore newOrder 추가는 OrderFirestoreManager로 이동됨

  // 소켓 연결 관련 메서드는 OrderSocketManager로 이동됨

  // 설치 유형을 감지하고 적절한 초기화 메서드 호출
  Future<void> _orderDataInitialize() async {
    // 로그아웃 상태인 경우 초기화 건너뛰기
    if (_isLoggedOut) {
      logger.d('로그아웃 상태이므로 설치 유형 감지 및 초기화를 건너뜁니다.');
      return;
    }

    try {
      // 초기 로딩 완료 후 Firestore 리스너 설정
      final storeId = ref.read(storeProvider).value?.storeId ?? '';
      if (storeId.isNotEmpty && !_isInitialLoadComplete) {
        logger.i('[OrderProvider] 서버에서 초기 주문 정보를 가져옵니다.');
        await refreshOrders();
        _isInitialLoadComplete = true; // 초기 로딩 완료 표시
      }
    } catch (e, s) {
      logger.e('설치 유형 감지 및 초기화 중 오류 발생', error: e, stackTrace: s);
    }
  }

  // 설치 유형 감지

  // 초기화 관련 메서드들은 OrderInitialization 클래스로 이동됨

  // 헬퍼 메서드들은 OrderHelperMethods 클래스로 이동됨
  late final OrderHelperMethods _helper = OrderHelperMethods(ref);

  // 초기화 관련 메서드들은 OrderInitialization 클래스로 이동됨

  // 소켓/폴링 관련 메서드들은 OrderSocketPolling 클래스로 이동됨

  // 주문을 UI에 표시할지 여부 확인 (모든 주문 통일 처리)
  bool _shouldShowOrder(OrderModel order) {
    return _helper.shouldShowOrder(order, true); // 모든 주문 표시
  }

  // 주문에 대해 소리/알림/인쇄를 할지 여부 확인 (모든 주문 통일 처리)
  bool _shouldNotifyForOrder(OrderModel order) {
    return _helper.shouldNotifyForOrder(order, true); // 모든 주문에 대해 알림/출력
  }

  // 수신된 주문 처리 전 건너뛰어야 하는지 확인하는 메서드
  Future<bool> _shouldSkipOrderProcessing(OrderModel order) async {
    // 큐 중복 확인은 QueueManager에서 처리됨

    // 뷰 상태에서 해당 주문이 더 최신인지 확인
    final existingOrderIndex =
        state.orders.indexWhere((o) => o.orderId == order.orderId);
    if (existingOrderIndex != -1) {
      final existingOrder = state.orders[existingOrderIndex];

      // 이미 처리된 주문이 더 최신이면 건너뜀
      if (existingOrder.updateTime.isAfter(order.updateTime)) {
        logger.d(
            '주문 ${order.orderId} 처리 건너뜀: 현재 상태(${existingOrder.status})가 더 최신임');
        return true;
      }

      // 같은 상태면 불필요한 처리 방지 (단, NEW 상태는 자동접수 처리를 위해 예외)
      if (existingOrder.status == order.status &&
          order.status != OrderStatus.NEW) {
        logger.d('주문 ${order.orderId} 상태 변경 없음 (${order.status}), UI 업데이트만 진행');
      }
    }

    return false;
  }

  //노티로 들어오는 실시간 주문 처리
  Future<void> _processSingleOrder(OrderModel order) async {
    //logger.d('처리 중인 주문: ${order.orderId}, 상태: ${order.status}');

    // 1. 주문 필터링 및 중복 처리 방지 로직 (조기 종료 조건)
    if (await _shouldSkipOrderProcessing(order)) {
      return;
    }

    // 2. UI 먼저 업데이트하여 체감 지연 최소화
    await _updateOrderInStateList(order);

    // 3. 상태에 따른 주문 처리 로직 수행 (출력, 소리 등)
    await _processOrderByStatus(order);
  }

  // 주문 목록에 업데이트하고 변경 여부 반환
  Future<bool> _updateOrderInStateList(OrderModel order) async {
    try {
      final existingIndex =
          state.orders.indexWhere((o) => o.orderId == order.orderId);
      final bool isNewOrder = existingIndex == -1;
      final String todayDate =
          DateTime.now().toString().substring(0, 10); // 오늘 날짜 문자열

      // 주문의 날짜 필드 확인 (orderTime 사용 및 포맷팅)
      final String orderDate = DateFormat('yyyy-MM-dd').format(order.orderedAt);
      final bool belongsToToday =
          orderDate == todayDate; // <--- orderTime 포맷하여 비교

      if (isNewOrder) {
        // 오늘 날짜에 속하고 && 표시해야 하는 주문만 추가
        if (belongsToToday && _shouldShowOrder(order)) {
          // [FIX] 새 주문이 들어올 때 캐시에 상세 정보가 있다면 유실되지 않도록 병합
          OrderModel orderToAdd = order;
          final cached = _orderDetailCache.get(order.orderId);
          if (!order.isDetailLoaded &&
              cached != null &&
              cached.isDetailLoaded) {
            orderToAdd = order.copyWith(
              menus: cached.menus,
              isDetailLoaded: true,
              kdsOrderType: cached.kdsOrderType,
            );
          }

          // 새 주문이면 목록에 추가
          final updatedOrders = [...state.orders, orderToAdd];
          // 추가 시 정렬 유지 (선택 사항, 필요하다면)
          // sortOrders(updatedOrders, ref.read(orderSortDirectionProvider)); // 필요시 정렬 로직 추가
          state = state.copyWith(
            orders: updatedOrders,
            activeOrderCount: _calculateActiveOrderCount(updatedOrders),
          );

          logger.i(
              '새 주문 목록에 추가 (오늘 날짜): ${orderToAdd.orderId}, 상태: ${orderToAdd.status}');

          return true;
        } else {
          // 오늘 날짜 주문이 아니거나 표시 대상이 아니면 상태 변경 없음
          logger.d(
              '주문 ${order.orderId} (날짜: $orderDate)는 오늘($todayDate) 목록에 추가되지 않음 (신규 처리 중).'); // 로그에도 포맷된 날짜 사용
          return false; // UI 변경 없음
        }
      } else {
        // 기존 주문 업데이트 (오늘 날짜 주문임이 확실)
        // 기존 주문이면 상태 업데이트
        final existingOrder = state.orders[existingIndex];

        // 상태 변경이 있는지 또는 다른 정보 업데이트가 필요한지 확인
        if (existingOrder.status != order.status ||
            existingOrder.updateTime != order.updateTime) {
          // updateTime 등 변경 감지 추가 가능
          logger.d(
              '주문 상태/정보 변경됨: ${order.orderId}, ${existingOrder.status} -> ${order.status}');

          // [FIX] 기존 주문의 상세 정보(메뉴 등)가 있으면 소켓 이벤트 등에 의해 유실되지 않도록 병합
          OrderModel mergedOrder = order;
          if (!order.isDetailLoaded && existingOrder.isDetailLoaded) {
            mergedOrder = order.copyWith(
              menus: existingOrder.menus,
              isDetailLoaded: true,
              kdsOrderType: existingOrder.kdsOrderType,
            );
            // 캐시와도 상태 동기화
            _orderDetailCache.put(mergedOrder.orderId, mergedOrder);
          }

          final updatedOrders = List<OrderModel>.from(state.orders);
          updatedOrders[existingIndex] = mergedOrder; // 최신 정보로 업데이트

          // 필터링은 이미 state.orders에 적용되어 있으므로 다시 적용하지 않음
          state = state.copyWith(
            orders: updatedOrders, // 필터링 없이 단순 업데이트
            activeOrderCount: _calculateActiveOrderCount(updatedOrders),
          );
          // 상태가 변경되었으므로 true 반환 (다른 정보만 변경돼도 UI 갱신 위해 true 반환 고려)
          return true;
        } else {
          logger.d('주문 상태/정보 변경 없음: ${order.orderId}, 상태: ${order.status}');
          return false; // 상태 변경이 없었으므로 false 반환
        }
      }
    } catch (e, s) {
      logger.e('주문 목록 업데이트 중 오류', error: e, stackTrace: s);
      return false;
    }
  }

  // 주문 상태에 따른 처리 로직
  Future<void> _processOrderByStatus(OrderModel order) async {
    try {
      switch (order.status) {
        case OrderStatus.NEW:
          await _processNewOrder(order);
          break;
        case OrderStatus.PREPARING: // 준비중(수락됨)
        case OrderStatus.READY:
        case OrderStatus.DONE:
        case OrderStatus.CANCELLED:
          // KDS 모드에서 READY(PICKUP_REQUESTED) 상태로 변경될 때 출력 지원
          if (order.status == OrderStatus.READY && ref.read(kdsModeProvider)) {
            // KDS 모드: 픽업 요청됨(READY), 출력 시도: ${order.orderId}
            // [FIX] READY 상태에서는 영수증만 출력하고 라벨은 출력하지 않음
            await _outputService.notifyNewOrder(
              order,
              playSound: false,
              printLabel: false, // 라벨 출력 방지
            );
          }

          // KDS 모드에서 접수(PREPARING) 상태로 변경될 때만 오버레이 알림
          if (order.status == OrderStatus.PREPARING &&
              ref.read(kdsModeProvider)) {
            logger.d(
                'KDS 모드: 접수된 주문에 대해 알림 발생 (Sound/Overlay/AppBar): ${order.orderId}');
            ref.read(alertManagerProvider).triggerNewOrderAlert(
                  playSound: true,
                  triggerOverlay: true,
                  triggerAppBar: true,
                );

            // [NEW] KDS 모드: 접수된 주문 유입 시 라벨 자동 출력
            if (ref.read(preferenceServiceProvider).getUseLabelPrinter()) {
              _outputService.printOrderLabels(order);
            }
          }
          // 이미 UI 업데이트는 _updateOrderInStateList에서 수행됨
          logger.d('상태 변경된 주문 처리 완료: ${order.orderId}, 상태: ${order.status}');
          break;
      }
    } catch (e, s) {
      logger.e('주문 상태별 처리 중 오류', error: e, stackTrace: s);
    }
  }

  // NEW 상태 주문 처리 메서드
  Future<void> _processNewOrder(OrderModel order) async {
    logToFile(
        tag: LogTag.API,
        message:
            '[Order] 신규 주문 감지: ${order.orderId} (번호: ${order.shopOrderNo}, 상태: ${order.orderStatus})');

    // 1) 자동접수 우선 처리: 알림 설정(_shouldNotifyForOrder)과 무관하게 동작해야 함
    final bool shouldAutoAccept = state.isAutoReceipt;
    final isKdsMode = ref.read(kdsModeProvider);
    final modeText = isKdsMode ? 'KDS 모드' : '일반 모드';

    logger.d(
        '$modeText: 자동접수 설정 확인: $shouldAutoAccept, 주문: ${order.orderId}, 초기알람플래그: $_shouldPlayInitialAlarm');

    // KDS 모드에서는 NEW를 자동접수/알람 처리하지 않음 (ACCEPTED 상태에서만 알람 처리)
    // 단, MOCK_ 테스트 주문은 정상적으로 파이프라인(자동접수 등)을 타도록 예외 처리
    if (isKdsMode && !order.orderId.startsWith('MOCK_')) {
      logger.d('  NEW 주문은 진행탭/알람 대상 아님 (전체 탭에서만 표시)');
      return;
    }

    // NEW 주문 수신 처리 (일반 모드)
    // AlertManager를 통해 소리, 깜빡임, 오버레이 통합 실행
    // playSound: true (소리 재생), triggerOverlay: true (오버레이), triggerAppBar: true (앱바)
    if (!isKdsMode) {
      ref.read(alertManagerProvider).triggerNewOrderAlert(
            playSound: true,
            triggerOverlay: true,
            triggerAppBar: true,
          );
      logger.d('  NEW 주문 알림 발생 완료 (Sound/Overlay/AppBar)');
    }

    if (shouldAutoAccept) {
      logger.d('$modeText: 자동 접수 진행: ${order.orderId}');
      // 사용자 피드백을 위해 블링크는 즉시 반영 (UI는 NEW 상태로 유지)

      // Firestore 기록은 updateOrderStatus에서 처리하므로 중복 제거
      // 즉시 서버 업데이트로 속도 개선
      Future.microtask(() => updateOrderStatus(order, OrderStatus.PREPARING))
          .then((success) async {
        logger.d(
            '$modeText: updateOrderStatus 결과 - 성공: $success, 주문: ${order.orderId}');
        if (success) {
          logger.d('$modeText: 자동 접수 성공: ${order.orderId}');
          // 접수 성공 시: 프린트만 실행
          logger
              .d('$modeText: processOrderOutput 호출 시작 - 주문: ${order.orderId}');
          await _outputService.notifyNewOrder(order, playSound: false);
          logger.d('$modeText: processOrderOutput 완료 - 주문: ${order.orderId}');

          // 첫 주문 자동접수 성공 시 초기 알람 플래그 비활성화
          if (_shouldPlayInitialAlarm) {
            logger.d('$modeText: 첫 주문 자동접수 성공으로 초기 알람 플래그 비활성화');
            _shouldPlayInitialAlarm = false;
          }
        } else {
          // 실패 시 NEW로 롤백 (안정성)
          try {
            final rollback = order.copyWith(
              status: OrderStatus.NEW,
              orderStatus: '',
              updateTime: DateTime.now(),
            );
            final idx =
                state.orders.indexWhere((o) => o.orderId == order.orderId);
            if (idx != -1) {
              final updated = List<OrderModel>.from(state.orders);
              updated[idx] = rollback;
              state = state.copyWith(
                orders: updated,
                activeOrderCount: _calculateActiveOrderCount(updated),
              );
            }
          } catch (e, s) {
            logger.w('자동접수 실패 롤백 중 오류(무시 가능): ${order.orderId}',
                error: e, stackTrace: s);
          }
          logger.w('$modeText: 자동 접수 실패: ${order.orderId}');
        }
      });

      return; // 자동접수 경로에서는 추가 알림 처리 불필요
    }

    // 2) 수동접수 모드: 알람소리는 이미 위에서 재생했으므로 추가 처리 불필요
    if (!isKdsMode && _shouldNotifyForOrder(order)) {
      logger.d('NEW 주문 처리(수동): ${order.orderId} - 알람소리는 이미 재생됨');

      // [NEW] 수동 접수 모드에서도 신규 주문 수신 시 라벨 자동 출력
      if (ref.read(preferenceServiceProvider).getUseLabelPrinter()) {
        _outputService.printOrderLabels(order);
      }
    }
  }

  // (정리) _processAcceptedKioskOrder: 사용되지 않아 제거

  // 리팩토링 후:
  int _calculateActiveOrderCount(List<OrderModel> orders) {
    return _stateManager.calculateActiveOrderCount(orders);
  }

  // ==========================================
  // refreshOrders 심플화를 위한 헬퍼 메서드들
  // ==========================================

  // 캐시 갱신 함수 제거됨 - 이제 refreshOrders에서 직접 처리

  /// 2. NEW/ACCEPTED 주문 처리
  Future<void> _processNewOrdersWhenRefresh(List<OrderModel> orders) async {
    final newOrders = orders.where((o) => o.status == OrderStatus.NEW).toList();

    logger.d('[Order Processing] NEW: ${newOrders.length}건');

    final isKdsMode = ref.read(kdsModeProvider);

    // NEW 주문 처리 (자동접수만 처리, 알람소리는 _processNewOrder에서 처리)
    if (newOrders.isNotEmpty && !isKdsMode) {
      for (final order in newOrders) {
        if (state.isAutoReceipt) {
          logger.d('[Order Processing] NEW 주문 자동접수: ${order.orderId}');
          // 자동접수 처리
          Future.microtask(
              () => updateOrderStatus(order, OrderStatus.PREPARING));
        } else {
          logger.d(
              '[Order Processing] NEW 주문 수동접수 모드: ${order.orderId} (알람소리는 _processNewOrder에서 처리)');
          // 수동접수 모드에서는 알람소리를 재생하지 않음 (이미 _processNewOrder에서 처리됨)
        }
      }
    }
  }

  // 백그라운드 로딩 함수 제거됨 - refreshOrders에서 순차적으로 처리

  // 백그라운드 로딩 관련 함수들 제거됨 - 이제 refreshOrders에서 순차적으로 처리

  /// 단일 주문 상세정보 로드 (사용 안함 - 배치 처리로 대체)
  /*
  Future<OrderModel?> _loadSingleOrderDetail(String orderId) async {
    try {
      // 이미 캐시에 있는지 확인
      final cached = _orderDetailCache.get(orderId);
      if (cached != null && cached.orderMenuList.isNotEmpty) {
        return cached;
      }

      // API에서 상세정보 가져오기
      final storeId = ref.read(storeProvider).value?.storeId ?? '';
      if (storeId.isEmpty) return null;

      final orderDetail =
          await _apiService.getOrderDetail(orderId, storeId: storeId);

      // 캐시에 저장 (상세정보가 있는 경우만)
      if (orderDetail.orderMenuList.isNotEmpty) {
        _orderDetailCache.put(orderId, orderDetail);
        
        // 개별 상태 업데이트는 배치 처리로 대체됨
        // _updateOrderInStateWithDetails(orderDetail);

        return orderDetail;
      }

      return null;
    } catch (e) {
      logger.d('[Detail Loading] 오류 - ${orderId}: $e');
      return null;
    }
  }
  */

  /// 상태 목록에서 주문을 상세정보로 업데이트 (사용 안함 - 배치 처리로 대체)
  /*
  void _updateOrderInStateWithDetails(OrderModel detailedOrder) {
    final updatedOrders = state.orders.map((order) {
      if (order.orderId == detailedOrder.orderId) {
        // 상세정보를 적용하되, 기존 상태 정보는 보존
        return detailedOrder.copyWith(
          status: order.status,
          orderStusCd: order.orderStatus,
          updateTime: order.updateTime.isAfter(detailedOrder.updateTime)
              ? order.updateTime
              : detailedOrder.updateTime,
        );
      }
      return order;
    }).toList();

    state = state.copyWith(
      orders: updatedOrders,
      activeOrderCount: _calculateActiveOrderCount(updatedOrders),
    );
  }
  */

  /// KDS 등에서 화면에 보이는 중요한 주문들의 상세 정보를 우선 로딩
  Future<void> _fetchDetailsForVisibleOrders() async {
    final isKdsMode = ref.read(kdsModeProvider);
    // KDS 모드가 아니면 자동 로딩 하지 않음 (팝업 클릭 시 로딩)
    if (!isKdsMode) return;

    // 로딩 대상: 상세정보가 없고(로드 안됨) & 화면에 표시되는 주문
    // 정렬 순서대로 상위 N개
    // 로딩 대상: 상세정보가 없고(로드 안됨) & 화면에 표시되는 주문
    // 정렬 순서대로 상위 visibleOrderCount개
    final targetOrders = state.orders
        .where((o) => _shouldShowOrder(o)) // 먼저 표시 대상 필터링
        .take(state.visibleOrderCount) // 현재 보여지는 개수만큼 가져옴 (Pagination)
        .where((o) => !o.isDetailLoaded) // 그 중에서 상세 정보 없는 것만
        .toList();

    logger.d('[OrderProvider] 상세 정보 로딩 필요 주문 수: ${targetOrders.length}');

    if (targetOrders.isEmpty) return;

    logger.d(
        '[OrderProvider] KDS 상위 ${targetOrders.length}개 주문 상세정보 병렬 로딩 시작: ${targetOrders.map((o) => o.orderId).join(", ")}');

    // 병렬 처리 (Future.wait)
    // 5개씩 끊어서 할 수도 있지만, 20개 정도는 한 번에 해도 무방 (HTTP/2 or Keep-Alive)
    // 부하 분산을 위해 map으로 실행
    try {
      await Future.wait(targetOrders.map((o) => fetchOrderDetail(o.orderId)));
      logger.d('[OrderProvider] 병렬 로딩 완료');
    } catch (e) {
      logger.e('[OrderProvider] 병렬 로딩 중 오류 발생', error: e);
    }
  }

  // 중복 호출 방지를 위한 플래그
  bool _isRefreshing = false;

  Future<void> refreshOrders({String? date}) async {
    // 기본 검증
    if (_isLoggedOut) {
      logger.d('[refreshOrders] 로그아웃 상태이므로 건너뜀');
      return;
    }
    if (state.isLoading || _isRefreshing) {
      logger.d(
          '[refreshOrders] 이미 로딩/새로고침 중이므로 건너뜀 (loading: ${state.isLoading}, refreshing: $_isRefreshing)');
      return;
    }
    date = DateTime.now().toString().substring(0, 10);
    logger.d('[refreshOrders] 시작 (날짜: $date)');
    _isRefreshing = true;
    // 새로고침 시 가시 개수 초기화 (12개) - 스크롤 위치 초기화와 함께 동작 예상
    state = state.copyWith(
      isLoading: true,
      error: null,
      visibleOrderCount: 12,
    );

    try {
      final storeId = ref.read(storeProvider).value?.storeId ?? '';
      if (storeId.isEmpty) {
        state = state.copyWith(isLoading: false, error: '매장 ID를 찾을 수 없습니다.');
        _isRefreshing = false; // 오류 시에도 플래그 해제
        return;
      }

      // 1. 주문 목록 조회 (API 호출 1회) - 상세 정보 없음
      final basicOrders =
          await _apiService.getOrders(storeId, startDate: date, endDate: date);
      logger.d('[refreshOrders] API 목록 조회 완료: ${basicOrders.length}건');

      // 2. 기존 캐시나 상태에서 상세 정보 복원 및 병합
      final mergedOrders = <OrderModel>[];
      for (final basicOrder in basicOrders) {
        // 캐시 확인
        final cached = _orderDetailCache.get(basicOrder.orderId);

        if (cached != null && cached.menus.isNotEmpty) {
          // 캐시된 상세 정보가 있으면 병합 (상태는 최신 basicOrder 기준)
          mergedOrders.add(cached.copyWith(
            status: basicOrder.status,
            orderStatus: basicOrder.orderStatus,
            updateTime: basicOrder.orderedAt.isAfter(cached.updateTime)
                ? basicOrder.orderedAt
                : cached
                    .updateTime, // orderedAt or updateTime? basicOrder has updateTime logic inside getOrders? No, it parses createdAt usually.
            // getOrders result maps createdAt to orderedAt.
            // Let's trust basicOrder's status but keep cached menus.
            shopOrderNo: basicOrder.shopOrderNo,
            isDetailLoaded: true,
          ));
        } else {
          // 상세 정보 없음. 그냥 추가 (isDetailLoaded=false 상태)
          mergedOrders.add(basicOrder);
        }
      }

      // 3. 필터링 및 정렬
      final displayOrders = mergedOrders.where(_shouldShowOrder).toList();

      // 전체 정렬 (오래된 주문 우선 - 오름차순)
      displayOrders.sort((a, b) {
        final numA = int.tryParse(a.shopOrderNo) ?? 0;
        final numB = int.tryParse(b.shopOrderNo) ?? 0;
        if (numA != numB) return numA.compareTo(numB);
        return a.updateTime.compareTo(b.updateTime);
      });

      // 4. State 업데이트 (1차: 목록만 빠르게 표시)
      state = state.copyWith(
        orders: displayOrders,
        isLoading: false,
        activeOrderCount: _calculateActiveOrderCount(displayOrders),
      );

      // 시퀀스 번호 갱신
      if (displayOrders.isNotEmpty) {
        _updateLastKnownOrderSequence(displayOrders);
      }

      logger.d(
          '[refreshOrders] 목록 업데이트 완료 (${displayOrders.length}건). 상세 정보 로딩 시작...');

      // 5. NEW/ACCEPTED 주문 처리 (자동접수 등) - 상세 정보가 필요할 수 있음
      // 자동접수는 메뉴 정보가 필요 없을 수도 있지만, 출력 시 필요함.
      // _processNewOrdersWhenRefresh 내부 로직 확인 필요.
      // 일단 목록 갱신 후, KDS 모드면 상세 로딩 트리거

      await _fetchDetailsForVisibleOrders();

      // 6. NEW/ACCEPTED 처리 (상세 로딩된 후 처리하는 것이 안전하지만, 비동기로 둠)
      // 만약 자동접수 로직이 메뉴 정보를 필요로 한다면 _processNewOrdersWhenRefresh에서
      // 개별적으로 fetchOrderDetail을 await해야 함.
      // 현재는 그냥 호출.
      await _processNewOrdersWhenRefresh(displayOrders);

      // 7. blink 상태 업데이트 (자동 동기화되므로 활성 주문 수 계산 및 필요한 경우 사운드 중지만 수행)
      final activeCount = _calculateActiveOrderCount(displayOrders);
      if (activeCount == 0) {
        stopBlinking();
      }
    } catch (e, s) {
      logger.e('[refreshOrders] 오류 발생', error: e, stackTrace: s);
      state = state.copyWith(isLoading: false, error: e.toString());
    } finally {
      _isRefreshing = false; // 완료 시 플래그 해제
    }
  }

  // ==========================================
  // 기존 메서드들 (심플화된 refreshOrders에서 사용 안함)
  // ==========================================

  // 앱 초기화시 알람 처리 (사용 안함)
  /*
  void _handleInitialAlarm(List<OrderModel> orders) {
    final isKdsMode = ref.read(kdsModeProvider);
    final modeText = isKdsMode ? 'KDS 모드' : '일반 모드';

    // 앱 시작 시 출력/알람 처리는 _handleAppStartupPrintAndAlarm에서 처리하므로
    // 여기서는 초기 알람 플래그만 비활성화
    _shouldPlayInitialAlarm = false;
    logger.d('[초기 알람] $modeText: 초기 알람 플래그 비활성화 완료');
  }
  */

  // Firestore 동기화는 OrderFirestoreManager로 이동됨

  // OrderStatus 변환은 OrderFirestoreManager로 이동됨

  // --- Public Methods --- (Exposed to UI or other providers)

  // --- Pagination Logic [NEW] ---

  // 더 많은 주문 로드하기 (스크롤 시 호출)
  Future<void> loadMoreOrders() async {
    if (state.isLoading) return;

    final currentCount = state.visibleOrderCount;
    final totalCount = state.orders.length;

    if (currentCount >= totalCount) {
      logger.d('[OrderProvider] 모든 주문이 로드되었습니다. ($currentCount / $totalCount)');
      return;
    }

    final nextCount = currentCount + 5; // 5개씩 추가 로드
    logger.d('[OrderProvider] 주문 추가 로드: $currentCount -> $nextCount');

    state = state.copyWith(visibleOrderCount: nextCount);

    // 새로 추가된 주문들의 상세 정보 로딩 트리거
    await _fetchDetailsForVisibleOrders();
  }

  Future<bool> cancelOrder(String orderId) async {
    final storeId = ref.read(storeProvider).value?.storeId ?? '';
    if (storeId.isEmpty) {
      logger.e('Cannot cancel order: Store ID not found.');
      state = state.copyWith(error: '매장 ID 없어 주문 취소 불가');
      return false;
    }
    logger.d('Cancelling order: $orderId');
    try {
      // API 호출 전 소켓 이벤트 무시 등록
      SocketEventSuppressor().add(orderId, appfit_core.OrderEventType.orderCancelled.value);

      final success = await _apiService.cancelOrder(orderId);
      if (success) {
        // Firestore 상태 업데이트 (Removed)
        // final firestoreService = ref.read(firestoreStatusServiceProvider); ...

        // 주문 상태 업데이트는 _processSingleOrder에 위임하기 위해 큐에 넣음
        // API에서 주문 상세 정보를 가져와서 큐에 넣어야 할 수도 있음 (만약 orderId만 넘어온다면)
        // 여기서는 일단 로컬 상태 기반으로 취소 상태 모델 생성 시도
        final index = state.orders.indexWhere((o) => o.orderId == orderId);
        OrderModel? orderToQueue;
        if (index != -1) {
          final currentOrder = state.orders[index];
          orderToQueue = currentOrder.copyWith(
            status: OrderStatus.CANCELLED,
            orderStatus: "9001", // Cancelled status code
            updateTime: DateTime.now(),
          );

          // 즉시 상태 업데이트 제거 - 큐 처리를 통해 상태 반영 유도
          /*
          final updatedOrders = List<OrderModel>.from(state.orders);
          updatedOrders[index] = orderToQueue;
          state = state.copyWith(
            orders: updatedOrders,
            activeOrderCount: _calculateActiveOrderCount(updatedOrders),
          );
          */
          logger.d(
              "Order cancellation for today's order $orderId - update via queue."); // 로그 메시지 수정
        } else {
          // If not in state, try fetching details to create a model for the queue
          try {
            final details =
                await _apiService.getOrder(orderId, storeId: storeId);
            // 주문 상태 업데이트
            orderToQueue = details.copyWith(
              status: OrderStatus.CANCELLED,
              orderStatus: '9001', // 취소 상태 코드
              updateTime: DateTime.now(),
            );
            logger.w(
                "Order $orderId not in state, fetched details for cancellation queue.");
          } catch (e) {
            logger.e(
                "Failed to fetch details for cancelled order $orderId, cannot queue state update.");
          }
        }

        if (orderToQueue != null) {
          queueOrderExternal(orderToQueue);
          _updateOrderInCache(
              orderId, OrderStatus.CANCELLED, "9001"); // Update cache
          logger.d("Order cancellation queued locally: $orderId");
        }

        // 취소 영수증 출력 로직 (API 성공 후 즉시 실행)
        try {
          await _outputService.printCancelReceiptById(
            orderId: orderId,
            storeId: storeId,
          );
        } catch (printError, stackTrace) {
          if (printError is Exception &&
              printError.toString().contains("키오스크 주문은 현재 표시되지 않도록 설정되었습니다")) {
            logger.w(
                "Cannot print cancellation receipt for hidden kiosk order $orderId.");
          } else {
            logger.e('Error printing cancelled order receipt',
                error: printError, stackTrace: stackTrace);
          }
        }

        return true;
      } else {
        logger.e('Server failed to cancel order $orderId');
        state = state.copyWith(error: '서버에서 주문 취소 실패 (orderId: $orderId)');
        return false;
      }
    } catch (e, s) {
      logger.e('Error calling cancel order API', error: e, stackTrace: s);
      state = state.copyWith(error: '주문 취소 API 오류: $e');
      return false;
    }
  }

  void stopBlinking() async {
    // SoundService를 통해 사운드 중지
    try {
      await ref.read(soundAppServiceProvider).stop();
      logger.d('Notification sound stopped manually.');
    } catch (e) {
      logger.w('Error stopping sound service: $e');
    }

    ref.read(blinkStateProvider.notifier).stopBlinking();
  }

  // 리팩토링 후:
  Future<OrderModel> getOrderDetail(String orderId, String storeId) async {
    return await _cacheManager.getOrderDetail(orderId, storeId, state.orders);
  }

  bool hasDetailCache(String orderId) {
    return _cacheManager.hasDetailCache(orderId);
  }

  Future<void> updateAutoReceipt(bool value) async {
    await _settingsManager.updateAutoReceipt(value);
    state = state.copyWith(isAutoReceipt: value);
    logger.d('updateAutoReceipt 완료 - 상태 업데이트됨: ${state.isAutoReceipt}');
  }

  void updateSoundSettings() {
    _settingsManager.updateSoundSettings();
    _settingsManager.applyAudioPlayerSettings(_audioPlayer);
    // SoundService의 설정도 업데이트
    ref.read(soundAppServiceProvider).reloadSettings();
    logger
        .d('Sound settings reloaded for both OrderProvider and SoundService.');
  }

  Future<({int successCount, int failCount, String? errorMessage})>
      completeReadyOrders() async {
    state = state.copyWith(isLoading: true, error: null);

    final storeId = ref.read(storeProvider).value?.storeId;
    if (storeId == null || storeId.isEmpty) {
      logger.e('Cannot complete orders: Store ID not found.');
      state = state.copyWith(isLoading: false);
      return (successCount: 0, failCount: 0, errorMessage: '매장 ID를 찾을 수 없습니다.');
    }

    // Use the already filtered list from the state
    final readyOrders = state.orders
        .where((order) => order.status == OrderStatus.READY)
        .toList();

    if (readyOrders.isEmpty) {
      logger.d('No orders ready for bulk completion.');
      state = state.copyWith(isLoading: false);
      return (successCount: 0, failCount: 0, errorMessage: null);
    }

    // 소켓 이벤트 중복 처리 방지: 모든 READY 주문의 ORDER_DONE 이벤트 사전 억제
    for (final order in readyOrders) {
      SocketEventSuppressor()
          .add(order.orderId, appfit_core.OrderEventType.orderDone.value);
    }

    logger
        .d('Starting bulk completion processing: ${readyOrders.length} orders');

    try {
      // AppFit (v2) - 서버 측 일괄 처리 API 사용
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final response =
          await _apiService.bulkCompleteOrders(storeId, from: today, to: today);

      final data = response['data'] as Map<String, dynamic>;
      final int successCount = data['updateSuccessCount'] ?? 0;
      final int failCount = data['updateFailCount'] ?? 0;

      logToFile(
          tag: LogTag.API,
          message:
              'AppFit Bulk completion result: Success $successCount, Fail $failCount');

      if (failCount == 0 && successCount > 0) {
        // [전체 성공] 낙관적 업데이트: 스냅샷의 모든 READY 주문 → DONE 즉시 반영
        final updatedOrders = state.orders.map((order) {
          if (readyOrders.any((r) => r.orderId == order.orderId)) {
            return order.copyWith(
              status: OrderStatus.DONE,
              orderStatus: '2020',
              updateTime: DateTime.now(),
            );
          }
          return order;
        }).toList();
        // isLoading = false 먼저 설정 → refreshOrders() 차단 해소 (핵심 버그 수정)
        state = state.copyWith(orders: updatedOrders, isLoading: false);
        await refreshOrders();
      } else if (successCount > 0) {
        // [부분 실패] 어느 주문이 성공했는지 알 수 없으므로 낙관적 업데이트 없이 서버 동기화
        state = state.copyWith(isLoading: false);
        await refreshOrders();
      } else {
        // [전체 실패] 상태 변경 없음
        state = state.copyWith(isLoading: false);
      }

      return (
        successCount: successCount,
        failCount: failCount,
        errorMessage:
            failCount > 0 ? '일부($failCount건) 주문 완료 처리에 실패했습니다.' : null,
      );
    } catch (e, stackTrace) {
      logger.e('Critical error during bulk completion',
          error: e, stackTrace: stackTrace);

      logToFile(
          tag: LogTag.API,
          message: 'Critical error during bulk completion: $stackTrace');

      state = state.copyWith(isLoading: false);

      return (
        successCount: 0,
        failCount: readyOrders.length,
        errorMessage: '일괄 완료 처리 중 오류 발생: 시스템 오류로 인해 처리하지 못했습니다.',
      );
    }
  }

  // --- Private Helper Methods --- (Restored missing methods & removed mounted)

  // 리팩토링 후:
  void _loadSoundSettings() {
    _settingsManager.loadSoundSettings();
    _settingsManager.applyAudioPlayerSettings(_audioPlayer);
  }

  //주기적으로 주문 폴링 - TimerManager로 위임 (긴급모드 ON이면 즉시 10s 적용)
  void _setupPollingTimer() {
    if (_preferenceService.getForceSocketReconnect()) {
      _timerManager.restartPolling(OrderTimerManager.socketDisconnectedIntervalSeconds);
      logToFile(tag: LogTag.WEBSOCKET, message: '[긴급모드] 폴링 ${OrderTimerManager.socketDisconnectedIntervalSeconds}s 복원');
    } else {
      _timerManager.setupPollingTimer(_isLoggedOut);
    }
  }

  //주문상세, 프린트내역 캐시 정리 타이머 - TimerManager로 위임
  void _setupCacheCleanupTimer() {
    _timerManager.setupCacheCleanupTimer();
  }

  void _scheduleMidnightRefresh() {
    _timerManager.scheduleMidnightRefresh();
  }

  // 소켓 변경사항 리스닝은 OrderSocketManager로 이동됨

  // 소켓 구독 관련 메서드들은 OrderSocketManager로 이동됨

  // 배치 처리 관련 메서드들은 OrderQueueManager로 이동됨

  // 외부 서비스용 얇은 래퍼들 - QueueManager로 위임
  void queueOrderExternal(OrderModel order) {
    // 캐시 확인 (중복 방지) - 상태 변경은 허용하기 위해 ID+Status 조합 키 사용
    final cacheKey = '${order.orderId}_${order.status}';

    if (_processedOrderCache.contains(cacheKey)) {
      logger.d(
          '[OrderProvider] Order $cacheKey already processed (Cache Hit). Skipping queue.');
      return;
    }
    _processedOrderCache.add(cacheKey);
    _queueManager.queueOrder(order);
  }

  List<OrderModel> moveQueueToBatchExternal() =>
      _queueManager.moveQueueToBatch();
  void sortBatchQueueByOrderNumberExternal() =>
      _queueManager.sortBatchQueueByOrderNumber();
  bool get isBatchCollectingExternal => _queueManager.isBatchCollecting;
  bool get hasPendingExternal => _queueManager.hasPending;
  void processNextOrdersInBatchExternal() =>
      _queueManager.processNextOrdersInBatch();

  // 폴링으로 주기적 주문 처리
  Future<void> _pollNewOrders() async {
    if (_isLoggedOut) {
      logger.i('로그아웃 상태이므로 폴링을 건너뜁니다.');
      return;
    }

    final storeId = ref.read(storeProvider).value?.storeId ?? '';
    if (storeId.isEmpty) return;

    final today = DateTime.now().toString().substring(0, 10);

    try {
      final newOrders = await _apiService.getNewOrders(storeId,
          startDate: today, endDate: _lastKnownOrderSequence);

      if (newOrders.isNotEmpty) {
        logger.i('폴링으로 주문 수신: ${newOrders.length}건.');
        _mergeOrdersIntoUnfilteredList(newOrders);
        _updateLastKnownOrderSequence(
            _unfilteredOrders); // Update sequence from full list
        _processPollingNewOrders(newOrders);
      }
    } catch (e, s) {
      logger.e('Error polling new orders', error: e, stackTrace: s);
    }
  }

  // 폴링된 주문을 _unfilteredOrders에 병합하는 헬퍼 메서드
  void _mergeOrdersIntoUnfilteredList(List<OrderModel> newOrders) {
    if (newOrders.isEmpty) return;

    final Map<String, OrderModel> orderMap = {
      for (var order in _unfilteredOrders) order.orderId: order
    };

    for (var newOrder in newOrders) {
      // 최신 정보로 업데이트 (같은 ID가 있으면 교체, 없으면 추가)
      orderMap[newOrder.orderId] = newOrder;
    }

    _unfilteredOrders = orderMap.values.toList();
    // 선택 사항: 병합 후 정렬 (필요하다면)
    // _unfilteredOrders.sort((a, b) => b.updateTime.compareTo(a.updateTime));
  }

  void _updateLastKnownOrderSequence(List<OrderModel> orders) {
    if (orders.isEmpty) return;
    // Ensure the list passed here is the unfiltered list when needed
    final ordersBySequence = [...orders];
    // ordersBySequence 정렬 로직 수정: simpleNum을 int로 변환하여 비교
    ordersBySequence.sort((a, b) {
      try {
        final numA = int.parse(a.shopOrderNo);
        final numB = int.parse(b.shopOrderNo);
        return numB.compareTo(numA); // 내림차순 정렬
      } catch (e) {
        // 파싱 오류 발생 시 처리 (예: 오류 로그, 기본값 반환 등)
        // 여기서는 오류 발생 시 순서 변경하지 않음 (0 반환)
        logger.w(
            'Error parsing simpleNum during sort: ${a.shopOrderNo} or ${b.shopOrderNo}');
        return 0;
      }
    });

    // simpleNum 비교 로직 강화 (숫자 변환 오류 방지)
    int maxSimpleNum = 0;
    try {
      maxSimpleNum = int.parse(_lastKnownOrderSequence);
    } catch (_) {}

    // 정렬된 목록의 첫 번째 요소를 사용할 수 있음 (단, 파싱 오류 없을 때)
    if (ordersBySequence.isNotEmpty) {
      try {
        final currentMaxNum = int.parse(ordersBySequence.first.shopOrderNo);
        if (currentMaxNum > maxSimpleNum) {
          maxSimpleNum = currentMaxNum;
        }
      } catch (e) {
        logger.w(
            'Invalid simpleNum in first element after sort: ${ordersBySequence.first.shopOrderNo}');
        // fallback to iterating if first element parse fails
        for (final order in ordersBySequence) {
          try {
            final currentSimpleNum = int.parse(order.shopOrderNo);
            if (currentSimpleNum > maxSimpleNum) {
              maxSimpleNum = currentSimpleNum;
            }
          } catch (e) {
            logger.w(
                'Invalid simpleNum found while updating sequence: ${order.shopOrderNo}');
          }
        }
      }
    }

    final newSequence = maxSimpleNum.toString();
    if (_lastKnownOrderSequence != newSequence) {
      _lastKnownOrderSequence = newSequence;
      logger.d('_lastKnownOrderSequence updated to: $_lastKnownOrderSequence');
    } else {
      logger.d('_lastKnownOrderSequence remains: $_lastKnownOrderSequence');
    }
  }

  // --- Small helpers for readability ---
  // (reserved for later refactor helpers - removed to keep lints clean)

  void _updateOrderInCache(
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
        // logger.d('Updated order detail cache for $orderId'); // Can be verbose
      }
    }
  }

  // DEPRECATED: moved to SoundService - 제거됨

  Future<bool> updateOrderStatus(OrderModel orderModel, OrderStatus newStatus,
      {String? readyTime}) async {
    final storeId = ref.read(storeProvider).value?.storeId ?? '';
    if (storeId.isEmpty) {
      logger.e('Cannot update order status: Store ID not found.');
      state = state.copyWith(error: '매장 ID를 찾을 수 없어 상태 업데이트 불가');
      return false;
    }

    final orderId = orderModel.orderId;
    final displayNum = orderModel.displayNum;

    // 이미 해당 상태인 경우 업데이트 건너뛰기
    final existingOrder = state.orders.firstWhere(
      (order) => order.orderId == orderId,
      orElse: () => orderModel,
    );
    logger.d(
        'updateOrderStatus 상태 확인 - 주문: $orderId, 현재 상태: ${existingOrder.status}, 요청 상태: $newStatus');
    if (existingOrder.status == newStatus) {
      logger
          .i('Order $orderId is already in status $newStatus, skipping update');
      return true;
    }

    try {
      // 소켓 이벤트 무시 등록
      String? expectedEventType;
      switch (newStatus) {
        case OrderStatus.PREPARING:
          expectedEventType = appfit_core.OrderEventType.orderAccepted.value;
          break;
        case OrderStatus.READY:
          expectedEventType = appfit_core.OrderEventType.orderPickupRequested.value;
          break;
        case OrderStatus.DONE:
          expectedEventType = appfit_core.OrderEventType.orderDone.value;
          break;
        case OrderStatus.CANCELLED:
          expectedEventType = appfit_core.OrderEventType.orderCancelled.value;
          break;
        default:
          break;
      }

      if (expectedEventType != null) {
        SocketEventSuppressor().add(orderId, expectedEventType);
      }

      logger.d(
          'updateOrderStatus API 호출 시작 - storeId: $storeId, orderId: $orderId, newStatus: $newStatus');

      bool success = false;

      // MOCK 주문의 경우 API 호출을 무시하고 성공으로 간주
      if (orderId.startsWith('MOCK_')) {
        logger.d('MOCK 주문이므로 API 호출을 건너뛰고 성공으로 처리합니다: $orderId');
        success = true;
      } else {
        success = await _apiService.updateOrderStatus(
            storeId, newStatus, orderId,
            cancelReason: readyTime);
      }

      logger.d('API 호출 결과 - 성공: $success, orderId: $orderId');

      if (success) {
        // Find the order in the *current state* to update it
        final index = state.orders.indexWhere((o) => o.orderId == orderId);
        final statusCode = '';

        // 1. 상태 변경된 주문 모델 생성
        OrderModel orderToQueue;
        if (index != -1) {
          final currentOrderInState = state.orders[index];
          orderToQueue = currentOrderInState.copyWith(
            orderStatus: statusCode,
            status: newStatus,
            updateTime: DateTime.now(),
          );
        } else {
          orderToQueue = orderModel.copyWith(
            orderStatus: statusCode,
            status: newStatus,
            updateTime: DateTime.now(),
          );
          logger.w(
              'Order $orderId not found in current state list during status update, using provided model for queue.');
        }

        // 2. 큐에 추가 (비동기 처리를 위함)
        queueOrderExternal(orderToQueue);
        logger.d(
            'Order status update queued locally: ${orderToQueue.orderId} to ${orderToQueue.status}');

        // 3. 캐시 업데이트
        _updateOrderInCache(orderId, newStatus, statusCode);

        // 4. 즉시 UI 업데이트 (사용자 반응성 향상을 위한 미리보기 업데이트)
        _performImmediateUIUpdate(orderToQueue, index);

        return true;
      } else {
        logToFile(
            tag: LogTag.SYSTEM,
            message:
                '주문 상태 업데이트 실패: displayNum=$displayNum, orderId=$orderId, statusCd=${newStatus.name}');
        logger.w('Server failed to update order status for $orderId');
        state = state.copyWith(error: '서버에서 주문 상태 업데이트 실패 (orderId: $orderId)');
        return false;
      }
    } catch (e, s) {
      // ApiService에서 이미 [API] ERROR 로그를 남겼을 것이므로, 여기서는 경고 수준으로 기록
      logger.e('[OrderProvider] updateOrderStatus 오류', error: e, stackTrace: s);
      if (e is ApiException) rethrow;
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  // 성능 최적화: Map 인덱스 관리 메서드들
  void _updateOrderIndexMap(List<OrderModel> orders) {
    _orderIndexMap.clear();
    for (int i = 0; i < orders.length; i++) {
      _orderIndexMap[orders[i].orderId] = i;
    }
  }

  // 상태 및 UI 업데이트 헬퍼 메서드
  void _updateStateAndUI(List<OrderModel> updatedOrders, String mode) {
    final filtered = updatedOrders.where(_shouldShowOrder).toList();
    final newActive = _calculateActiveOrderCount(filtered);

    state = state.copyWith(
      orders: filtered,
      activeOrderCount: newActive,
    );

    _updateOrderIndexMap(filtered);
    _blinkService.updateActiveCount(newActive);
    _blinkService.stopIfZero(newActive);

    logger.d(
        '[OrderProvider][$mode] Firestore updates applied. orders=${filtered.length}, activeCount=$newActive');
  }

  int _findOrderIndex(String orderId) {
    return _orderIndexMap[orderId] ?? -1;
  }

  // UI 즉시 업데이트를 위한 메서드 추출 (역할 분리)
  void _performImmediateUIUpdate(OrderModel updatedOrder, int existingIndex) {
    // 디버깅을 위한 로그 추가 - 업데이트 전
    logger.d(
        '_performImmediateUIUpdate 시작 - 업데이트 전 주문 수: ${state.orders.length}');
    logger.d(
        '업데이트 전 주문 ID 목록: ${state.orders.map((o) => '${o.orderId}(${o.status})').join(', ')}');
    logger.d(
        '업데이트할 주문: ${updatedOrder.orderId}(${updatedOrder.status}), 인덱스: $existingIndex');

    // KDS 모드에서 상태 변경 시 안정적인 UI 업데이트를 위한 처리
    final isKdsMode = ref.read(kdsModeProvider);
    final isStatusTransition = existingIndex != -1 &&
        state.orders[existingIndex].status != updatedOrder.status;

    if (existingIndex != -1) {
      // 기존 주문 업데이트 - 깊은 복사로 안전하게 처리
      final updatedOrders =
          state.orders.map((order) => order.copyWith()).toList();
      updatedOrders[existingIndex] = updatedOrder;

      // 정렬 (오래된 주문이 앞으로/왼쪽으로 오도록 오름차순) - 작업 순서 보장
      updatedOrders.sort((a, b) {
        final numA = int.tryParse(a.shopOrderNo) ?? 0;
        final numB = int.tryParse(b.shopOrderNo) ?? 0;
        if (numA != numB) return numA.compareTo(numB);
        return a.updateTime.compareTo(b.updateTime);
      });

      // UI 즉시 업데이트 (큐 중복 방지를 위해 큐 추가 제거)
      logger.d('UI 즉시 업데이트 및 정렬: ${updatedOrder.orderId}');

      // KDS 모드에서 상태 전환 시 안정적인 UI 업데이트
      if (isKdsMode && isStatusTransition) {
        logger.d(
            'KDS 모드: 상태 전환 시 안정적인 UI 업데이트 - ${updatedOrder.orderId}: ${state.orders[existingIndex].status} -> ${updatedOrder.status}');

        // 상태 변경을 한 번에 처리하여 UI 깜빡임 방지
        state = state.copyWith(
          orders: updatedOrders,
          activeOrderCount: _calculateActiveOrderCount(updatedOrders),
        );
      } else {
        // 일반적인 업데이트
        state = state.copyWith(
          orders: updatedOrders,
          activeOrderCount: _calculateActiveOrderCount(updatedOrders),
        );
      }

      logger.d(
          '주문 상태 즉시 화면 업데이트: ${updatedOrder.orderId}, 상태: ${updatedOrder.status}');
    } else if (!state.orders.any((o) => o.orderId == updatedOrder.orderId)) {
      // 상태 목록에 없는 경우 목록에 추가 (필터링은 이미 state.orders에 적용되어 있으므로 다시 적용하지 않음)
      final updatedOrders = [updatedOrder, ...state.orders];

      // 정렬 (오래된 주문이 앞으로/왼쪽으로 오도록 오름차순) - 작업 순서 보장
      updatedOrders.sort((a, b) {
        final numA = int.tryParse(a.shopOrderNo) ?? 0;
        final numB = int.tryParse(b.shopOrderNo) ?? 0;
        if (numA != numB) return numA.compareTo(numB);
        return a.updateTime.compareTo(b.updateTime);
      });

      // UI 즉시 업데이트 (큐 중복 방지를 위해 큐 추가 제거)
      logger.d('새 주문 UI 즉시 추가 및 정렬: ${updatedOrder.orderId}');

      state = state.copyWith(
        orders: updatedOrders,
        activeOrderCount: _calculateActiveOrderCount(updatedOrders),
      );
      logger.d(
          '주문 상태 변경 후 즉시 목록에 추가 및 정렬: ${updatedOrder.orderId}, 상태: ${updatedOrder.status}');
    }

    // 디버깅을 위한 로그 추가 - 업데이트 후
    logger.d('_performImmediateUIUpdate 완료 - 현재 주문 수: ${state.orders.length}');
    logger.d(
        '업데이트 후 주문 ID 목록: ${state.orders.map((o) => '${o.orderId}(${o.status})').join(', ')}');
  }

  // 폴링으로 주문 처리 시 중복 체크를 위한 메서드
  void _processPollingNewOrders(List<OrderModel> newOrders) async {
    logger.d('주문 ${newOrders.length}건 처리 중...');

    // 큐 정보는 QueueManager에서 관리됨
    logger.d('주문 처리 시작: ${newOrders.length}건');

    // 주문 처리 중복 방지를 위한 이미 처리된 ID 세트 (이번 배치 내에서)
    final Set<String> processedOrderIds = {};

    // 소켓 연결 상태 확인 (폴링으로 주문이 감지되었을 때 소켓 상태를 죽이지 않기 위함)
    final isSocketConnected = ref.read(appFitNotifierServiceProvider).isConnected;
    bool latencyDetected = false;

    for (final order in newOrders) {
      // 1. 글로벌 캐시 확인 (소켓 등 이미 처리된 주문인지 확인)
      if (_processedOrderCache.contains(order.orderId)) {
        // 이미 처리된 주문은 로그만 남기고 스킵 (너무 많으면 로그 생략 가능)
        continue;
      }

      // 2. 이번 배치 내 중복 확인
      if (processedOrderIds.contains(order.orderId)) {
        continue;
      }
      processedOrderIds.add(order.orderId);

      // 3. 소켓 연결 상태인데 폴링으로 새로운 주문이 발견된 경우 (지연 감지)
      if (isSocketConnected) {
        logger.w(
            '[OrderProvider] Socket latency detected: Polling found new order ${order.orderId} while socket is connected.');
        latencyDetected = true;
        // 여기서 소켓을 재연결하지 않음 (기존 로직 개선)
      }

      // 큐에 추가 (중복 체크 후) - 외부 큐 서비스 경유
      // queueOrderExternal 내부에서도 캐시 체크를 하지만, 여기서 명시적으로 호출
      queueOrderExternal(order);

      // 즉시 상태 반영이 필요한 주문 처리 (NEW->ACCEPTED 자동 접수 등)
      if (order.status == OrderStatus.NEW) {
        // KDS 모드에서는 NEW에 대해 아무 처리도 하지 않음 (전체 탭에서만 보이도록)
        if (ref.read(kdsModeProvider)) {
          continue;
        }
        // 이미 처리된 주문은 건너뜀 (위에서 processedOrderIds 체크 했으므로 중복이지만 안전상 유지하거나 제거 가능. 여기선 제거)
        // if (processedOrderIds.contains(order.orderId)) { ... } -> Removed redundant check

        processedOrderIds.add(order.orderId);

        // 자동 접수 조건 확인 (설정 기반)
        final bool shouldAutoAccept = state.isAutoReceipt;
        if (shouldAutoAccept) {
          logger.d('새로고침으로 받은 주문 자동 접수 시작: ${order.orderId}');

          // 1) 즉시 UI 상태 업데이트 (ACCEPTED 상태로 변경)
          final acceptedOrder = order.copyWith(
            status: OrderStatus.PREPARING,
            orderStatus: '',
            updateTime: DateTime.now(),
          );

          // UI 상태 즉시 업데이트
          final existingIndex =
              state.orders.indexWhere((o) => o.orderId == order.orderId);
          if (existingIndex != -1) {
            final updatedOrders = List<OrderModel>.from(state.orders);
            updatedOrders[existingIndex] = acceptedOrder;
            state = state.copyWith(
              orders: updatedOrders,
              activeOrderCount: _calculateActiveOrderCount(updatedOrders),
            );
            logger.d('자동접수 주문 UI 상태 즉시 업데이트: ${order.orderId} -> ACCEPTED');
          }

          // 2) 비동기 API 호출 (UI는 이미 업데이트됨)
          Future.microtask(
                  () => updateOrderStatus(order, OrderStatus.PREPARING))
              .then((success) async {
            if (success) {
              logger.d('새로고침 주문 자동 접수 성공: ${order.orderId}');
              // 접수 성공 시: 프린트만 실행 (큐를 통해 처리)
              _outputQueueService.add(acceptedOrder, playSound: true);

              // 플랫폼 알림 (앱이 백그라운드일 때)
              // 플랫폼 알림 (앱이 백그라운드일 때)
              ref.read(alertManagerProvider).triggerNewOrderAlert(
                    playSound: true,
                    triggerOverlay: true,
                    triggerAppBar: true,
                  );
            } else {
              logger.w('새로고침 주문 자동 접수 실패: ${order.orderId}');
              // 실패 시 NEW 상태로 롤백
              final rollbackOrder = order.copyWith(
                status: OrderStatus.NEW,
                orderStatus: '',
                updateTime: DateTime.now(),
              );
              if (existingIndex != -1) {
                final rollbackOrders = List<OrderModel>.from(state.orders);
                rollbackOrders[existingIndex] = rollbackOrder;
                state = state.copyWith(
                  orders: rollbackOrders,
                  activeOrderCount: _calculateActiveOrderCount(rollbackOrders),
                );
                logger.w('자동접수 실패로 상태 롤백: ${order.orderId} -> NEW');
              }
            }
          });

          // 큐 관리는 QueueManager에서 처리됨
          logger.d('자동접수 처리 완료: ${order.orderId}');
          continue; // 다음 주문으로 넘어감
        } else {
          // 자동 접수가 아닌 경우
          // 이 주문이 새로고침/폴링을 통해 '새롭게' 발견된 것인지 확인
          // (즉, 현재 state.orders 목록에 아직 없는지 확인)
          final isTrulyNewToThisProvider =
              !state.orders.any((o) => o.orderId == order.orderId);
          if (isTrulyNewToThisProvider) {
            // 상태 목록에 없었으므로 진짜 '새로운' NEW 주문임 -> 알림 재생
            logger.d('새로고침/폴링으로 처음 발견된 NEW 주문 알림 재생: ${order.orderId}');
            // 블링크 시작 추가
            _updateBlinkState();

            // 알람소리는 notifyNewOrder에서 처리하므로 여기서는 재생하지 않음
            // 플랫폼 알림 (앱이 백그라운드일 때)
            ref.read(alertManagerProvider).triggerNewOrderAlert(
                  playSound: true,
                  triggerOverlay: true,
                  triggerAppBar: true,
                );
          } else {
            // 이미 상태 목록에 존재하는 주문 (NEW 상태일 것임) -> 알림 재생 안함
            logger.d('새로고침/폴링 시 이미 존재하는 NEW 주문 알림 건너뜀: ${order.orderId}');
          }
        }
      } else if (order.status == OrderStatus.PREPARING) {
        // PREPARING 상태 주문 처리 - 앱 시작 시 이미 처리되었으므로 건너뜀
        logger.d('PREPARING 주문 확인: ${order.orderId} - 앱 시작 시 이미 처리됨으로 건너뜀');

        // 앱 시작 시 _handleAppStartupPrintAndAlarm에서 이미 처리되었으므로
        // 여기서는 추가 프린트/알람 처리하지 않음
        continue;
      }

      // 즉시 UI 상태 업데이트는 하지 않음 (refreshOrders에서 _mergeWithExistingDetails로 처리됨)
      // _performImmediateUIUpdate(order, existingIndex);
    }

    // 폴링 로직 개선: 소켓이 연결되어 있지 않은 상태에서 폴링으로 주문을 찾았다면,
    // 소켓 연결에 문제가 있을 수 있으므로 재연결 시도 (기존 로직 유지하되 조건부 실행)
    if (!isSocketConnected && newOrders.isNotEmpty && !latencyDetected) {
      logger.i(
          '[OrderProvider] Polling found orders while socket disconnected. Triggering socket check.');
      _socketManager.checkAndFixSocketConnection(_isLoggedOut);
    }

    logger.d('${newOrders.length}건 주문 처리 큐 추가 및 즉시 처리 완료');
  }

  // DEPRECATED: Use AlertManager.triggerNewOrderAlert instead
  // void blinkBubble() { ... }

  // blink 상태 업데이트를 위한 별도 메서드
  void _updateBlinkState() {
    // 필터링된 주문 목록을 사용하여 activeOrderCount 계산
    final filteredOrders = state.orders.where(_shouldShowOrder).toList();
    final activeCount = _calculateActiveOrderCount(filteredOrders);
    // blinkStateProvider만 업데이트하고 orderProvider의 state는 변경하지 않음
    _blinkService.start();
    _blinkService.updateActiveCount(activeCount);
  }

  // 외부 서비스에서 사용할 수 있도록 얇은 퍼블릭 래퍼 제공
  void updateBlinkStateExternal() => _updateBlinkState();

  Future<void> processOrderOutput(OrderModel order,
      {bool playSound = true}) async {
    // [NEW] 출력 작업을 메인 UI 스레드와 분리된 큐로 위임 (즉시 리턴)
    _outputQueueService.add(order, playSound: playSound);
  }

  /// 외부에서 라벨 출력을 직접 요청할 때 호출 (영수증 재출력 등)
  Future<void> printOrderLabels(OrderModel order, {bool isReprint = false}) async {
    await _outputService.printOrderLabels(order, isReprint: isReprint);
  }

  // 영수증 출력 로직을 중복 코드 제거를 위해 분리

  // 주문 목록에서 특정 주문 업데이트
  void updateOrderInList(OrderModel updatedOrder) {
    state = _stateManager.updateOrderInList(state, updatedOrder);
  }

  // 주문 목록 갱신 후 마지막 주문 시간 업데이트
  Future<void> updateLastOrderTime() async {
    // 주문 목록 갱신
    await refreshOrders();

    // 최신 주문 시간 저장
    if (state.orders.isNotEmpty) {
      final sortedOrders = [...state.orders];
      sortedOrders.sort((a, b) => b.updateTime.compareTo(a.updateTime));
      await _preferenceService.setLastOrderTime(sortedOrders.first.updateTime);
    }
  }

  // 캐시에서 주문 상세 정보 직접 가져오기 (저사양 장비 최적화)
  Future<OrderModel?> getOrderDetailFromCache(String orderId) async {
    return _orderDetailCache.get(orderId);
  }

  // 캐시에서 주문 상세 정보 동기적으로 가져오기
  OrderModel? getCachedOrderDetail(String orderId) {
    return _orderDetailCache.get(orderId);
  }

  // state.orders에서 주문을 ID로 찾아 반환 (소켓 매니저용)
  OrderModel? getOrderFromState(String orderId) {
    try {
      return state.orders.firstWhere((o) => o.orderId == orderId);
    } catch (_) {
      return null;
    }
  }

  // 현재 로딩 중인 주문 ID들을 추적하는 Set
  final Set<String> _loadingOrderIds = <String>{};

  // 주문 상세 정보가 현재 로딩 중인지 확인
  bool isOrderDetailLoading(String orderId) {
    return _loadingOrderIds.contains(orderId);
  }

  // 주문 상세 정보 조회
  // 주문 상세 정보 조회 (상태 업데이트 포함)
  Future<OrderModel?> fetchOrderDetail(String orderId) async {
    // 이미 로딩 중인 경우 중복 호출 방지
    if (_loadingOrderIds.contains(orderId)) {
      logger.d('[fetchOrderDetail] 이미 로딩 중인 주문, 중복 호출 방지: $orderId');
      return null;
    }

    // 캐시에서 먼저 확인
    final cachedOrder = _orderDetailCache.get(orderId);
    if (cachedOrder != null && cachedOrder.isDetailLoaded) {
      // [FIX] 캐시에는 상세 정보가 있지만 state.orders에는 없는 경우(초기 로딩 시점 엇갈림 등) UI 갱신을 위해 state 업데이트
      final index = state.orders.indexWhere((o) => o.orderId == orderId);
      if (index != -1) {
        final existingOrder = state.orders[index];
        if (!existingOrder.isDetailLoaded) {
          final mergedOrder = cachedOrder.copyWith(
            status: existingOrder.status,
            orderStatus: existingOrder.orderStatus,
            updateTime: existingOrder.updateTime.isAfter(cachedOrder.updateTime)
                ? existingOrder.updateTime
                : cachedOrder.updateTime,
            isDetailLoaded: true,
          );
          final updatedOrders = List<OrderModel>.from(state.orders);
          updatedOrders[index] = mergedOrder;
          state = state.copyWith(orders: updatedOrders);
          logger.d('[fetchOrderDetail] 캐시에서 정보 복원하여 상태 업데이트: $orderId');
        }
      }
      return cachedOrder;
    }

    // API 호출 시작
    _loadingOrderIds.add(orderId);

    // 로딩 상태 표시를 위해 상태 업데이트 (선택 사항 - 스피너 표시용)
    // 현재는 _loadingOrderIds로 관리하므로 state 변경은 안 함 via isDetailLoaded

    final storeState = ref.read(storeProvider);
    if (!storeState.hasValue || storeState.value == null) {
      logger.e('매장 정보가 없습니다.');
      _loadingOrderIds.remove(orderId);
      return null;
    }
    final storeId = storeState.value!.storeId;

    final apiService = ref.read(apiServiceProvider);
    try {
      logger.d('[fetchOrderDetail] API 호출 시작: $orderId');
      final detailedOrder =
          await apiService.getOrder(orderId, storeId: storeId);

      _loadingOrderIds.remove(orderId);

      // 상태 업데이트
      final index = state.orders.indexWhere((o) => o.orderId == orderId);
      if (index != -1) {
        final existingOrder = state.orders[index];

        final mergedOrder = detailedOrder.copyWith(
          status: existingOrder.status,
          orderStatus: existingOrder.orderStatus,
          updateTime: existingOrder.updateTime.isAfter(detailedOrder.updateTime)
              ? existingOrder.updateTime
              : detailedOrder.updateTime,
          isDetailLoaded: true,
        );

        // 리스트 업데이트
        final updatedOrders = List<OrderModel>.from(state.orders);
        updatedOrders[index] = mergedOrder;

        state = state.copyWith(orders: updatedOrders);
        _orderDetailCache.put(orderId, mergedOrder);

        logger.d('[fetchOrderDetail] 로딩 및 상태 업데이트 완료: $orderId');
        return mergedOrder;
      } else {
        // 리스트에 없으면 캐시에만 저장
        _orderDetailCache.put(orderId, detailedOrder);
        logger.d('[fetchOrderDetail] 목록에 없음, 캐시 저장 완료: $orderId');
        return detailedOrder;
      }
    } catch (e) {
      // ApiService/AppFitCore에서 이미 상세한 [API] ERROR 로그를 남겼으므로,
      // Provider에서는 간단히 실패 사실만 기록 (중복 방지)
      logger.w('[fetchOrderDetail] 실패: $orderId ($e)');
      _loadingOrderIds.remove(orderId);
      return null;
    }
  }

  // 로그아웃 시 캐시 초기화 (기존 호환성을 위해 유지)
  void clearCache() {
    _orderDetailCache.clear();
    logger.d('[OrderProvider] 캐시 초기화 완료 (cleanupOnLogout 사용 권장)');
  }

  // 로그아웃 시 자원 정리 (심플화)
  void cleanupOnLogout() {
    logger.d('[OrderProvider] 로그아웃 시 자원 정리 시작');

    // 로그아웃 상태 설정
    _isLoggedOut = true;

    // 1. 소켓 연결 해제
    _socketManager.clearOnLogout();

    // 2. 타이머 정리
    _timerManager.cleanupOnLogout();
    _queueProcessingTimer?.cancel();
    _queueProcessingTimer = null;
    _batchProcessingTimer?.cancel();
    _batchProcessingTimer = null;

    // 3. 외부 서비스 정지
    // _firestoreSyncService.stop(); // Removed
    _orderQueueService.stop();

    // 4. AudioPlayer 정리
    if (!_isAudioPlayerDisposed) {
      _audioPlayer.stop();
      _audioPlayer.dispose();
      _isAudioPlayerDisposed = true;
    }

    // 5. UI 상태 초기화
    state = OrderState.initial();

    logger.d('[OrderProvider] 로그아웃 시 자원 정리 완료');
  }

  // 로그인 후 설정 재로드 (심플화)
  void reloadSettings() {
    logger.d('[OrderProvider] 로그인 후 재시작');

    // 1. 로그아웃 상태 해제
    _isLoggedOut = false;

    // 2. 초기 로딩 완료 플래그 초기화 (모드 전환 시 초기 주문 로딩을 위해)
    _isInitialLoadComplete = false;

    // 3. 자동접수 설정 로드
    final currentAutoReceipt = _preferenceService.getAutoReceipt();
    state = state.copyWith(isAutoReceipt: currentAutoReceipt);

    // 4. 필수 서비스 재시작
    _settingsManager.reloadAfterLogin();
    _setupPollingTimer();
    _orderQueueService.start();

    // 5. Firestore 리스너 재시작 (Removed)
    // final storeId = ref.read(storeProvider).value?.storeId ?? '';
    // if (storeId.isNotEmpty) {
    // _firestoreSyncService.start(storeId, _handleFirestoreStatusUpdate);
    // }

    // 6. 소켓 연결 (일반 모드만)
    final isKdsMode = ref.read(kdsModeProvider);
    if (!isKdsMode) {
      Future.microtask(
          () => _socketManager.checkAndFixSocketConnection(_isLoggedOut));
    }

    // 7. AudioPlayer 재초기화
    _reinitAudioPlayerIfNeeded();

    // 8. 초기 주문 데이터 로딩 (모드 전환 시 필요)
    Future.microtask(() => _orderDataInitialize());

    logger.d('[OrderProvider] 로그인 후 재시작 완료');
  }

  void _reinitAudioPlayerIfNeeded() {
    try {
      if (_isAudioPlayerDisposed) {
        logger.d('[OrderProvider] AudioPlayer 재초기화(reloadSettings)');
        try {
          _audioPlayer.dispose();
        } catch (_) {}
        _audioPlayer = AudioPlayer();
        _isAudioPlayerDisposed = false;
        // 최근 로드된 볼륨/설정을 반영
        try {
          _settingsManager.applyAudioPlayerSettings(_audioPlayer);
        } catch (e) {
          logger.w('AudioPlayer 초기화 설정 중 경고: $e');
        }
      }
    } catch (e, s) {
      logger.w('AudioPlayer 재초기화 실패 (무시 가능)', error: e, stackTrace: s);
    }
  }

  // 기존 상세 정보를 보존하면서 새 주문 목록과 병합 (사용 안함)
  /*
  List<OrderModel> _mergeWithExistingDetails(List<OrderModel> newOrders) {
    return _helper.mergeWithExistingDetails(
        newOrders, state.orders, _orderDetailCache);
  }
  */

  // 주문 상세 정보를 백그라운드에서 병렬로 로드 (사용 안함)
  /*
  Future<void> _loadOrderDetailsInBackground(List<OrderModel> orders) async {
    try {
      // 상세 정보가 없는 주문들만 필터링
      final ordersNeedingDetails = orders
          .where((order) =>
              order.orderMenuList.isEmpty && order.orderId.isNotEmpty)
          .toList();

      if (ordersNeedingDetails.isEmpty) {
        logger.d('[Detail Loading] 상세 정보가 필요한 주문이 없습니다.');
        return;
      }

      logger.d(
          '[Detail Loading] ${ordersNeedingDetails.length}개 주문의 상세 정보를 백그라운드에서 로드 시작');

      // 로딩할 주문 ID 목록 출력
      final orderIds = ordersNeedingDetails.map((o) => o.orderId).join(', ');
      logger.d('[Detail Loading] 로딩 대상 주문 ID: $orderIds');

      // 저사양 장비 고려한 상세 정보 로드
      final isKdsMode = ref.read(kdsModeProvider);
      final int batchSize = isKdsMode ? 3 : 5; // 배치 크기 조정
      final int delayMs = isKdsMode ? 200 : 100; // 지연 시간 단축

      int loadedCount = 0;
      int errorCount = 0;

      for (int i = 0; i < ordersNeedingDetails.length; i += batchSize) {
        final batch = ordersNeedingDetails.skip(i).take(batchSize).toList();
        logger.d(
            '[Detail Loading] 배치 ${(i ~/ batchSize) + 1} 처리 중: ${batch.length}건');

        // 이미 캐시에 있는 주문은 건너뛰기
        final ordersToLoad = batch
            .where((order) => !_orderDetailCache.contains(order.orderId))
            .toList();

        if (ordersToLoad.isNotEmpty) {
          logger.d(
              '[Detail Loading] 실제 로딩할 주문: ${ordersToLoad.map((o) => o.orderId).join(', ')}');

          if (isKdsMode) {
            // KDS 모드에서는 순차적으로 처리 (저사양 장비 고려)
            for (final order in ordersToLoad) {
              try {
                final result = await fetchOrderDetail(order.orderId);
                if (result != null) {
                  loadedCount++;
                  logger.d('[Detail Loading] 성공: ${order.orderId}');
                } else {
                  errorCount++;
                  logger.d('[Detail Loading] 실패: ${order.orderId} (null 반환)');
                }
                // 각 주문 로드 후 짧은 휴식
                await Future.delayed(const Duration(milliseconds: 50));
              } catch (e) {
                errorCount++;
                logger.e('[Detail Loading] 오류: ${order.orderId}', error: e);
              }
            }
          } else {
            // 일반 모드에서는 병렬 처리 (에러 처리 개선)
            final results = await Future.wait(
              ordersToLoad.map(
                  (order) => fetchOrderDetail(order.orderId).catchError((e) {
                        logger.e('[Detail Loading] 병렬 로딩 오류: ${order.orderId}',
                            error: e);
                        errorCount++;
                        return null;
                      })),
            );

            loadedCount += results.where((result) => result != null).length;
          }
        } else {
          logger.d('[Detail Loading] 배치 ${(i ~/ batchSize) + 1}: 모든 주문이 이미 캐시됨');
        }

        // 각 배치 완료 후 대기 시간
        if (i + batchSize < ordersNeedingDetails.length) {
          await Future.delayed(Duration(milliseconds: delayMs));
        }
      }

      logger.d(
          '[Detail Loading] 백그라운드 상세 정보 로드 완료: 성공 ${loadedCount}건, 실패 ${errorCount}건');
    } catch (e, s) {
      logger.e('[Detail Loading] 백그라운드 상세 정보 로드 중 전체 오류 발생',
          error: e, stackTrace: s);
    }
  }
  */

  /// 긴급 모드 ON/OFF — 설정 화면에서 호출 (폴링 주기만 변경)
  void updateEmergencyPoll(bool enabled) {
    if (enabled) {
      _timerManager.restartPolling(OrderTimerManager.socketDisconnectedIntervalSeconds);
      logToFile(
        tag: LogTag.WEBSOCKET,
        message: '[긴급모드] ON - 폴링 ${OrderTimerManager.socketDisconnectedIntervalSeconds}s',
      );
    } else {
      _timerManager.restartPolling(OrderTimerManager.socketConnectedIntervalSeconds);
      logToFile(
        tag: LogTag.WEBSOCKET,
        message: '[긴급모드] OFF - 폴링 복원 ${OrderTimerManager.socketConnectedIntervalSeconds}s',
      );
    }
  }
}

// (removed) Legacy adapters and internal service contracts are moved to core/orders/*
