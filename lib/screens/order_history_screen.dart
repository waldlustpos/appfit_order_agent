import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:appfit_order_agent/providers/providers.dart';
import 'package:appfit_order_agent/widgets/common/app_loading_indicator.dart';
import 'package:appfit_order_agent/widgets/home/order_card_widget.dart';
import 'package:appfit_order_agent/constants/app_styles.dart';
import 'package:appfit_order_agent/widgets/order/order_detail_popup.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:appfit_order_agent/utils/logger.dart';
import 'package:appfit_order_agent/services/platform_service.dart';
import 'package:appfit_order_agent/utils/model_parse_utils.dart';
import 'package:appfit_order_agent/models/order_model.dart';
import 'package:appfit_order_agent/providers/order/order_history_provider.dart';
import 'package:appfit_order_agent/i18n/strings.g.dart';

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
    logToFile(tag: LogTag.UI_ACTION, message: '주문내역 달력 버튼 터치');
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
            calendarStyle: CalendarStyle(
              selectedDecoration: BoxDecoration(
                color: AppStyles.kMainColor,
                shape: BoxShape.circle,
              ),
              todayDecoration: const BoxDecoration(
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
    // 닫힌 후 별도 갱신 불필요: 오늘 날짜 목록/건수는 build 의
    // ref.watch(orderProvider) 가 상태 변경을 자동 반영한다.
    showDialog(
      barrierDismissible: true,
      context: context,
      builder: (context) => OrderDetailPopup(
        order: order,
        isFromHistory: true,
      ),
    );
  }

  void _onDaySelectedInCalendar(DateTime newSelectedDay, DateTime focusedDay) {
    final dateString = newSelectedDay.toString().substring(0, 10);
    logToFile(tag: LogTag.UI_ACTION, message: '주문내역 날짜 선택: $dateString');
    ref.read(selectedDateProvider.notifier).updateDate(dateString);

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
            Padding(
              padding: const EdgeInsets.all(AppSpacing.s12),
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: AppRadius.bMd,
                  boxShadow: AppElevation.soft,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s16,
                  vertical: AppSpacing.s12,
                ),
                child: Row(
                  children: [
                    _buildCalendarButton(selectedDate),
                    const SizedBox(width: AppSpacing.s8),
                    SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        style: AppStyles.outlinedButton(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.s16,
                          ),
                          minimumSize: const Size(100, 48),
                          borderColor: AppStyles.gray3,
                        ).copyWith(
                          textStyle: const WidgetStatePropertyAll(
                            AppTextStyles.body,
                          ),
                        ),
                        onPressed: () {
                          logToFile(
                              tag: LogTag.UI_ACTION,
                              message: '주문내역 오늘조회 버튼 터치');
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
                    ),
                    const SizedBox(width: AppSpacing.s8),
                    _buildSortDirectionToggle(sortDirection),
                    const Spacer(),
                    _buildDetailedCountWidget(isToday),
                    const SizedBox(width: AppSpacing.s8),
                    _buildFilterSegment(selectedFilter),
                  ],
                ),
              ),
            ),
            Expanded(
              // Content display logic
              child:
                  _buildOrderListWidget(isToday, selectedFilter, sortDirection),
            ),
          ],
        ),
      ),
    );
  }

  // 달력 피커 버튼 — 높이 48, gray3 아웃라인, bSm 라운딩
  Widget _buildCalendarButton(String selectedDate) {
    return Material(
      color: Colors.white,
      borderRadius: AppRadius.bSm,
      child: InkWell(
        onTap: _showCalendarDialog,
        borderRadius: AppRadius.bSm,
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s16,
          ),
          decoration: BoxDecoration(
            border: Border.all(color: AppStyles.gray3),
            borderRadius: AppRadius.bSm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.calendar_today, color: AppStyles.kMainColor, size: 18),
              const SizedBox(width: AppSpacing.s8),
              Text(
                selectedDate,
                style: AppTextStyles.body.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppStyles.gray9,
                ),
              ),
              const SizedBox(width: AppSpacing.s4),
              Icon(Icons.arrow_drop_down,
                  color: AppStyles.kMainColor, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  // 필터 세그먼트 — iOS pill 스타일. gray2 트랙 + 선택 pill 흰배경+그림자
  Widget _buildFilterSegment(OrderFilter selectedFilter) {
    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: const BoxDecoration(
        color: AppStyles.gray2,
        borderRadius: AppRadius.bSm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _FilterSegmentButton(
            title: t.order_history.filter_all,
            isSelected: selectedFilter == OrderFilter.ALL,
            onPressed: () {
              logToFile(tag: LogTag.UI_ACTION, message: '주문내역 필터 선택: 전체');
              ref.read(orderFilterProvider.notifier).state = OrderFilter.ALL;
            },
          ),
          _FilterSegmentButton(
            title: t.order_history.filter_completed,
            isSelected: selectedFilter == OrderFilter.COMPLETED,
            onPressed: () {
              logToFile(tag: LogTag.UI_ACTION, message: '주문내역 필터 선택: 완료');
              ref.read(orderFilterProvider.notifier).state =
                  OrderFilter.COMPLETED;
            },
          ),
          _FilterSegmentButton(
            title: t.order_history.filter_cancelled,
            isSelected: selectedFilter == OrderFilter.CANCELLED,
            onPressed: () {
              logToFile(tag: LogTag.UI_ACTION, message: '주문내역 필터 선택: 취소');
              ref.read(orderFilterProvider.notifier).state =
                  OrderFilter.CANCELLED;
            },
          ),
        ],
      ),
    );
  }

  // 상세 건수 표시 — gray2 뱃지 2개 (총/취소)
  Widget _buildDetailedCountWidget(bool isToday) {
    if (isToday) {
      final orderState = ref.watch(orderProvider);
      final orders = orderState.orders;
      final totalCount = orders.length;
      final cancelledCount =
          orders.where((order) => order.status == OrderStatus.CANCELLED).length;
      return _buildCountChipsRow(totalCount, cancelledCount);
    }

    final historyStateAsync = ref.watch(orderHistoryProvider);
    return historyStateAsync.when(
      data: (orders) {
        final totalCount = orders.length;
        final cancelledCount = orders
            .where((order) => order.status == OrderStatus.CANCELLED)
            .length;
        return _buildCountChipsRow(totalCount, cancelledCount);
      },
      loading: () => Text(
        t.order_history.loading,
        style: AppTextStyles.bodySm.copyWith(
          fontWeight: FontWeight.w600,
          color: AppStyles.gray9,
        ),
      ),
      error: (error, stackTrace) => Text(
        t.common.error,
        style: AppTextStyles.bodySm.copyWith(
          fontWeight: FontWeight.w600,
          color: Colors.red,
        ),
      ),
    );
  }

  Widget _buildCountChipsRow(int totalCount, int cancelledCount) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _CountChip(label: t.order_history.total_count(n: totalCount)),
        const SizedBox(width: AppSpacing.s8),
        _CountChip(
          label: t.order_history.cancel_count(n: cancelledCount),
          numberColor: cancelledCount > 0 ? AppStyles.kRed : null,
        ),
      ],
    );
  }

  // 정렬 방향 토글 버튼 — 높이 48, gray3 아웃라인, bSm 라운딩
  Widget _buildSortDirectionToggle(OrderSortDirection sortDirection) {
    return Material(
      color: Colors.white,
      borderRadius: AppRadius.bSm,
      child: InkWell(
        borderRadius: AppRadius.bSm,
        onTap: () {
          final newDirection = sortDirection == OrderSortDirection.ASC
              ? OrderSortDirection.DESC
              : OrderSortDirection.ASC;
          logToFile(
              tag: LogTag.UI_ACTION,
              message: '주문내역 정렬방향 변경: '
                  '${newDirection == OrderSortDirection.ASC ? "오래된순" : "최신순"}');
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(0.0);
          }
          ref.read(orderSortDirectionProvider.notifier).state = newDirection;
        },
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s12),
          decoration: BoxDecoration(
            border: Border.all(color: AppStyles.gray3),
            borderRadius: AppRadius.bSm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                t.order_history.sort,
                style: AppTextStyles.body.copyWith(color: AppStyles.gray9),
              ),
              const SizedBox(width: AppSpacing.s4),
              Icon(
                sortDirection == OrderSortDirection.ASC
                    ? Icons.arrow_upward
                    : Icons.arrow_downward,
                size: 18,
                color: AppStyles.gray9,
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
        loading: () => const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppLoadingIndicator(size: 32),
              SizedBox(height: 16),
              Text('주문 정보를 불러오는 중...'),
            ],
          ),
        ),
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

