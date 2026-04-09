import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'dart:async'; // FutureOr 사용 위해 추가 (build 메서드 반환 타입)
import '../models/order_model.dart';
import 'providers.dart';
// PrintService import 추가
import 'package:appfit_order_agent/utils/logger.dart'; // logger import 추가
import 'package:appfit_order_agent/utils/model_parse_utils.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'order_history_provider.g.dart';

// 주문 필터 상태를 관리하는 enum
enum OrderFilter {
  ALL, // 전체 주문
  COMPLETED, // 픽업 완료 주문
  CANCELLED, // 취소된 주문
}

// 주문 정렬 방향을 관리하는 enum
enum OrderSortDirection {
  ASC, // 오름차순 (주문번호 낮은순)
  DESC, // 내림차순 (주문번호 높은순)
}

// 주문 필터를 위한 프로바이더
final orderFilterProvider =
    StateProvider<OrderFilter>((ref) => OrderFilter.ALL);

// 주문 정렬 방향을 위한 프로바이더
final orderSortDirectionProvider =
    StateProvider<OrderSortDirection>((ref) => OrderSortDirection.DESC);

// 필터링된 주문 목록을 제공하는 프로바이더
// 날짜별 주문과 필터를 결합하여 필터링된 결과 제공
final filteredOrderHistoryProvider =
    Provider<AsyncValue<List<OrderModel>>>((ref) {
  final filter = ref.watch(orderFilterProvider);
  final sortDirection = ref.watch(orderSortDirectionProvider);
  final ordersAsync = ref.watch(orderHistoryProvider);

  return ordersAsync.when(
    data: (orders) {
      // 필터링
      final filteredOrders = filterOrders(orders, filter);

      // 정렬
      sortOrders(filteredOrders, sortDirection);

      return AsyncData(filteredOrders);
    },
    loading: () => const AsyncLoading(),
    error: (error, stackTrace) => AsyncError(error, stackTrace),
  );
});

// 필터에 따른 주문 필터링 로직
List<OrderModel> filterOrders(List<OrderModel> orders, OrderFilter filter) {
  switch (filter) {
    case OrderFilter.ALL:
      return orders;
    case OrderFilter.COMPLETED:
      return orders
          .where((order) =>
              order.status == OrderStatus.DONE ||
              order.status == OrderStatus.READY)
          .toList();
    case OrderFilter.CANCELLED:
      return orders
          .where((order) => order.status == OrderStatus.CANCELLED)
          .toList();
  }
}

// 주문 정렬 함수
void sortOrders(List<OrderModel> orders, OrderSortDirection direction) {
  if (direction == OrderSortDirection.ASC) {
    // 오름차순 (낮은 번호부터)
    orders.sort((a, b) => a.shopOrderNo.compareTo(b.shopOrderNo));
  } else {
    // 내림차순 (높은 번호부터)
    orders.sort((a, b) => b.shopOrderNo.compareTo(a.shopOrderNo));
  }
}

// AsyncNotifier는 로딩/에러 상태를 AsyncValue로 관리하므로 별도 State 클래스 불필요

@Riverpod(keepAlive: true)
class OrderHistory extends _$OrderHistory {
  String? _lastFetchedDate;

