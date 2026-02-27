import 'package:appfit_order_agent/utils/logger.dart';

/// 소켓 이벤트 중복 처리를 방지하기 위한 유틸리티 클래스
///
/// 자신이 요청한 API에 의한 소켓 이벤트는 무시하고,
/// 다른 기기에서 발생한 이벤트만 처리하도록 돕습니다.
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
