import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kokonut_order_agent/models/order_model.dart';
import 'package:kokonut_order_agent/providers/providers.dart';
import 'package:kokonut_order_agent/utils/logger.dart';

class OrderQueueService {
  final Ref ref;
  OrderQueueService(this.ref);
  Timer? _tickTimer;
  static const Duration _tickInterval = Duration(milliseconds: 30);

  void start() {
    stop();
    _tickTimer = Timer.periodic(_tickInterval, (_) {
      try {
        final notifier = ref.read(orderProvider.notifier);
        if (!notifier.hasPendingExternal &&
            !notifier.isBatchCollectingExternal) {
          return;
        }
        notifier.processNextOrdersInBatchExternal();
      } catch (e, s) {
        logger.e('[OrderQueueService] tick error', error: e, stackTrace: s);
      }
    });
    logger.i(
        '[OrderQueueService] started with interval=${_tickInterval.inMilliseconds}ms');
  }

  void stop() {
    _tickTimer?.cancel();
    _tickTimer = null;
    logger.i('[OrderQueueService] stopped');
  }

  // 외부에서 다수 주문을 큐에 넣을 때 사용
  void enqueueAll(List<OrderModel> orders) {
    final notifier = ref.read(orderProvider.notifier);
    for (final order in orders) {
      _enqueueOne(notifier, order);
    }
    // 즉시 한 틱 실행하여 체감 지연 최소화 (busy면 내부에서 즉시 return)
    try {
      notifier.processNextOrdersInBatchExternal();
    } catch (_) {}
    logger.d('[OrderQueueService] enqueued ${orders.length} orders');
  }

  // 중복 방지 포함 단건 큐잉
  void _enqueueOne(Order notifier, OrderModel order) {

    // 상세 중복검사는 OrderProvider 내부에서 처리
    notifier.queueOrderExternal(order);
  }

  // 배치 이동/정렬은 기존 래퍼 사용 (추후 내부 구현 이관 예정)
  List<OrderModel> moveQueueToBatch() {
    return ref.read(orderProvider.notifier).moveQueueToBatchExternal();
  }

  void sortBatchByOrderNumber() {
    ref.read(orderProvider.notifier).sortBatchQueueByOrderNumberExternal();
  }

  bool get isBatchCollecting =>
      ref.read(orderProvider.notifier).isBatchCollectingExternal;
  bool get hasPending => ref.read(orderProvider.notifier).hasPendingExternal;
}

final orderQueueAppServiceProvider = Provider<OrderQueueService>((ref) {
  return OrderQueueService(ref);
});
