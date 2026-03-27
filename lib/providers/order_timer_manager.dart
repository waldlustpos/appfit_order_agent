import 'dart:async';
import 'package:appfit_core/appfit_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/logger.dart';

/// 주문 관련 타이머 및 구독 관리 클래스
/// 폴링, 캐시 정리, 자정 새로고침 등의 타이머를 관리합니다.
class OrderTimerManager {
  final Ref ref;

  // 타이머들
  Timer? _pollingTimer;
  Timer? _pollingStartupTimer; // 초기 30초 딜레이용 (취소 가능)
  Timer? _cacheCleanupTimer;
  Timer? _midnightRefreshTimer;
  Timer? _batchProcessingTimer;

  // 구독들
  StreamSubscription? _orderNotificationSubscription;
  StreamSubscription<Map<String, dynamic>>? _messageStreamSubscription;

  // 폴링 간격 상수 (appfit_core 공용 상수 참조)
  static const int socketConnectedIntervalSeconds = AppFitSyncIntervals.connectedSeconds;
  static const int socketDisconnectedIntervalSeconds = AppFitSyncIntervals.disconnectedSeconds;

  // 설정
  int _currentPollingIntervalSeconds = socketConnectedIntervalSeconds;

  // 콜백 함수들
  final VoidCallback? onPollNewOrders;
  final VoidCallback? onRefreshOrders;
  final VoidCallback? onCacheCleanup;

  OrderTimerManager(
    this.ref, {
    this.onPollNewOrders,
    this.onRefreshOrders,
    this.onCacheCleanup,
  });

  /// 폴링 타이머 설정
  void setupPollingTimer(bool isLoggedOut) {
    // 로그아웃 상태인 경우 폴링 하지 않음
    if (isLoggedOut) {
      logger.d('로그아웃 상태이므로 폴링을 건너뜁니다.');
      return;
    }

    // AppFitConfig.baseUrl이 유효하지 않은 경우 폴링 하지 않음
    if (AppFitConfig.baseUrl.isEmpty || AppFitConfig.baseUrl == "/") {
      logger.d(
          'AppFitConfig.baseUrl이 유효하지 않아 폴링을 건너뜁니다. baseUrl: ${AppFitConfig.baseUrl}');
      return;
    }

    logger.d('주문폴링 시작');

    _pollingStartupTimer?.cancel();
    _pollingTimer?.cancel();

    _pollingStartupTimer = Timer(const Duration(seconds: 30), () {
      _pollingStartupTimer = null;
      _pollingTimer?.cancel();
      _pollingTimer = Timer.periodic(
          Duration(seconds: _currentPollingIntervalSeconds), (_) {
        logger.d('폴링 실행 -> _pollNewOrders');
        onPollNewOrders?.call();
      });
    });
  }

  /// 소켓 상태에 따른 폴링 간격 재설정 (항상 전체 새로고침)
  void restartPolling(int intervalSeconds) {
    _pollingStartupTimer?.cancel();
    _pollingStartupTimer = null;
    _currentPollingIntervalSeconds = intervalSeconds;
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(Duration(seconds: intervalSeconds), (_) {
      logger.d('폴링 실행 (간격: ${intervalSeconds}s) → 전체 새로고침');
      onRefreshOrders?.call();
    });
    logger.d('폴링 간격 변경 → ${intervalSeconds}s');
  }

  /// 캐시 정리 타이머 설정
  void setupCacheCleanupTimer() {
    _cacheCleanupTimer?.cancel();
    _cacheCleanupTimer = Timer.periodic(const Duration(hours: 1), (_) {
      onCacheCleanup?.call();
    });
  }

  /// 자정 새로고침 타이머 설정
  void scheduleMidnightRefresh() {
    _midnightRefreshTimer?.cancel();
    final now = DateTime.now();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1, 0, 0, 1);
    final durationUntilMidnight = nextMidnight.difference(now);

    logger.i(
        'Scheduling next midnight refresh in $durationUntilMidnight. Will run at $nextMidnight');

    _midnightRefreshTimer = Timer(durationUntilMidnight, () {
      logger.i('Midnight timer triggered. Refreshing orders for the new day.');
      onRefreshOrders?.call();
      scheduleMidnightRefresh();
    });
  }

  /// 배치 처리 타이머 설정
  void setBatchProcessingTimer(Duration duration, VoidCallback callback) {
    _batchProcessingTimer?.cancel();
    _batchProcessingTimer = Timer(duration, callback);
  }

  /// 배치 처리 타이머 취소
  void cancelBatchProcessingTimer() {
    _batchProcessingTimer?.cancel();
    _batchProcessingTimer = null;
  }

  /// 주문 알림 구독 설정
  void setOrderNotificationSubscription(StreamSubscription subscription) {
    _orderNotificationSubscription?.cancel();
    _orderNotificationSubscription = subscription;
  }

  /// 메시지 스트림 구독 설정
  void setMessageStreamSubscription(
      StreamSubscription<Map<String, dynamic>> subscription) {
    _messageStreamSubscription?.cancel();
    _messageStreamSubscription = subscription;
  }

  /// 주문 알림 구독 취소
  void cancelOrderNotificationSubscription() {
    _orderNotificationSubscription?.cancel();
    _orderNotificationSubscription = null;
  }

  /// 메시지 스트림 구독 취소
  void cancelMessageStreamSubscription() {
    _messageStreamSubscription?.cancel();
    _messageStreamSubscription = null;
  }

  /// 주문 알림 구독 상태 확인
  bool get hasOrderNotificationSubscription =>
      _orderNotificationSubscription != null;

  /// 주문 알림 구독이 일시 중지되었는지 확인
  bool get isOrderNotificationSubscriptionPaused =>
      _orderNotificationSubscription?.isPaused ?? false;

  /// 주문 알림 구독 재개
  void resumeOrderNotificationSubscription() {
    _orderNotificationSubscription?.resume();
  }

  /// 모든 타이머 및 구독 정리
  void dispose() {
    logger.d('OrderTimerManager disposing...');

    // 타이머 정리
    _pollingStartupTimer?.cancel();
    _pollingStartupTimer = null;

    _pollingTimer?.cancel();
    _pollingTimer = null;

    _cacheCleanupTimer?.cancel();
    _cacheCleanupTimer = null;

    _midnightRefreshTimer?.cancel();
    _midnightRefreshTimer = null;

    _batchProcessingTimer?.cancel();
    _batchProcessingTimer = null;

    // 구독 정리
    _orderNotificationSubscription?.cancel();
    _orderNotificationSubscription = null;

    _messageStreamSubscription?.cancel();
    _messageStreamSubscription = null;

    logger.d('OrderTimerManager disposed.');
  }

  /// 로그아웃 시 정리
  void cleanupOnLogout() {
    logger.d('[OrderTimerManager] 로그아웃 시 정리 시작');
    dispose();
    logger.d('[OrderTimerManager] 로그아웃 시 정리 완료');
  }
}
