import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'dart:async'; // FutureOr 사용 위해 추가 (build 메서드 반환 타입)
import 'package:appfit_order_agent/models/order_model.dart';
import 'package:appfit_order_agent/models/enums/order_cancel_reason.dart';
import 'package:appfit_order_agent/providers/providers.dart';
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

// 출처(키오스크/POS) 노출 설정까지 적용한 과거 주문 목록.
//
// 오늘 목록은 OrderProvider 가 유입 시점에 이미 걸러서 state 에 넣지만
// (`_shouldShowOrder`), 과거 날짜는 API 결과를 그대로 받으므로 여기서 같은 기준을
// 다시 적용한다. 이 단계를 건너뛰면 "노출 OFF 인데 과거 조회에서만 보인다"는
// 날짜별 비대칭이 생긴다. 목록과 상단 건수 칩이 **같은 이 프로바이더**를 봐야
// 건수와 카드 수가 어긋나지 않는다.
final visibleOrderHistoryProvider =
    Provider<AsyncValue<List<OrderModel>>>((ref) {
  final showKiosk = ref.watch(showKioskOrderProvider);
  final showPos = ref.watch(showPosOrderProvider);
  final ordersAsync = ref.watch(orderHistoryProvider);

  return ordersAsync.whenData(
      (orders) => filterOrdersBySourceVisibility(orders, showKiosk, showPos));
});

// 필터링된 주문 목록을 제공하는 프로바이더
// 날짜별 주문과 필터를 결합하여 필터링된 결과 제공
final filteredOrderHistoryProvider =
    Provider<AsyncValue<List<OrderModel>>>((ref) {
  final filter = ref.watch(orderFilterProvider);
  final sortDirection = ref.watch(orderSortDirectionProvider);
  final ordersAsync = ref.watch(visibleOrderHistoryProvider);

  return ordersAsync.when(
    data: (orders) {
      // 필터링 → 정렬(새 리스트 반환)
      final filteredOrders = filterOrders(orders, filter);
      return AsyncData(sortOrders(filteredOrders, sortDirection));
    },
    loading: () => const AsyncLoading(),
    error: (error, stackTrace) => AsyncError(error, stackTrace),
  );
});

// 출처 노출 설정에 따른 필터링 — `OrderHelperMethods.shouldShowOrder` 의 출처 판정과
// 같은 기준(`classifyOrderSource`)을 쓴다. 날짜·상태 조건은 여기서 보지 않는다:
// 주문내역은 과거 날짜를 조회하는 화면이고, 상태는 `filterOrders` 가 따로 거른다.
// 양쪽 모두 ON(기본값)이면 입력 리스트를 그대로 돌려주므로 불필요한 복사·리빌드가 없다.
List<OrderModel> filterOrdersBySourceVisibility(
    List<OrderModel> orders, bool showKiosk, bool showPos) {
  if (showKiosk && showPos) return orders;
  return orders.where((order) {
    switch (classifyOrderSource(order.source)) {
      case OrderSourceType.kiosk:
        return showKiosk;
      case OrderSourceType.pos:
        return showPos;
      case OrderSourceType.app:
        return true;
    }
  }).toList();
}

// 필터에 따른 주문 필터링 로직
// 반환값은 읽기 전용으로 취급할 것 — ALL 분기는 입력 리스트를 그대로(별칭) 돌려주므로
// 호출부에서 제자리 변형하면 원본(= provider 상태 리스트)을 오염시킨다. 정렬이 필요하면
// 새 리스트를 반환하는 `sortOrders` 를 사용한다.
List<OrderModel> filterOrders(List<OrderModel> orders, OrderFilter filter) {
  switch (filter) {
    case OrderFilter.ALL:
      return orders;
    case OrderFilter.COMPLETED:
      // 미픽업은 완료 쪽에 넣는다 — 취소 필터에 섞으면 취소 건수 집계가 오염된다.
      return orders
          .where((order) =>
              order.status == OrderStatus.DONE ||
              order.status == OrderStatus.READY ||
              order.status == OrderStatus.NO_SHOW)
          .toList();
    case OrderFilter.CANCELLED:
      return orders
          .where((order) => order.status == OrderStatus.CANCELLED)
          .toList();
  }
}