/// 건수 표시 뱃지 — gray2 배경 통일. numberColor 지정 시 라벨 내 숫자만 강조색.
class _CountChip extends StatelessWidget {
  const _CountChip({required this.label, this.numberColor});

  final String label;
  final Color? numberColor;

  @override
  Widget build(BuildContext context) {
    final baseStyle = AppTextStyles.bodySm.copyWith(
      fontSize: AppStyles.kSectionCountSize,
      fontWeight: FontWeight.w600,
      color: AppStyles.gray9,
    );

    // numberColor 지정 시에만 첫 숫자 그룹을 별도 span 으로 분리해 색 적용.
    // ko/en/ja 모두 generic 하게 RegExp 로 매칭 (총 N건 / Total: N / 合計 N件 등).
    Widget textChild;
    final match = numberColor == null ? null : RegExp(r'\d+').firstMatch(label);
    if (match == null) {
      textChild = Text(label, style: baseStyle);
    } else {
      textChild = Text.rich(
        TextSpan(
          style: baseStyle,
          children: [
            TextSpan(text: label.substring(0, match.start)),
            TextSpan(
              text: match.group(0),
              style: TextStyle(color: numberColor),
            ),
            TextSpan(text: label.substring(match.end)),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s12,
        vertical: AppSpacing.s4,
      ),
      decoration: const BoxDecoration(
        color: AppStyles.gray2,
        borderRadius: AppRadius.bMd,
      ),
      child: textChild,
    );
  }
}

/// 필터 세그먼트 내부 개별 pill 버튼 — iOS 스타일.
/// 선택 시 흰배경 + 약한 그림자 pill, 미선택 시 트랙(gray2) 위 투명 배경.
class _FilterSegmentButton extends StatelessWidget {
  const _FilterSegmentButton({
    required this.title,
    required this.isSelected,
    required this.onPressed,
  });

  final String title;
  final bool isSelected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isSelected ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        boxShadow: isSelected
            ? const [
                BoxShadow(
                  color: Color(0x14000000), // black 8%
                  blurRadius: 4,
                  offset: Offset(0, 1),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onPressed,
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s16),
            child: Text(
              title,
              style: AppTextStyles.body.copyWith(
                color: isSelected ? AppStyles.gray9 : AppStyles.gray6,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
