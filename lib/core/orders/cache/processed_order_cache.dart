import 'package:appfit_order_agent/utils/logger.dart';

/// 처리된 주문을 추적하여 중복 처리를 방지하는 캐시
/// 소켓과 폴링 간의 경쟁 상태(Race Condition)를 해결하기 위해 사용됩니다.
class ProcessedOrderCache {
  // orderId -> processedTime
  final Map<String, DateTime> _processedOrders = {};

  // 캐시 만료 시간 (기본 30분)
  // 주문 처리 후 30분이 지나면 중복 체크에서 제외 (재처리 가능성 열어둠? 보통은 불필요하지만 메모리 관리를 위해)
  final Duration _cleanupThreshold = const Duration(minutes: 30);

  /// 주문이 이미 처리되었는지 확인
  bool contains(String orderId) {
    _cleanupOldEntries();
    return _processedOrders.containsKey(orderId);
  }

  /// 주문을 처리된 목록에 추가
  void add(String orderId) {
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
