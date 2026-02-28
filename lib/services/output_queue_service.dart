import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:appfit_core/appfit_core.dart';
import 'package:appfit_order_agent/models/order_model.dart';
import 'package:appfit_order_agent/utils/logger.dart';
import 'package:appfit_order_agent/core/orders/output_service.dart';

/// 출력 작업 관리를 위한 큐 서비스
/// 프린트/TTS 등 오래 걸리는 작업을 메인 로직과 분리하여 순차적으로 처리합니다.
/// appfit_core의 SerialAsyncQueue를 활용합니다.
class OutputQueueService {
  final Ref ref;
  late final SerialAsyncQueue<({OrderModel order, bool playSound})> _queue;

  OutputQueueService(this.ref) {
    _queue = SerialAsyncQueue(
      onProcess: _processItem,
      onError: (item, error, stack) {
        logger.e('[OutputQueue] 출력 처리 중 실패: ${item.order.orderId}',
            error: error, stackTrace: stack);
      },
    );
  }

  /// 출력 작업 추가
  void add(OrderModel order, {bool playSound = true}) {
    _queue.add((order: order, playSound: playSound));
    logger.d('[OutputQueue] 작업 추가됨: ${order.orderId} (대기열: ${_queue.length})');
  }

  Future<void> _processItem(({OrderModel order, bool playSound}) item) async {
    final outputService = ref.read(outputAppServiceProvider);
    logger.d('[OutputQueue] 출력 시작: ${item.order.orderId}');
    await outputService.notifyNewOrder(item.order, playSound: item.playSound);
    logger.d('[OutputQueue] 출력 완료: ${item.order.orderId}');
  }

  /// 큐 정리 (로그아웃 등)
  void clear() {
    _queue.clear();
    logger.d('[OutputQueue] 큐 정리 완료');
  }
}

/// 전역 프로바이더 정의
final outputQueueServiceProvider = Provider<OutputQueueService>((ref) {
  return OutputQueueService(ref);
});
