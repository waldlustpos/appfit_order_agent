import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:appfit_core/appfit_core.dart';
import 'package:appfit_order_agent/models/order_model.dart';
import 'package:appfit_order_agent/utils/logger.dart';
import 'package:appfit_order_agent/core/orders/output_service.dart';

/// 출력 큐 작업 종류
sealed class OutputJob {
  const OutputJob(this.order);
  final OrderModel order;
}

/// 신규 주문 자동 출력 (영수증 + 라벨 + 사운드)
final class NewOrderJob extends OutputJob {
  const NewOrderJob(super.order, {this.playSound = true});
  final bool playSound;
}

/// 사용자 요청 기반 라벨 재출력 (영수증/사운드 없음)
final class ReprintJob extends OutputJob {
  const ReprintJob(super.order);
}

/// 출력 작업 관리를 위한 큐 서비스
/// 프린트/TTS 등 오래 걸리는 작업을 메인 로직과 분리하여 순차적으로 처리합니다.
/// appfit_core의 SerialAsyncQueue를 활용합니다.
class OutputQueueService {
  final Ref ref;
  late final SerialAsyncQueue<OutputJob> _queue;

  OutputQueueService(this.ref) {
    _queue = SerialAsyncQueue(
      onProcess: _processItem,
      onError: (item, error, stack) {
        logger.e('[OutputQueue] 출력 처리 중 실패: ${item.order.orderId}',
            error: error, stackTrace: stack);
      },
    );
  }

  /// 신규 주문 출력 작업 추가
  void add(OrderModel order, {bool playSound = true}) {
    _queue.add(NewOrderJob(order, playSound: playSound));
    logger
        .d('[OutputQueue] NEW 작업 추가: ${order.orderId} (대기열: ${_queue.length})');
  }

  /// 사용자 재출력 요청 추가 (라벨 프린터 USB 경쟁 방지를 위해 동일 큐에 직렬화)
  /// 동일 orderId 의 ReprintJob 이 이미 대기 중이면 중복 추가를 무시한다.
  void addReprint(OrderModel order) {
    _queue.add(ReprintJob(order));
    logger.d(
        '[OutputQueue] REPRINT 작업 추가: ${order.orderId} (대기열: ${_queue.length})');
  }

  Future<void> _processItem(OutputJob job) async {
    final outputService = ref.read(outputAppServiceProvider);
    switch (job) {
      case NewOrderJob(order: final order, playSound: final playSound):
        logger.d('[OutputQueue] NEW 출력 시작: ${order.orderId}');
        await outputService.notifyNewOrder(order, playSound: playSound);
        logger.d('[OutputQueue] NEW 출력 완료: ${order.orderId}');
      case ReprintJob(order: final order):
        logger.d('[OutputQueue] REPRINT 출력 시작: ${order.orderId}');
        await outputService.printOrderLabels(order, isReprint: true);
        logger.d('[OutputQueue] REPRINT 출력 완료: ${order.orderId}');
    }
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
