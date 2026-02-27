import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'order_provider.dart';
import '../models/order_model.dart';
import 'kds_unified_providers.dart';
import '../utils/logger.dart';

part 'kds_order_tracking_provider.g.dart';

@Riverpod(keepAlive: true)
class KdsOrderTracking extends _$KdsOrderTracking {
  final Set<String> _previousOrderIds = {};
  final Map<String, OrderStatus> _previousStatuses = {};
  bool _isInitialized = false;

  @override
  void build() {
    // orderProvider를 watch하여 데이터 변경 시마다 build 호출
    final orderState = ref.watch(orderProvider);

    // 초기 로딩 중이거나 데이터가 아직 없는 경우 스킵
    if (orderState.isLoading && orderState.orders.isEmpty) return;

    // 변경 사항 추적 및 애니메이션 트리거
    _trackChanges(orderState.orders);
  }

  void _trackChanges(List<OrderModel> currentOrders) {
    if (!_isInitialized) {
      // 처음 한 번은 현재 상태를 저장만 하고 애니메이션은 트리거하지 않음 (전체 강조 방지)
      _previousOrderIds.addAll(currentOrders.map((o) => o.orderId));
      for (final order in currentOrders) {
        _previousStatuses[order.orderId] = order.status;
      }
      _isInitialized = true;
      logger.d('[KdsOrderTracking] 초기 상태 저장 완료 (${currentOrders.length}개)');
      return;
    }

    final currentOrderIds = currentOrders.map((o) => o.orderId).toSet();

    for (final order in currentOrders) {
      final id = order.orderId;
      final status = order.status;
      final prevStatus = _previousStatuses[id];

      bool shouldHighlight = false;

      // 1. 진행 탭: 신규 주문이 나타났을 때 (상태가 PREPARING으로 진입)
      if (status == OrderStatus.PREPARING) {
        if (!_previousOrderIds.contains(id)) {
          // 완전 신규 주문
          shouldHighlight = true;
        } else if (prevStatus != null && prevStatus != OrderStatus.PREPARING) {
          // 다른 상태에서 PREPARING으로 변경된 경우 (예: 접수 취소 후 재접수 등)
          shouldHighlight = true;
        }
      }

      // 2. 완료 탭: 픽업요청(READY) 상태로 처음 진입하거나, 완료(DONE) 처리됐을 때
      if (status == OrderStatus.READY || status == OrderStatus.DONE) {
        if (!_previousOrderIds.contains(id)) {
          // 완료 탭에 새로 나타남 (이전 상태 추적 안 됨)
          shouldHighlight = true;
        } else if (prevStatus != null && prevStatus != status) {
          // 다른 상태에서 READY나 DONE으로 변경됨
          // (예: PREPARING -> READY, READY -> DONE)
          shouldHighlight = true;
        }
      }

      // 3. 취소 탭: 취소건으로 주문이 나타났을 때 (신규 혹은 상태 변경)
      if (status == OrderStatus.CANCELLED) {
        if (!_previousOrderIds.contains(id) ||
            (prevStatus != null && prevStatus != OrderStatus.CANCELLED)) {
          shouldHighlight = true;
        }
      }

      if (shouldHighlight) {
        logger.d('[KdsOrderTracking] 강조 효과 트리거: $id (상태: $status)');
        // 애니메이션 트리거는 화면 렌더링 프레임 이후로 지연 (Provider 초기화 중 다른 Provider 로직 변경 오류 방지)
        Future.microtask(() {
          ref
              .read(kdsCardAnimationsProvider.notifier)
              .startStatusChangeAnimation(id);
        });
      }
    }

    // 다음 비교를 위해 데이터 업데이트
    _previousOrderIds.clear();
    _previousOrderIds.addAll(currentOrderIds);
    _previousStatuses.clear();
    for (final order in currentOrders) {
      _previousStatuses[order.orderId] = order.status;
    }
  }
}
