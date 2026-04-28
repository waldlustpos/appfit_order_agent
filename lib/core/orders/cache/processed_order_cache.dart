import 'package:appfit_order_agent/models/enums/order_status.dart';
import 'package:appfit_order_agent/utils/logger.dart';

/// (orderId, status) 조합 단위로 이미 큐에 들어간 주문을 추적하여 중복 enqueue를 방지하는 캐시.
///
/// **키 포맷**: `'${orderId}_${status}'` — 같은 주문이라도 status가 바뀌면(NEW→PREPARING 등)
/// 새 항목으로 기록되어 상태 전이 이벤트는 통과한다. 같은 (id, status) 조합은 30분 차단한다.
///
/// **목적**: WebSocket과 REST 폴링이 동일한 (orderId, status) 페어를 동시 발행하는
/// 이중 소스 race를 차단한다. 호출자가 키 포맷을 직접 만들지 않도록
/// `containsOrderStatus` / `addOrderStatus` API만 사용해야 한다.
///
/// SocketEventSuppressor와의 차이:
/// - SocketEventSuppressor는 **클라이언트 자가 PUT 직후 echo 이벤트** 1회성 차단(10초, 키=eventType).
/// - ProcessedOrderCache는 **소스 무관 (orderId, status) enqueue 중복** 차단(30분, 키=status).
class ProcessedOrderCache {
  // 키: '${orderId}_${status}' -> 값: 처리 시각
  final Map<String, DateTime> _processedOrders = {};

  // 캐시 만료 시간 (기본 30분)
  final Duration _cleanupThreshold = const Duration(minutes: 30);

  // 최대 캐시 크기 (초과 시 가장 오래된 항목부터 제거)
  static const int _maxSize = 500;

  /// (orderId, status) 조합이 이미 처리되었는지 확인.
  bool containsOrderStatus(String orderId, OrderStatus status) {
    return _containsKey(_makeKey(orderId, status));
  }

  /// (orderId, status) 조합을 처리됨으로 기록.
  void addOrderStatus(String orderId, OrderStatus status) {
    _addKey(_makeKey(orderId, status));
  }

  /// 캐시 초기화
  void clear() {
    _processedOrders.clear();
    logger.d('[ProcessedOrderCache] 캐시 초기화 완료');
  }

  /// 디버깅용: 현재 캐시 크기 확인
  int get size => _processedOrders.length;

  String _makeKey(String orderId, OrderStatus status) => '${orderId}_$status';

  bool _containsKey(String key) {
    _cleanupOldEntries();
    return _processedOrders.containsKey(key);
  }

  void _addKey(String key) {
    _cleanupOldEntries();
    if (_processedOrders.length >= _maxSize) {
      // 가장 오래된 항목 제거
      final oldest = _processedOrders.entries
          .reduce((a, b) => a.value.isBefore(b.value) ? a : b)
          .key;
      _processedOrders.remove(oldest);
    }
    _processedOrders[key] = DateTime.now();
  }

  /// 만료된 항목 정리
  void _cleanupOldEntries() {
    final now = DateTime.now();
    _processedOrders
        .removeWhere((_, time) => now.difference(time) > _cleanupThreshold);
  }
}
