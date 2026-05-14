import 'package:flutter/foundation.dart' show listEquals;
import '../models/order_model.dart';

// `error: null` 같이 의도적 reset 을 "전달됨" vs "기본값" 으로 구분하기 위한 sentinel.
const Object _unset = Object();

// 주문 상태를 나타내는 클래스
class OrderState {
  final List<OrderModel> orders;
  final bool isLoading;
  final String? error;
  final int activeOrderCount; // 활성 주문 건수 (NEW, ACCEPTED)
  final bool isAutoReceipt; // 자동 접수 설정 (메인 모드)
  final bool isKdsAcceptOrders; // KDS 모드에서 NEW 주문 직접 자동접수 (단독 운영용)
  final int visibleOrderCount; // [NEW] KDS 모드에서 표시할 주문 개수 (Pagination)

  const OrderState({
    required this.orders,
    required this.isLoading,
    this.error,
    this.activeOrderCount = 0,
    this.isAutoReceipt = false,
    this.isKdsAcceptOrders = false,
    this.visibleOrderCount = 12, // 초기값 12개 (FHD 화면 스크롤 확보용)
  });

  /// `error` 만 sentinel 패턴(null 명시 reset 허용). 그 외는 기존 nullable 코어 패턴 유지.
  /// 모든 인자가 동일 값으로 들어오면 `this` 를 그대로 반환해 watcher notify 를 차단.
  OrderState copyWith({
    List<OrderModel>? orders,
    bool? isLoading,
    Object? error = _unset,
    int? activeOrderCount,
    bool? isAutoReceipt,
    bool? isKdsAcceptOrders,
    int? visibleOrderCount,
  }) {
    final nextOrders = orders ?? this.orders;
    final nextIsLoading = isLoading ?? this.isLoading;
    final String? nextError =
        identical(error, _unset) ? this.error : error as String?;
    final nextActiveOrderCount = activeOrderCount ?? this.activeOrderCount;
    final nextIsAutoReceipt = isAutoReceipt ?? this.isAutoReceipt;
    final nextIsKdsAcceptOrders = isKdsAcceptOrders ?? this.isKdsAcceptOrders;
    final nextVisibleOrderCount = visibleOrderCount ?? this.visibleOrderCount;

    final unchanged = identical(nextOrders, this.orders) &&
        nextIsLoading == this.isLoading &&
        nextError == this.error &&
        nextActiveOrderCount == this.activeOrderCount &&
        nextIsAutoReceipt == this.isAutoReceipt &&
        nextIsKdsAcceptOrders == this.isKdsAcceptOrders &&
        nextVisibleOrderCount == this.visibleOrderCount;
    if (unchanged) return this;

    return OrderState(
      orders: nextOrders,
      isLoading: nextIsLoading,
      error: nextError,
      activeOrderCount: nextActiveOrderCount,
      isAutoReceipt: nextIsAutoReceipt,
      isKdsAcceptOrders: nextIsKdsAcceptOrders,
      visibleOrderCount: nextVisibleOrderCount,
    );
  }

  static OrderState initial() {
    // 초기 상태 로드는 build에서 PreferenceService 통해 수행
    return const OrderState(
      orders: [],
      isLoading: false,
      activeOrderCount: 0,
      isAutoReceipt: false,
      isKdsAcceptOrders: false,
      visibleOrderCount: 12, // 초기값 12개
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is OrderState &&
        isLoading == other.isLoading &&
        error == other.error &&
        activeOrderCount == other.activeOrderCount &&
        isAutoReceipt == other.isAutoReceipt &&
        isKdsAcceptOrders == other.isKdsAcceptOrders &&
        visibleOrderCount == other.visibleOrderCount &&
        (identical(orders, other.orders) || listEquals(orders, other.orders));
  }

  @override
  int get hashCode => Object.hash(
        orders.length,
        isLoading,
        error,
        activeOrderCount,
        isAutoReceipt,
        isKdsAcceptOrders,
        visibleOrderCount,
      );
}