// 주문 정렬 함수 — 주문시간(orderedAt) 기준. 앱 전역 정본(KDS 포함).
//
// 입력을 제자리 정렬하지 않고 **정렬된 새 리스트를 반환**한다. 입력이 const 리스트
// (`OrderState.initial().orders`)나 `List.unmodifiable`, 혹은 provider 가 보유한 공유
// 리스트여도 안전하게 만들기 위함이다. 제자리 정렬은 전자에서 UnsupportedError 를,
// 후자에서 통지 없는 상태 변형을 일으킨다.
//
// `Iterable` 을 받으므로 `orders.where(...)` 를 `.toList()` 없이 바로 넘기면 된다
// (복사는 이 함수 안에서 1회만 일어난다).
List<OrderModel> sortOrders(
    Iterable<OrderModel> orders, OrderSortDirection direction) {
  final sorted = orders.toList();
  if (direction == OrderSortDirection.ASC) {
    // 오름차순 (오래된 주문순)
    sorted.sort((a, b) => a.orderedAt.compareTo(b.orderedAt));
  } else {
    // 내림차순 (최신 주문순)
    sorted.sort((a, b) => b.orderedAt.compareTo(a.orderedAt));
  }
  return sorted;
}

// AsyncNotifier는 로딩/에러 상태를 AsyncValue로 관리하므로 별도 State 클래스 불필요

@Riverpod(keepAlive: true)
class OrderHistory extends _$OrderHistory {
  // 캐시 키는 (날짜, 매장) 쌍이다. 매장을 빼면 로그아웃 → 다른 매장 로그인 후
  // 같은 날짜를 조회할 때 이전 매장의 목록을 그대로 돌려준다(건수·목록 stale).
  String? _lastFetchedDate;
  String? _lastFetchedStoreId;

  @override
  Future<List<OrderModel>> build() async {
    // selectedDate는 변경될 수 있으므로 watch 유지
    final selectedDate = ref.watch(selectedDateProvider);

    // 매장 ID 는 **settle 된 값만** 사용한다(shopCatalog 와 동일 규약).
    // 로딩 중 AsyncValue.value 는 이전 매장을 유지하므로 그대로 읽으면, 로그아웃
    // 정리로 storeProvider 가 invalidate 되는 순간 이전 매장 ID 로 조회를 쏴버린다
    // (자격증명은 이미 지워진 뒤라 "토큰 발급 실패" 로 끝나는 헛 요청).
    var storeAsync = ref.watch(storeProvider);
    if (storeAsync.isLoading) {
      await ref.read(storeProvider.future);
      storeAsync = ref.read(storeProvider);
      if (storeAsync.isLoading) {
        logger.d('OrderHistory build: store 미settle — 조회 보류');
        return const <OrderModel>[];
      }
    }
    final storeId = storeAsync.value?.storeId;

    logger.d(
        'OrderHistory build triggered: Date=$selectedDate, StoreId=$storeId, HasValue=${state.hasValue}, LastFetched=$_lastFetchedStoreId/$_lastFetchedDate');

    // 매장 없음 = 세션 없음(로그아웃 직후 / 로그인 전). settle 된 값이므로 "아직
    // 로딩 중" 과 구분된다 → 예외가 아니라 빈 목록으로 조용히 처리한다.
    if (storeId == null || storeId.isEmpty) {
      logger.i('OrderHistory build: 매장 미설정 — 빈 목록 반환(세션 없음)');
      _lastFetchedDate = null;
      _lastFetchedStoreId = null;
      return const <OrderModel>[];
    }

    // 이미 데이터가 있고, 날짜·매장이 모두 그대로면 API 호출 없이 기존 데이터 반환
    if (state.hasValue &&
        selectedDate == _lastFetchedDate &&
        storeId == _lastFetchedStoreId) {
      logger.d(
          'OrderHistory build: Date/Store unchanged and data exists. Returning cached state.');
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

      // API 호출 성공 시 마지막 조회 조건(날짜+매장) 업데이트
      _lastFetchedDate = selectedDate;
      _lastFetchedStoreId = storeId;

      return orders;
    } catch (e, stackTrace) {
      logger.e('OrderHistory build: Error loading orders',
          error: e, stackTrace: stackTrace);
      // 실패 시 마지막 조회 조건 초기화
      _lastFetchedDate = null;
      _lastFetchedStoreId = null;
      rethrow;
    }
  }

  // 주문 취소 기능
  Future<bool> cancelOrder(String orderId,
      {required OrderCancelReason reason}) async {
    logger.i('주문내역 화면에서 주문 취소 요청: $orderId');

    try {
      // 주문 취소는 OrderProvider에 위임
      final orderNotifier = ref.read(orderProvider.notifier);
      final success =
          await orderNotifier.cancelOrder(orderId, reason: reason); // 무조건 호출

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
    // 마지막 조회 조건 초기화하여 다음 build()에서 API 호출 강제
    _lastFetchedDate = null;
    _lastFetchedStoreId = null;
    ref.invalidateSelf();
  }
}

// 기존 Provider 정의 삭제
