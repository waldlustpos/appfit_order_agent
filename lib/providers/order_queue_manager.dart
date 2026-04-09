import 'dart:async';
import 'dart:collection';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/order_model.dart';
import '../utils/logger.dart';

/// 주문 처리 큐 관리 클래스 (Refactored)
/// Buffer -> Sort -> Emit (Throttle) 파이프라인 구현
class OrderQueueManager {
  final Ref ref;

  // 1. Buffering Stage
  final List<OrderModel> _bufferList = [];
  Timer? _bufferTimer;
  // 요구사항: 1초 정도의 버퍼링 텀 (순서 정렬을 위해 모으는 시간)
  static const Duration _bufferWindow = Duration(milliseconds: 1000);

  // 2. Emitting Stage
  final Queue<OrderModel> _emitQueue = Queue();
  Timer? _emitTimer;
  // 요구사항: 일정 term으로 보여짐 (0.5초 간격, 대량 인입 시 0.25초로 단축)
  static const Duration _emitInterval = Duration(milliseconds: 500);
  static const Duration _emitIntervalFast = Duration(milliseconds: 250);
  static const int _fastEmitThreshold = 20;

  // 주문 처리 콜백 (UI 업데이트)
  final Future<void> Function(OrderModel) onProcessSingleOrder;

  OrderQueueManager(this.ref, {required this.onProcessSingleOrder});

  /// 외부에서 주문을 큐에 추가
  void queueOrder(OrderModel order) {
    // 중복 체크: 버퍼나 방출 큐에 이미 있는지 확인
    final isDuplicate = _bufferList.any((o) => o.orderId == order.orderId) ||
        _emitQueue.any((o) => o.orderId == order.orderId);

    if (isDuplicate) {
      logger.d('[QueueManager] 중복 주문 무시: ${order.orderId}');
      return;
    }

    // [FIX] NEW 상태가 아닌 상태 변경(PREPARING 등)은 큐(throttle)를 거치지 않고 즉시 방출
    // 이를 통해 주문 대량 인입 시 상태 변경에 따른 알림, 출력음이 밀리는(25초 뒤 재생) 현상을 방지
    if (order.status != OrderStatus.NEW) {
      logger.d(
          '[QueueManager] 상태 업데이트 즉시 방출 (큐 우회): ${order.orderId} (${order.status})');
      onProcessSingleOrder(order);
      return;
    }

    _bufferList.add(order);
    logger.d(
        '[QueueManager] 버퍼 추가: ${order.orderId} (현재 버퍼: ${_bufferList.length})');

    // 버퍼 타이머 시작 (최초 1회 진입 시)
    if (_bufferTimer == null || !_bufferTimer!.isActive) {
      logger.d('[QueueManager] 버퍼 타이머 시작 (${_bufferWindow.inMilliseconds}ms)');
      _bufferTimer = Timer(_bufferWindow, _flushBuffer);
    }
  }

  /// 버퍼를 비우고 정렬하여 방출 큐로 이동
  void _flushBuffer() {
    if (_bufferList.isEmpty) return;

    // 1. 정렬 (User 요구사항: 낮은 주문번호 순)
    _bufferList.sort((a, b) {
      try {
        final nA = int.parse(a.shopOrderNo);
        final nB = int.parse(b.shopOrderNo);
        return nA.compareTo(nB);
      } catch (_) {
        return a.orderId.compareTo(b.orderId);
      }
    });

    logger.d('[QueueManager] 버퍼 정렬 완료 및 방출 큐 이동: ${_bufferList.length}건');

    // 2. 방출 큐로 이동
    _emitQueue.addAll(_bufferList);
    _bufferList.clear();
    _bufferTimer = null;

    // 3. 방출 프로세스 시작
    _startEmitLoop();
  }

  /// 방출 루프 시작
  void _startEmitLoop() {
    if (_emitTimer != null && _emitTimer!.isActive) return;
    if (_emitQueue.isEmpty) return;

    // 즉시 첫 실행
    _processNextEmit();
  }

  /// 다음 주문 방출 및 처리
  void _processNextEmit() async {
    if (_emitQueue.isEmpty) {
      _emitTimer = null;
      return;
    }

    final order = _emitQueue.removeFirst();
    logger.d('[QueueManager] 방출(UI표시): ${order.orderId}');

    try {
      await onProcessSingleOrder(order);
    } catch (e, s) {
      logger.e('[QueueManager] 주문 처리 실패', error: e, stackTrace: s);
    }

    // 다음 처리를 위한 타이머 예약 (적응형 Throttling)
    if (_emitQueue.isNotEmpty) {
      final interval = _emitQueue.length > _fastEmitThreshold
          ? _emitIntervalFast
          : _emitInterval;
      _emitTimer = Timer(interval, _processNextEmit);
    } else {
      _emitTimer = null;
    }
  }

  bool get hasPending => _bufferList.isNotEmpty || _emitQueue.isNotEmpty;

  void clearQueues() {
    _bufferList.clear();
    _emitQueue.clear();
    _bufferTimer?.cancel();
    _emitTimer?.cancel();
    _bufferTimer = null;
    _emitTimer = null;
    logger.d('[OrderQueueManager] 큐 정리 완료');
  }

  void clearOnLogout() {
    clearQueues();
    logger.d('[OrderQueueManager] 로그아웃 시 정리 완료');
  }

  void dispose() {
    clearQueues();
    logger.d('[OrderQueueManager] dispose 완료');
  }
}
