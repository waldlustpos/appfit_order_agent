import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';
import '../providers/providers.dart';
import '../widgets/home/order_card_widget.dart';
import '../constants/app_styles.dart';
import '../widgets/order/order_detail_popup.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:appfit_order_agent/utils/logger.dart';
import 'package:appfit_order_agent/utils/model_parse_utils.dart';
import '../models/order_model.dart';
import '../providers/order_history_provider.dart';
import '../i18n/strings.g.dart';

class OrderHistoryScreen extends ConsumerStatefulWidget {
  const OrderHistoryScreen({super.key});

  @override
  ConsumerState<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends ConsumerState<OrderHistoryScreen> {
  // 스크롤 컨트롤러
  final ScrollController _scrollController = ScrollController();

  // 이전 정렬 방향을 추적하여 정렬 변경 감지
  OrderSortDirection? _previousSortDirection;

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('ko_KR', null);
    logger.i('initState: OrderHistoryScreen initialized.');
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // 정렬 변경 감지 (로깅 목적, 실제 스크롤 초기화는 버튼 클릭 시 즉시 처리)
  void _detectSortChangeAndResetScroll(
      OrderSortDirection currentSortDirection) {
    if (_previousSortDirection != null &&
        _previousSortDirection != currentSortDirection) {
      logger.d(
          'OrderHistory: 정렬 변경 감지됨 - ${currentSortDirection == OrderSortDirection.ASC ? t.order_history.sort : t.order_history.sort}');
    }

    _previousSortDirection = currentSortDirection;
  }

  void _showCalendarDialog() {
    final selectedDay = DateTime.parse(ref.read(selectedDateProvider));
    final focusedDayForCalendar = selectedDay;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        contentPadding: const EdgeInsets.all(0),
        content: SizedBox(
          width: 300,
          height: 400,
          child: TableCalendar(
            firstDay: DateTime.utc(2024, 1, 1),
            lastDay: DateTime.now(),
            focusedDay: focusedDayForCalendar,
            locale: 'ko_KR',
            selectedDayPredicate: (day) {
              return isSameDay(selectedDay, day);
            },
            onDaySelected: _onDaySelectedInCalendar,
            headerStyle: const HeaderStyle(
              formatButtonVisible: false,
              titleCentered: true,
            ),
            calendarStyle: const CalendarStyle(
              selectedDecoration: BoxDecoration(
                color: AppStyles.kMainColor,
                shape: BoxShape.circle,
              ),
              todayDecoration: BoxDecoration(
                color: Colors.orange,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showOrderDetails(order) {
    showDialog(
      barrierDismissible: true,
      context: context,
      builder: (context) => OrderDetailPopup(
        order: order,
        isFromHistory: true,
      ),
    ).then((_) {
      // 다이얼로그가 닫힌 후 오늘 날짜인 경우 상태를 다시 가져오기
      final selectedDate = ref.read(selectedDateProvider);
      if (selectedDate == todayDateString()) {
        // 오늘 날짜이면 orderProvider의 상태를 반영
        setState(() {
          // 화면 갱신 트리거
        });
      }
    });
  }

  void _onDaySelectedInCalendar(DateTime newSelectedDay, DateTime focusedDay) {
    ref
        .read(selectedDateProvider.notifier)
        .updateDate(newSelectedDay.toString().substring(0, 10));

    // 필터를 전체주문(ALL)으로 설정
    ref.read(orderFilterProvider.notifier).state = OrderFilter.ALL;

    // 정렬 방향을 내림차순(최신순)으로 초기화
    ref.read(orderSortDirectionProvider.notifier).state =
        OrderSortDirection.DESC;

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final selectedDate = ref.watch(selectedDateProvider);
    final isToday = selectedDate == todayDateString();
    final selectedFilter = ref.watch(orderFilterProvider);
    final sortDirection = ref.watch(orderSortDirectionProvider);

    // 정렬 변경 감지 및 스크롤 위치 초기화
    _detectSortChangeAndResetScroll(sortDirection);

    return Scaffold(
      body: Container(
        color: AppStyles.gray1,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12.0),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Colors.grey[400]!),
                ),
              ),
              child: Row(
                children: [
                  InkWell(
                    onTap: _showCalendarDialog,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16.0, vertical: 8.0),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[400]!),
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.calendar_today,
                              color: AppStyles.kMainColor),
                          const SizedBox(width: 12.0),
                          Text(
                            selectedDate,
                            style: const TextStyle(
                              fontSize: 16.0,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.arrow_drop_down,
                              color: AppStyles.kMainColor, size: 20),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12.0),
                  ElevatedButton(
                    style: AppStyles.outlinedButton(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      minimumSize: const Size(100, 48),
                      borderColor: Colors.grey.shade300,
                    ).copyWith(
                      textStyle: WidgetStatePropertyAll(
                        const TextStyle(fontSize: 16),
                      ),
                    ),
                    onPressed: () {
                      ref
                          .read(selectedDateProvider.notifier)
                          .updateDate(todayDateString());

                      ref.read(orderFilterProvider.notifier).state =
                          OrderFilter.ALL;

                      ref.read(orderSortDirectionProvider.notifier).state =
                          OrderSortDirection.DESC;
                    },
                    child: Text(
                      t.order_history.search_today,
                      textAlign: TextAlign.center,
                    ),
                  ),

                  const SizedBox(width: 8.0),
                  // 정렬 방향 버튼 추가
                  _buildSortDirectionToggle(sortDirection),

                  const Spacer(),

                  const SizedBox(width: 16.0),

                  // Total count display logic - new format
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12.0, vertical: 8.0),
                    child: _buildDetailedCountWidget(isToday),
                  ),
                  const SizedBox(width: 8.0),

                  // 필터 버튼 그룹 - 오른쪽으로 이동
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        _buildFilterButton(
                          context: context,
                          title: t.order_history.filter_all,
                          isSelected: selectedFilter == OrderFilter.ALL,
                          onPressed: () => ref
                              .read(orderFilterProvider.notifier)
                              .state = OrderFilter.ALL,
                          leftRadius: true,
                        ),
                        // 구분선 추가
                        Container(
                          width: 1,
                          height: 24,
                          color: Colors.grey.shade300,
                        ),
                        _buildFilterButton(
                          context: context,
                          title: t.order_history.filter_completed,
                          isSelected: selectedFilter == OrderFilter.COMPLETED,
                          onPressed: () => ref
                              .read(orderFilterProvider.notifier)
                              .state = OrderFilter.COMPLETED,
                        ),
                        // 구분선 추가
                        Container(
                          width: 1,
                          height: 24,
                          color: Colors.grey.shade300,
                        ),
                        _buildFilterButton(
                          context: context,
                          title: t.order_history.filter_cancelled,
                          isSelected: selectedFilter == OrderFilter.CANCELLED,
                          onPressed: () => ref
                              .read(orderFilterProvider.notifier)
                              .state = OrderFilter.CANCELLED,
                          rightRadius: true,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              // Content display logic
              child: _buildOrderListWidget(
                  isToday, selectedFilter, sortDirection),
            ),
          ],
        ),
      ),
    );
  }

  // 필터 버튼 위젯
  Widget _buildFilterButton({
    required BuildContext context,
    required String title,
    required bool isSelected,
    required VoidCallback onPressed,
    bool leftRadius = false,
    bool rightRadius = false,
  }) {
    return InkWell(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppStyles.kMainColor : Colors.white,
          borderRadius: BorderRadius.horizontal(
            left: leftRadius ? const Radius.circular(8) : Radius.zero,
            right: rightRadius ? const Radius.circular(8) : Radius.zero,
          ),
        ),
        child: Text(
          title,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.black87,
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  // 상세 건수 표시 위젯 (총n건 | 취소 n건 | 자동취소 n건)
  Widget _buildDetailedCountWidget(bool isToday) {
    if (isToday) {
      final orderState = ref.watch(orderProvider);
      final orders = orderState.orders;

      // 총 건수
      final totalCount = orders.length;

      // 취소 건수 (일반 취소)
      final cancelledCount =
          orders.where((order) => order.status == OrderStatus.CANCELLED).length;

      return Row(
        children: [
          Text(
            t.order_history.total_count(n: totalCount),
            style: const TextStyle(
              fontSize: AppStyles.kSectionCountSize,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            '|',
            style: TextStyle(
              fontSize: AppStyles.kSectionCountSize,
              color: Colors.grey,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            t.order_history.cancel_count(n: cancelledCount),
            style: const TextStyle(
              fontSize: AppStyles.kSectionCountSize,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );
    } else {
      final historyStateAsync = ref.watch(orderHistoryProvider);

      return historyStateAsync.when(
        data: (orders) {
          // 총 건수
          final totalCount = orders.length;

          // 취소 건수 (일반 취소)
          final cancelledCount = orders
              .where((order) => order.status == OrderStatus.CANCELLED)
              .length;

          return Row(
            children: [
              Text(
                t.order_history.total_count(n: totalCount),
                style: const TextStyle(
                  fontSize: AppStyles.kSectionCountSize,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                '|',
                style: TextStyle(
                  fontSize: AppStyles.kSectionCountSize,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                t.order_history.cancel_count(n: cancelledCount),
                style: const TextStyle(
                  fontSize: AppStyles.kSectionCountSize,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          );
        },
        loading: () => Text(
          t.order_history.loading,
          style: const TextStyle(
            fontSize: AppStyles.kSectionCountSize,
            fontWeight: FontWeight.w500,
            color: Colors.grey,
          ),
        ),
        error: (error, stackTrace) => Text(
          t.common.error,
          style: const TextStyle(
            fontSize: AppStyles.kSectionCountSize,
            fontWeight: FontWeight.w500,
            color: Colors.red,
          ),
        ),
      );
    }
  }

  // 정렬 방향 토글 버튼 — sortDirection은 build()에서 전달받음
  Widget _buildSortDirectionToggle(OrderSortDirection sortDirection) {

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        onTap: () {
          // 정렬 변경 전에 즉시 스크롤 초기화
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(0.0);
          }

          // 정렬 방향 토글
          ref.read(orderSortDirectionProvider.notifier).state =
              sortDirection == OrderSortDirection.ASC
                  ? OrderSortDirection.DESC
                  : OrderSortDirection.ASC;
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Text(
                t.order_history.sort,
                style: const TextStyle(
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                sortDirection == OrderSortDirection.ASC
                    ? Icons.arrow_upward
                    : Icons.arrow_downward,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Helper widget to build the order list based on the selected date
  // filter, sortDirection은 build()에서 전달받음
  Widget _buildOrderListWidget(
      bool isToday, OrderFilter filter, OrderSortDirection sortDirection) {
    if (isToday) {
      // 오늘 날짜인 경우 orderProvider + 필터 적용
      final orderState = ref.watch(orderProvider);
      final orders = orderState.orders;

      // 1. 상태 필터링은 order_history_provider의 filterOrders 함수 사용
      final filteredOrders = filterOrders(orders, filter);

      // 2. 정렬 적용
      sortOrders(filteredOrders, sortDirection);

      if (filteredOrders.isEmpty) {
        return Center(
          child: Text(
            filter == OrderFilter.ALL
                ? t.order_history.no_data_today
                : filter == OrderFilter.COMPLETED
                    ? t.order_history.no_completed_today
                    : t.order_history.no_cancelled_today,
            style: const TextStyle(
              fontSize: 16.0,
              color: Colors.grey,
            ),
          ),
        );
      }
      return _buildOrderGrid(filteredOrders);
    } else {
      // 다른 날짜인 경우 filteredOrderHistoryProvider 사용
      final filteredOrdersAsync = ref.watch(filteredOrderHistoryProvider);

      return filteredOrdersAsync.when(
        data: (orders) {
          if (orders.isEmpty) {
            return Center(
              child: Text(
                filter == OrderFilter.ALL
                    ? t.order_history.no_data_date
                    : filter == OrderFilter.COMPLETED
                        ? t.order_history.no_completed_date
                        : t.order_history.no_cancelled_date,
                style: const TextStyle(
                  fontSize: 16.0,
                  color: Colors.grey,
                ),
              ),
            );
          }
          return _buildOrderGrid(orders);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) {
          logger.e('Build Error State for History',
              error: error, stackTrace: stackTrace);
          return Center(
            child: Text(
              t.order_history.error_load(error: error.toString()),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
          );
        },
      );
    }
  }

  // Reusable GridView builder
  Widget _buildOrderGrid(List<OrderModel> orders) {
    return RawScrollbar(
      controller: _scrollController, // 스크롤바에 컨트롤러 명시적 지정
      radius: const Radius.circular(10),
      thumbColor: Colors.grey[400],
      fadeDuration: const Duration(milliseconds: 300),
      child: GridView.builder(
        controller: _scrollController, // 스크롤 컨트롤러 추가
        padding: const EdgeInsets.all(8.0),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 8,
          childAspectRatio: 1.0,
          crossAxisSpacing: 8.0,
          mainAxisSpacing: 8.0,
        ),
        itemCount: orders.length,
        itemBuilder: (context, index) {
          final order = orders[index];
          return SizedBox(
            width: 150,
            height: 150,
            child: OrderCardWidget(
              order: order,
              onTap: () => _showOrderDetails(order),
            ),
          );
        },
      ),
    );
  }
}
