import 'package:appfit_order_agent/models/order_model.dart';

class _CacheEntry {
  final OrderModel order;
  final DateTime timestamp; // 저장 시간
  DateTime lastAccessed; // 마지막 접근 시간

  _CacheEntry({
    required this.order,
    required this.timestamp,
    required this.lastAccessed,
  });
}

// 주문 상세 정보 캐시 클래스
class OrderDetailCache {
  // 최대 캐시 크기 (건수)
  static const int maxCacheSize = 200;
  // 캐시 유효기간 (1시간)
  static const Duration maxCacheAge = Duration(hours: 1);

  // 캐시 데이터 구조
  final Map<String, _CacheEntry> _cache = {};

  // 캐시 데이터 저장
  void put(String orderId, OrderModel order) {
    // 캐시 정리
    _cleanupCacheIfNeeded();

    // 캐시 저장
    _cache[orderId] = _CacheEntry(
      order: order,
      timestamp: DateTime.now(),
      lastAccessed: DateTime.now(),
    );
  }

  // 캐시 데이터 조회
  OrderModel? get(String orderId) {
    final entry = _cache[orderId];
    if (entry == null) {
      return null;
    }

    // 유효기간 확인
    if (DateTime.now().difference(entry.timestamp) > maxCacheAge) {
      // 만료된 데이터 삭제
      _cache.remove(orderId);
      return null;
    }

    // 마지막 접근 시간 업데이트
    entry.lastAccessed = DateTime.now();
    return entry.order;
  }

  // 캐시 존재 여부 확인
  bool contains(String orderId) {
    final entry = _cache[orderId];
    if (entry == null) {
      return false;
    }

    // 유효기간 확인
    if (DateTime.now().difference(entry.timestamp) > maxCacheAge) {
      // 만료된 데이터 삭제
      _cache.remove(orderId);
      return false;
    }

    return true;
  }

  // 캐시 크기
  int get size => _cache.length;

  // 캐시 초기화
  void clear() {
    _cache.clear();
  }

  // 캐시 정리
  void _cleanupCacheIfNeeded() {
    // 최대 크기를 초과하지 않으면 정리 불필요
    if (_cache.length < maxCacheSize) {
      return;
    }

    // 유효 기간이 지난 항목 삭제
    _removeExpiredEntries();

    // 여전히 최대 크기를 초과하면 가장 오래된 항목부터 삭제
    if (_cache.length >= maxCacheSize) {
      final entriesToRemove = (_cache.length * 0.3).ceil();
      final sortedEntries = _cache.entries.toList()
        ..sort((a, b) => a.value.lastAccessed.compareTo(b.value.lastAccessed));

      for (var i = 0; i < entriesToRemove && i < sortedEntries.length; i++) {
        _cache.remove(sortedEntries[i].key);
      }
    }
  }

  // 만료된 캐시 정리 (주기적으로 호출)
  void cleanupExpiredEntries() {
    _removeExpiredEntries();
  }

  // 만료된 항목 제거 - 중복 코드 제거
  void _removeExpiredEntries() {
    final now = DateTime.now();
    _cache.removeWhere((_, entry) {
      return now.difference(entry.timestamp) > maxCacheAge;
    });
  }
}
