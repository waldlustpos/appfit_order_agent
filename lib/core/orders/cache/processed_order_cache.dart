import 'package:appfit_core/appfit_core.dart' as core;
import 'package:appfit_order_agent/models/enums/order_status.dart';

/// (orderId, status) 조합 단위로 이미 큐에 들어간 주문을 추적하여 중복 enqueue를 방지하는
/// 도메인 래퍼.
///
/// 실제 저장은 `appfit_core` 의 [core.ProcessedOrderCache] 가 담당하고, 여기서는
/// `OrderStatus` 와의 키 합성만 수행한다. 키 포맷은 `'${orderId}_${status}'`.
///
/// **목적**: WebSocket 과 REST 폴링이 동일한 (orderId, status) 페어를 동시 발행하는
/// 이중 소스 race 를 차단한다. 호출자가 키 포맷을 직접 만들지 않도록
/// `containsOrderStatus` / `addOrderStatus` API 만 사용해야 한다.
///
/// SocketEventSuppressor 와의 차이:
/// - SocketEventSuppressor 는 **클라이언트 자가 PUT 직후 echo 이벤트** 1회성 차단(10초, 키=eventType).
/// - ProcessedOrderCache 는 **소스 무관 (orderId, status) enqueue 중복** 차단(30분, 키=status).
class ProcessedOrderCache {
  final core.ProcessedOrderCache _delegate = core.ProcessedOrderCache();

  /// (orderId, status) 조합이 이미 처리되었는지 확인.
  bool containsOrderStatus(String orderId, OrderStatus status) {
    return _delegate.contains(_makeKey(orderId, status));
  }

  /// (orderId, status) 조합을 처리됨으로 기록.
  void addOrderStatus(String orderId, OrderStatus status) {
    _delegate.add(_makeKey(orderId, status));
  }

  /// 캐시 초기화
  void clear() => _delegate.clear();

  /// 디버깅용: 현재 캐시 크기 확인
  int get size => _delegate.size;

  String _makeKey(String orderId, OrderStatus status) => '${orderId}_$status';
}
