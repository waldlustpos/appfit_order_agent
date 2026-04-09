import 'package:appfit_order_agent/utils/logger.dart';

/// 처리된 주문을 추적하여 중복 처리를 방지하는 캐시
/// 소켓과 폴링 간의 경쟁 상태(Race Condition)를 해결하기 위해 사용됩니다.
class ProcessedOrderCache {
  // orderId -> processedTime
  final Map<String, DateTime> _processedOrders = {};

  // 캐시 만료 시간 (기본 30분)
  final Duration _cleanupThreshold = const Duration(minutes: 30);

  // 최대 캐시 크기 (초과 시 가장 오래된 항목부터 제거)
  static const int _maxSize = 500;

  /// 주문이 이미 처리되었는지 확인
  bool contains(String orderId) {
    _cleanupOldEntries();
    return _processedOrders.containsKey(orderId);
  }

  /// 주문을 처리된 목록에 추가
  void add(String orderId) {
    _cleanupOldEntries();
    if (_processedOrders.length >= _maxSize) {
      // 가장 오래된 항목 제거
      final oldest = _processedOrders.entries
          .reduce((a, b) => a.value.isBefore(b.value) ? a : b)
          .key;
      _processedOrders.remove(oldest);
    }
    _processedOrders[orderId] = DateTime.now();
  }

  /// 캐시 초기화
  void clear() {
    _processedOrders.clear();
    logger.d('[ProcessedOrderCache] 캐시 초기화 완료');
  }

  /// 만료된 항목 정리
  void _cleanupOldEntries() {
    final now = DateTime.now();
    _processedOrders
        .removeWhere((_, time) => now.difference(time) > _cleanupThreshold);
  }

  /// 디버깅용: 현재 캐시 크기 확인
  int get size => _processedOrders.length;
}
