import 'dart:async';
import 'dart:collection';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:appfit_order_agent/models/order_model.dart';
import 'package:appfit_order_agent/utils/logger.dart';
import 'package:appfit_order_agent/core/orders/output_service.dart';

/// 출력 작업 관리를 위한 큐 서비스
/// 프린트/TTS 등 오래 걸리는 작업을 메인 로직과 분리하여 순차적으로 처리합니다.
class OutputQueueService {
  final Ref ref;

  // 처리할 작업 큐
  final Queue<({OrderModel order, bool playSound})> _queue = Queue();
  bool _isProcessing = false;

  OutputQueueService(this.ref);

  /// 출력 작업 추가
  void add(OrderModel order, {bool playSound = true}) {
    _queue.add((order: order, playSound: playSound));
    logger.d('[OutputQueue] 작업 추가됨: ${order.orderId} (대기열: ${_queue.length})');
    _processNext();
  }

  /// 다음 작업 처리
  Future<void> _processNext() async {
    // 이미 처리 중이거나 큐가 비었으면 리턴
    if (_isProcessing) return;
    if (_queue.isEmpty) return;

    _isProcessing = true;

    try {
      final item = _queue.removeFirst();
      final outputService = ref.read(outputAppServiceProvider);

      logger.d('[OutputQueue] 출력 시작: ${item.order.orderId}');

      // 실제 출력 서비스 호출 (비동기)
      // 이 작업이 3~5초 걸려도 메인 UI 스레드나 OrderQueueManager는 영향을 받지 않음
      await outputService.notifyNewOrder(item.order, playSound: item.playSound);

      logger.d('[OutputQueue] 출력 완료: ${item.order.orderId}');
    } catch (e, stack) {
      logger.e('[OutputQueue] 출력 처리 중 실패', error: e, stackTrace: stack);
    } finally {
      _isProcessing = false;
      // 큐에 남은 작업이 있으면 계속 처리
      if (_queue.isNotEmpty) {
        // 스택 오버플로우 방지를 위해 microtask로 다음 작업 예약
        Future.microtask(() => _processNext());
      }
    }
  }

  /// 큐 정리 (로그아웃 등)
  void clear() {
    _queue.clear();
    _isProcessing = false;
    logger.d('[OutputQueue] 큐 정리 완료');
  }
}

/// 전역 프로바이더 정의
final outputQueueServiceProvider = Provider<OutputQueueService>((ref) {
  return OutputQueueService(ref);
});
