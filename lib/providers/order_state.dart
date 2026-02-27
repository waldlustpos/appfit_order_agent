import '../models/order_model.dart';

// 주문 상태를 나타내는 클래스
class OrderState {
  final List<OrderModel> orders;
  final bool isLoading;
  final String? error;
  final int activeOrderCount; // 활성 주문 건수 (NEW, ACCEPTED)
  final bool isAutoReceipt; // 자동 접수 설정
  final int visibleOrderCount; // [NEW] KDS 모드에서 표시할 주문 개수 (Pagination)

  const OrderState({
    required this.orders,
    required this.isLoading,
    this.error,
    this.activeOrderCount = 0,
    this.isAutoReceipt = false,
    this.visibleOrderCount = 12, // 초기값 12개 (FHD 화면 스크롤 확보용)
  });

  OrderState copyWith({
    List<OrderModel>? orders,
    bool? isLoading,
    String? error,
    int? activeOrderCount,
    bool? isAutoReceipt,
    int? visibleOrderCount,
  }) {
    return OrderState(
      orders: orders ?? this.orders,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
      activeOrderCount: activeOrderCount ?? this.activeOrderCount,
      isAutoReceipt: isAutoReceipt ?? this.isAutoReceipt,
      visibleOrderCount: visibleOrderCount ?? this.visibleOrderCount,
    );
  }

  static OrderState initial() {
    // 초기 상태 로드는 build에서 PreferenceService 통해 수행
    return const OrderState(
      orders: [],
      isLoading: false,
      activeOrderCount: 0,
      isAutoReceipt: false,
      visibleOrderCount: 12, // 초기값 12개
    );
  }
}