  @override
  Future<List<OrderModel>> build() async {
    // selectedDate는 변경될 수 있으므로 watch 유지
    final selectedDate = ref.watch(selectedDateProvider);

    // storeId는 변경되지 않으므로 read 사용 (Provider 빌드 시점 기준)
    // OrderHistoryScreen 접근 시점에 storeProvider는 이미 로드 완료되었다고 가정
    final storeId = ref.read(storeProvider).value?.storeId;

    logger.d(
        'OrderHistory build triggered: Date=$selectedDate, StoreId=$storeId, HasValue=${state.hasValue}, LastFetchedDate=$_lastFetchedDate');

    // 매장 ID 유효성 검사 (필수)
    if (storeId == null || storeId.isEmpty) {
      logger.e(
          'OrderHistory build: StoreId is null or empty. Cannot fetch orders.');
      // storeProvider가 로드되지 않은 상태일 수 있음.
      // 이 Provider가 사용되는 시점에는 storeId가 반드시 있어야 함.
      throw Exception('매장 ID를 사용할 수 없습니다. 로그인이 필요하거나 앱 초기화 오류일 수 있습니다.');
    }

    // 이미 데이터가 있고, 날짜가 변경되지 않았다면 API 호출 없이 기존 데이터 반환
    if (state.hasValue && selectedDate == _lastFetchedDate) {
      logger.d(
          'OrderHistory build: Date unchanged and data exists. Returning cached state.');
      return state.value!; // API 호출 없이 즉시 반환
    }

    // --- API 호출 로직 ---
    logger.i(
        'OrderHistory build: Fetching orders for Date=$selectedDate, StoreId=$storeId');
    final apiService = ref.read(apiServiceProvider);
    try {
      final orders = await apiService.getOrders(storeId,
          startDate: selectedDate,
          endDate: selectedDate); // read로 가져온 storeId 사용
      logger.i('OrderHistory build: Loaded ${orders.length} orders.');

      // API 호출 성공 시 마지막 조회 날짜 업데이트
      _lastFetchedDate = selectedDate;

      return orders;
    } catch (e, stackTrace) {
      logger.e('OrderHistory build: Error loading orders',
          error: e, stackTrace: stackTrace);
      // 실패 시 마지막 조회 조건 초기화
      _lastFetchedDate = null;
      rethrow;
    }
  }

  // 주문 취소 기능
  Future<bool> cancelOrder(String orderId) async {
    logger.i('주문내역 화면에서 주문 취소 요청: $orderId');

    try {
      // 주문 취소는 OrderProvider에 위임
      final orderNotifier = ref.read(orderProvider.notifier);
      final success = await orderNotifier.cancelOrder(orderId); // 무조건 호출

      if (success) {
        logger.i('주문내역 화면에서 주문 취소 성공: $orderId');

        // 오늘 날짜가 아닐 때만 로컬 상태 업데이트
        // 오늘 날짜의 경우 OrderProvider를 통해 자동 갱신됨
        final selectedDate = ref.read(selectedDateProvider);
        if (selectedDate != todayDateString() && state.hasValue) {
          // --- 취소 성공 후 현재 목록 업데이트 로직 ---
          final currentOrders = state.value!;
          final orderIndex =
              currentOrders.indexWhere((o) => o.orderId == orderId);
          if (orderIndex != -1) {
            final updatedOrders = List<OrderModel>.from(currentOrders);
            final orderToUpdate = updatedOrders[orderIndex];
            final updatedOrder = orderToUpdate.copyWith(
              status: OrderStatus.CANCELLED,
              orderStatus: '',
              updateTime: DateTime.now(),
            );
            updatedOrders[orderIndex] = updatedOrder;
            state = AsyncData(updatedOrders); // 로컬 상태 업데이트
            logger.d('OrderHistory: 로컬 상태에서 주문($orderId) 취소로 업데이트 완료');
          } else {
            logger
                .d('OrderHistory: 취소된 주문($orderId)이 현재 목록에 없어 로컬 상태 업데이트는 스킵.');
          }
        } else if (selectedDate == todayDateString()) {
          logger.d('OrderHistory: 오늘 날짜 주문 취소, OrderProvider에서 처리된 상태 사용');
          // 필요한 경우 강제 리빌드 트리거 가능
          // ref.invalidateSelf();
        }

        return true;
      } else {
        logger.w('주문내역 화면에서 주문 취소 실패: $orderId');
        // OrderProvider에서 설정한 에러 메시지를 가져와서 UI에 표시 가능
        // final errorMessage = ref.read(orderProvider).error;
        // _showErrorSnackbar(errorMessage ?? '주문 취소 실패');
        return false;
      }
    } catch (e, stackTrace) {
      logger.e('주문내역 화면에서 주문 취소 처리 중 오류', error: e, stackTrace: stackTrace);
      // _showErrorSnackbar('주문 취소 중 오류 발생: $e');
      return false;
    }
  }

  // 날짜 변경 등으로 화면 강제 갱신 메서드
  Future<void> refreshOrders() async {
    logger.i('OrderHistory refreshOrders: 주문 목록 강제 갱신');
    // 마지막 조회 날짜 초기화하여 다음 build()에서 API 호출 강제
    _lastFetchedDate = null;
    ref.invalidateSelf();
  }
}

// 기존 Provider 정의 삭제
