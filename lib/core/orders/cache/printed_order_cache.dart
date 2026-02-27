import 'package:appfit_order_agent/utils/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

/// 인쇄된 주문을 추적하여 중복 출력을 방지하는 캐시 (영구 저장소 지원)
class PrintedOrderCache {
  // 메모리 캐시 (고속 조회용)
  final Set<String> _printedOrders = {};

  // 영구 저장소 키
  static const String _keyPrintedOrders = 'printed_orders_cache';
  static const String _keyFirstRunCompleted = 'is_first_run_completed_v2';

  // 캐시 만료 시간 (기본 12시간)
  final Duration _cleanupThreshold = const Duration(hours: 12);

  bool _isInitialized = false;

  /// 초기화 메서드 (앱 시작 시 호출)
  /// [existingOrders]가 제공되면 최초 실행 시 해당 주문들을 모두 캐시에 등록함
  Future<void> init(List<String> existingOrders) async {
    if (_isInitialized) return;

    try {
      final prefs = await SharedPreferences.getInstance();

      // 1. 최초 실행 여부 확인
      final bool isFirstRun = prefs.getBool(_keyFirstRunCompleted) ?? false;

      if (!isFirstRun && existingOrders.isNotEmpty) {
        logger.i(
            '[PrintedOrderCache] 앱 최초 실행/재설치 감지 - 기존 주문 ${existingOrders.length}건을 출력된 것으로 처리합니다.');

        // 기존 주문을 모두 캐시에 등록
        final now = DateTime.now().millisecondsSinceEpoch;
        final Map<String, int> initialData = {};

        for (final orderId in existingOrders) {
          _printedOrders.add(orderId);
          initialData[orderId] = now;
        }

        // 저장소에 저장
        await prefs.setString(_keyPrintedOrders, jsonEncode(initialData));
        await prefs.setBool(_keyFirstRunCompleted, true);

        _isInitialized = true;
        return;
      }

      // 2. 저장된 데이터 로드 (일반 실행)
      final String? jsonStr = prefs.getString(_keyPrintedOrders);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final Map<String, dynamic> decoded = jsonDecode(jsonStr);
        final now = DateTime.now();

        // 만료된 항목 정리 후 메모리에 적재
        final Map<String, int> validData = {};
        bool needsUpdate = false;

        decoded.forEach((orderId, timestamp) {
          final time = DateTime.fromMillisecondsSinceEpoch(timestamp as int);
          if (now.difference(time) <= _cleanupThreshold) {
            _printedOrders.add(orderId);
            validData[orderId] = timestamp;
          } else {
            needsUpdate = true; // 정리된 항목이 있음
          }
        });

        logger.d('[PrintedOrderCache] 캐시 로드 완료: ${_printedOrders.length}건 유효');

        // 만료된 항목이 있었다면 정리된 데이터로 업데이트
        if (needsUpdate) {
          await prefs.setString(_keyPrintedOrders, jsonEncode(validData));
        }
      } else {
        // 데이터가 없으면 최초 실행 완료 마킹만 수행 (빈 상태로 시작)
        if (!isFirstRun) {
          await prefs.setBool(_keyFirstRunCompleted, true);
        }
      }

      _isInitialized = true;
    } catch (e, s) {
      logger.e('[PrintedOrderCache] 초기화 오류', error: e, stackTrace: s);
      // 오류 발생 시에도 동작은 가능하도록 플래그 설정
      _isInitialized = true;
    }
  }

  /// 주문이 이미 인쇄되었는지 확인 (메모리 조회 - O(1))
  bool contains(String orderId) {
    if (!_isInitialized) {
      logger.w('[PrintedOrderCache] 초기화되지 않은 상태에서 접근');
    }
    return _printedOrders.contains(orderId);
  }

  /// 주문을 인쇄된 목록에 추가하고 비동기로 저장
  void add(String orderId) {
    if (_printedOrders.contains(orderId)) return;

    // 1. 메모리 업데이트
    _printedOrders.add(orderId);

    // 2. 비동기 저장 (Fire-and-forget)
    _saveToDisk(orderId);
  }

  /// 단일 항목 추가에 대한 디스크 저장 처리
  Future<void> _saveToDisk(String newOrderId) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 전체 데이터를 덮어쓰는 방식이지만, JSON 텍스트 크기가 크지 않으므로 허용 가능
      // (더 최적화하려면 별도 DB나 파일 입출력이 필요하지만 SharedPreferences로 충분)
      final String? jsonStr = prefs.getString(_keyPrintedOrders);
      Map<String, dynamic> data = {};

      if (jsonStr != null) {
        data = jsonDecode(jsonStr);
      }

      data[newOrderId] = DateTime.now().millisecondsSinceEpoch;

      await prefs.setString(_keyPrintedOrders, jsonEncode(data));
    } catch (e) {
      logger.e('[PrintedOrderCache] 저장 오류: $newOrderId', error: e);
    }
  }

  /// 캐시 초기화
  Future<void> clear() async {
    _printedOrders.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyPrintedOrders);
    logger.d('[PrintedOrderCache] 캐시 초기화 완료');
  }

  int get size => _printedOrders.length;
}
