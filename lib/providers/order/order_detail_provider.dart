import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:appfit_order_agent/models/order_model.dart';
import 'package:appfit_order_agent/providers/providers.dart';

part 'order_detail_provider.g.dart';

@riverpod
class OrderDetail extends _$OrderDetail {
  @override
  ({
    OrderModel? order,
    bool isLoading,
    String? errorMessage,
  }) build() {
    return (
      order: null,
      isLoading: false,
      errorMessage: null,
    );
  }

  void setOrder(OrderModel order) {
    state = (
      order: order,
      isLoading: state.isLoading,
      errorMessage: state.errorMessage,
    );
  }

  void setLoading(bool isLoading) {
    state = (
      order: state.order,
      isLoading: isLoading,
      errorMessage: state.errorMessage,
    );
  }

  void setError(String? errorMessage) {
    state = (
      order: state.order,
      isLoading: state.isLoading,
      errorMessage: errorMessage,
    );
  }

  Future<void> fetchOrderDetail(String orderId, String storeId) async {
    setLoading(true);
    setError(null);

    try {
      final orderNotifier = ref.read(orderProvider.notifier);
      final detailedOrder = await orderNotifier.fetchOrderDetail(orderId);
      if (detailedOrder != null) {
        setOrder(detailedOrder);
      } else {
        setError('주문 상세 정보를 불러올 수 없습니다.');
      }
    } catch (e, s) {
      setError(e.toString());
    } finally {
      setLoading(false);
    }
  }

  void updateOrderStatus(OrderStatus newStatus) {
    if (state.order == null) return;

    final updatedOrder = state.order!.copyWith(
      status: newStatus,
      orderStatus: _getStatusCode(newStatus),
      updateTime: DateTime.now(),
    );
    setOrder(updatedOrder);
  }

  String _getStatusCode(OrderStatus status) {
    switch (status) {
      case OrderStatus.NEW:
        return "2003";
      case OrderStatus.PREPARING:
        return "2007";
      case OrderStatus.READY:
        return "2009";
      case OrderStatus.DONE:
        return "2020";
      case OrderStatus.CANCELLED:
        return "9001";
    }
  }
}
