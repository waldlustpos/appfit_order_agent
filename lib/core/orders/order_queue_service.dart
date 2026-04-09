import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:appfit_order_agent/models/order_model.dart';
import 'package:appfit_order_agent/providers/providers.dart';
import 'package:appfit_order_agent/utils/logger.dart';

class OrderQueueService {
  final Ref ref;
  OrderQueueService(this.ref);

  // OrderQueueManager가 자체 타이머로 처리하므로 tick 불필요
  void start() {
    logger.i('[OrderQueueService] started');
  }

  void stop() {
    logger.i('[OrderQueueService] stopped');
  }

  // 외부에서 다수 주문을 큐에 넣을 때 사용
  void enqueueAll(List<OrderModel> orders) {
    final notifier = ref.read(orderProvider.notifier);
    for (final order in orders) {
      notifier.queueOrderExternal(order);
    }
    logger.d('[OrderQueueService] enqueued ${orders.length} orders');
  }

  bool get hasPending => ref.read(orderProvider.notifier).hasPendingExternal;
}

final orderQueueAppServiceProvider = Provider<OrderQueueService>((ref) {
  return OrderQueueService(ref);
});
