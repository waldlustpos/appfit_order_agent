import 'package:appfit_core/appfit_core.dart';
import 'package:appfit_order_agent/utils/logger.dart';

/// 클라이언트가 직접 수행한 주문 동작을 일시적으로 저장하여
/// 소켓으로 동일한 이벤트가 중복 수신될 때 필터링하기 위한 캐시입니다.
class ActionCache {
  // key: orderId_eventType -> value: actionTime
  final Map<String, DateTime> _actions = {};

  // 캐시 유지 시간 (API 응답과 소켓 수신 간의 시간차를 고려하여 30초로 설정)
  final Duration _expiryThreshold = const Duration(seconds: 30);

  /// 특정 주문에 대해 특정 이벤트가 최근에 클라이언트에 의해 수행되었는지 확인
  bool isRecentAction(String orderId, OrderEventType eventType) {
    _cleanupExpiredEntries();
    final key = '${orderId}_${eventType.name}';
    return _actions.containsKey(key);
  }

  /// 클라이언트가 수행한 동작을 캐시에 추가
  void recordAction(String orderId, OrderEventType eventType) {
    final key = '${orderId}_${eventType.name}';
    _actions[key] = DateTime.now();
    logger.d('[ActionCache] Action recorded: $key');
  }

  /// 캐시 초기화
  void clear() {
    _actions.clear();
    logger.d('[ActionCache] Cache cleared');
  }

  /// 만료된 항목 정리
  void _cleanupExpiredEntries() {
    final now = DateTime.now();
    _actions.removeWhere((_, time) => now.difference(time) > _expiryThreshold);
  }
}
