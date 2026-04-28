import 'package:appfit_order_agent/utils/logger.dart';

/// 클라이언트 자가 PUT 직후 echo 로 돌아오는 소켓 이벤트를 1회성 차단하는 싱글톤.
///
/// **키 포맷**: `'${orderId}_${eventType}'` (eventType = appfit_core.OrderEventType.value)
/// **TTL**: 10초. **소비**: 1회성 — `shouldIgnore` 가 true 를 반환하면 즉시 제거.
///
/// **목적**: API 호출(예: updateOrderStatus PUT) 직후 같은 매장의 소켓 채널로 우리가
/// 만든 이벤트가 echo 되어 돌아온다. 이를 처리하면 자기 자신의 변경을 또 처리해 race 가
/// 발생하므로, 이 윈도우 동안만 차단한다. 다른 기기에서 발생한 같은 이벤트는 그대로 처리.
///
/// ProcessedOrderCache 와의 차이:
/// - ProcessedOrderCache 는 **소스 무관 (orderId, status) enqueue 중복** 차단(30분, 키=status, 다회 hit).
/// - SocketEventSuppressor 는 **자가 PUT 의 echo** 차단(10초, 키=eventType, 1회성 소비).
class SocketEventSuppressor {
  static final SocketEventSuppressor _instance =
      SocketEventSuppressor._internal();

  factory SocketEventSuppressor() {
    return _instance;
  }

  SocketEventSuppressor._internal();

  // Key: "${orderId}_${eventType}"
  // Value: Timestamp of request
  final Map<String, DateTime> _suppressionList = {};

  // 유효 시간 (이 시간이 지나면 무시하지 않음)
  static const Duration _expirationDuration = Duration(seconds: 10);

  /// 무시할 이벤트 등록
  /// orderId: 주문 ID
  /// eventType: 예상되는 이벤트 타입 (EventTypes.*)
  void add(String orderId, String eventType) {
    final key = _makeKey(orderId, eventType);
    _suppressionList[key] = DateTime.now();
    logger.d('[SocketEventSuppressor] 등록: $key');

    // 만료된 항목 정리 (가벼운 정리)
    _cleanup();
  }

  /// 이벤트를 무시해야 하는지 확인
  /// 무시해야 한다면 true 리턴하고 리스트에서 제거 (일회성)
  bool shouldIgnore(String orderId, String eventType) {
    final key = _makeKey(orderId, eventType);
    final timestamp = _suppressionList[key];

    if (timestamp != null) {
      final difference = DateTime.now().difference(timestamp);
      if (difference <= _expirationDuration) {
        // 무시 대상임
        _suppressionList.remove(key); // 한 번 막았으면 제거
        logger.i(
            '[SocketEventSuppressor] 자가 발생 이벤트 무시됨: $key (${difference.inMilliseconds}ms 경과)');
        return true;
      } else {
        // 시간이 너무 지났으면 유효하지 않음
        _suppressionList.remove(key);
      }
    }
    return false;
  }

  String _makeKey(String orderId, String eventType) {
    return "${orderId}_${eventType}";
  }

  void _cleanup() {
    final now = DateTime.now();
    _suppressionList.removeWhere((key, timestamp) {
      return now.difference(timestamp) > _expirationDuration;
    });
  }
}
