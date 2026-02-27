import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:appfit_order_agent/widgets/kds/kds_card_grid_layout_widget.dart';
import 'package:table_calendar/table_calendar.dart';
import '../providers/kds_unified_providers.dart';
import '../providers/kds_order_tracking_provider.dart';
import '../providers/providers.dart';
import '../services/preference_service.dart';
import '../constants/app_styles.dart';
import '../constants/card_types.dart';
import '../utils/logger.dart';
import '../widgets/order/order_detail_popup.dart';
import '../widgets/common/common_dialog.dart';
import '../utils/kds_utils.dart' as kds_utils;
import '../models/order_model.dart';
import '../widgets/home/order_card_widget.dart';
import '../i18n/strings.g.dart';

// 키오스크 주문 노출 설정을 위한 StateProvider (order_history_screen과 동일)
final kioskOrderVisibilityProvider = StateProvider<bool>((ref) {
  final preferenceService = PreferenceService();
  return preferenceService.getShowKioskOrder();
});

class KdsScreen extends ConsumerStatefulWidget {
  const KdsScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<KdsScreen> createState() => _KdsScreenState();
}

class _KdsScreenState extends ConsumerState<KdsScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  late PageController _pageController;

  // 이전 주문 ID 목록을 추적하여 신규 주문 감지 (스크롤 제어용)
  Set<String> _previousOrderIds = <String>{};

  // 탭별 스크롤 컨트롤러 ID 상수
  static const String _mainGridScrollerId = 'main_grid';
  static const String _progressTabScrollerId = 'progress_tab';
  static const String _pickupTabScrollerId = 'pickup_tab';
  static const String _completedTabScrollerId = 'completed_tab';
  static const String _cancelledTabScrollerId = 'cancelled_tab';

  // 이전 정렬 방향을 추적하여 정렬 변경 감지
  OrderSortDirection? _previousSortDirection;

  // 탭 중복 선택 감지를 위한 변수
  int? _lastSelectedTabIndex;

  // Timer 관리를 위한 맵 (메모리 누수 방지)
  final Map<String, Timer> _timers = {};

  @override
  void initState() {
    super.initState();
    // Provider에서 저장된 탭 인덱스로 초기화
    final savedTabIndex = ref.read(kdsTabIndexProvider);
    _tabController =
        TabController(length: 5, vsync: this, initialIndex: savedTabIndex);
    _pageController = PageController(initialPage: savedTabIndex);

    // KDS 화면에서는 전체 주문 필터 사용 (위젯 빌드 완료 후 실행)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(orderFilterProvider.notifier).state = OrderFilter.ALL;
      }
    });

    // 초기 탭 인덱스 설정
    _lastSelectedTabIndex = savedTabIndex;

    // 초기 탭의 정렬 방향 설정 및 스크롤 컨트롤러 초기화 (위젯 빌드 완료 후 실행)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        try {
          final initialTabIndex = ref.read(kdsTabIndexProvider);
          final initialSortDirection = ref
              .read(kdsTabSortDirectionsProvider.notifier)
              .getSortDirection(initialTabIndex);
          ref
              .read(kdsSortDirectionProvider.notifier)
              .updateDirection(initialSortDirection);

          // 탭별 스크롤 컨트롤러 초기화 (Provider를 통해 관리)
          final scrollControllerNotifier =
              ref.read(kdsScrollControllerMapProvider.notifier);
          scrollControllerNotifier.getOrCreateController(_mainGridScrollerId);
          scrollControllerNotifier
              .getOrCreateController(_progressTabScrollerId);
          scrollControllerNotifier.getOrCreateController(_pickupTabScrollerId);
          scrollControllerNotifier
              .getOrCreateController(_completedTabScrollerId);
          scrollControllerNotifier
              .getOrCreateController(_cancelledTabScrollerId);

          logger.d(
              'KDS: 초기화 완료 - 탭: $initialTabIndex, 정렬: ${initialSortDirection.name}');
        } catch (e) {
          logger.d('KDS initState: 초기화 중 오류: $e');
        }
      }
    });

    // 탭과 페이지 동기화
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        final currentTabIndex = _tabController.index;

        // 중복 선택 감지: 같은 탭을 다시 선택한 경우 스크롤 초기화
        if (_lastSelectedTabIndex == currentTabIndex) {
          _resetScrollForTab(currentTabIndex);
        }

        _pageController.jumpToPage(currentTabIndex);

        // Provider 상태 변경을 다음 프레임으로 지연
        Future.microtask(() {
          if (mounted) {
            // Provider에 현재 탭 인덱스 저장
            ref.read(kdsTabIndexProvider.notifier).updateIndex(currentTabIndex);

            // 탭 변경 시 해당 탭의 정렬 방향 적용
            final tabSortDirection = ref
                .read(kdsTabSortDirectionsProvider.notifier)
                .getSortDirection(currentTabIndex);
            ref
                .read(kdsSortDirectionProvider.notifier)
                .updateDirection(tabSortDirection);

            logger.d(
                'KDS: 탭 변경 - 탭: $currentTabIndex, 정렬: ${tabSortDirection == OrderSortDirection.ASC ? "오래된 주문순" : "최신 주문순"}');
          }
        });

        // 마지막 선택된 탭 인덱스 업데이트
        _lastSelectedTabIndex = currentTabIndex;
      }
    });

    // 페이지 변경 시 탭도 동기화 (무한 루프 방지)
    _pageController.addListener(() {
      // PageController가 초기화되었는지 확인
      if (_pageController.hasClients) {
        final currentPage = _pageController.page?.round() ?? 0;
        if (_tabController.index != currentPage &&
            !_tabController.indexIsChanging) {
          _tabController.animateTo(currentPage);

          // Provider 상태 변경을 다음 프레임으로 지연
          Future.microtask(() {
            if (mounted) {
              // Provider에 현재 탭 인덱스 저장
              ref.read(kdsTabIndexProvider.notifier).updateIndex(currentPage);

              // 페이지 변경 시 해당 탭의 정렬 방향 적용
              final tabSortDirection = ref
                  .read(kdsTabSortDirectionsProvider.notifier)
                  .getSortDirection(currentPage);
              ref
                  .read(kdsSortDirectionProvider.notifier)
                  .updateDirection(tabSortDirection);

              logger.d(
                  'KDS: 페이지 변경 - 탭: $currentPage, 정렬: ${tabSortDirection == OrderSortDirection.ASC ? "오래된 주문순" : "최신 주문순"}');
            }
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _pageController.dispose();

    // 모든 Timer 정리 (메모리 누수 방지)
    _cancelAllTimers();

    // 스크롤 컨트롤러는 Provider에서 관리하므로 여기서는 정리하지 않음
    // KdsScrollControllerMap Provider에서 자동으로 관리됨

    super.dispose();
  }

  // Timer 관리 헬퍼 메서드들
  void _setTimer(String key, Duration duration, VoidCallback callback) {
    _cancelTimer(key); // 기존 타이머가 있으면 취소
    _timers[key] = Timer(duration, () {
      _timers.remove(key);
      if (mounted) {
        callback();
      }
    });
  }

  void _cancelTimer(String key) {
    _timers[key]?.cancel();
    _timers.remove(key);
  }

  void _cancelAllTimers() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
  }

  // 주문 관련 모든 상태 정리 (메모리 누수 방지)
  void _cleanupOrderRelatedState(String orderId) {
    try {
      // Timer 정리
      _cancelTimer('scroll_button_update_$orderId');
      _cancelTimer('scroll_button_retry_$orderId');

      // 스크롤 관련 상태 정리
      ref
          .read(kdsScrollButtonStatesProvider.notifier)
          .removeScrollButtonState(orderId);
      ref
          .read(kdsScrollPositionsProvider.notifier)
          .clearScrollPosition(orderId);
      ref
          .read(kdsScrollControllerMapProvider.notifier)
          .disposeController(orderId);

      // 체크된 아이템 상태 정리
      ref.read(kdsCheckedItemsProvider.notifier).clearCheckedItems(orderId);

      // 애니메이션 상태 정리
      ref.read(kdsCardAnimationsProvider.notifier).clearAnimation(orderId);

      logger.d('KDS: 주문 관련 상태 정리 완료 - $orderId');
    } catch (e) {
      logger.d('KDS: 주문 상태 정리 중 오류 - $orderId: $e');
    }
  }

  // KDS 모드에서 로그아웃 시 호출되는 메서드 (사용 안함)
  // dispose에서 자동으로 정리됨

  // 사용하지 않는 메서드 제거 - OrderProvider에서 자동 초기화됨
  // Future<void> _refreshOrdersIfNeeded() async { ... }

  // 외부에서 호출되는 새로고침 메서드 (안전한 버전)
  Future<void> refreshOrdersSafely() async {
    logger.d('KDS: 안전한 새로고침 시작');

    // PageController가 초기화되었는지 확인
    if (!_pageController.hasClients) {
      logger.d('KDS: PageController가 아직 초기화되지 않음, 새로고침 지연');
      // PageController가 초기화될 때까지 잠시 대기
      await Future.delayed(const Duration(milliseconds: 100));
    }

    try {
      // 항상 orderProvider 새로고침 (실시간 데이터)
      await ref.read(orderProvider.notifier).refreshOrders();

      logger.d('KDS: 안전한 새로고침 완료');

      // 새로고침 완료 후 탭 동기화 보장
      _ensureTabSyncAfterRefresh();
    } catch (e) {
      logger.d('KDS: 안전한 새로고침 중 오류 발생: $e');
    }
  }

  // 3. 체크박스 관련 부분에서 Provider 사용
  // 예시: _buildSimpleMenuList, _buildMultiColumnMenuList 등에서
  // final checkedItems = ref.watch(kdsCheckedItemsProvider);
  // checkedItemsNotifier = ref.read(kdsCheckedItemsProvider.notifier);
  // checkedItemsNotifier.toggle(orderId, menuIndex, value);
  // checkedItemsNotifier.isChecked(orderId, menuIndex)

  // 신규 주문 감지 및 스크롤 컨트롤러 초기화
  void _detectNewOrdersAndResetScroll(List<OrderModel> currentOrders) {
    final currentOrderIds = currentOrders.map((o) => o.orderId).toSet();
    final newOrderIds = currentOrderIds.difference(_previousOrderIds);
    final removedOrderIds = _previousOrderIds.difference(currentOrderIds);

    // 신규 주문 처리
    if (newOrderIds.isNotEmpty) {
      for (final orderId in newOrderIds) {
        // 신규 주문의 스크롤 버튼 상태 초기화
        ref
            .read(kdsScrollButtonStatesProvider.notifier)
            .updateScrollButtons(orderId, false, false);

        // 신규 주문 카드가 완전히 렌더링된 후 스크롤 버튼 상태 업데이트
        _setTimer(
            'scroll_button_update_$orderId', const Duration(milliseconds: 3000),
            () {
          final scrollControllerMap = ref.read(kdsScrollControllerMapProvider);
          if (scrollControllerMap.containsKey(orderId)) {
            _updateScrollButtonVisibility(orderId);
          } else {
            // 컨트롤러가 아직 없으면 추가로 3초 더 기다림
            _setTimer('scroll_button_retry_$orderId',
                const Duration(milliseconds: 3000), () {
              final retryScrollControllerMap =
                  ref.read(kdsScrollControllerMapProvider);
              if (retryScrollControllerMap.containsKey(orderId)) {
                _updateScrollButtonVisibility(orderId);
              }
            });
          }
        });
      }
    }

    // 제거된 주문 처리 (상태 정리만)
    if (removedOrderIds.isNotEmpty) {
      for (final orderId in removedOrderIds) {
        logger.d('KDS: 주문 제거 감지 - $orderId, 상태 정리');
        _cleanupOrderRelatedState(orderId);
      }
    }

    // 이전 상태들 업데이트
    _previousOrderIds = currentOrderIds;
  }

  // 정렬 변경 감지 (로깅 목적, 실제 스크롤 초기화는 버튼 클릭 시 즉시 처리)
  void _detectSortChangeAndResetScroll(
      OrderSortDirection currentSortDirection) {
    if (_previousSortDirection != null &&
        _previousSortDirection != currentSortDirection) {
      logger.d(
          'KDS: 정렬 변경 감지됨 - ${currentSortDirection == OrderSortDirection.ASC ? "오래된 주문순" : "최신 주문순"}');
    }

    _previousSortDirection = currentSortDirection;
  }

  // 스크롤 컨트롤러를 최상단으로 초기화하는 헬퍼 메서드
  void _resetScrollToTop(ScrollController? controller) {
    if (mounted && controller != null && controller.hasClients) {
      try {
        controller.animateTo(
          0.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      } catch (e) {
        logger.d('KDS: 스크롤 초기화 오류 무시됨: $e');
      }
    }
  }

  // 모든 스크롤 컨트롤러를 즉시 초기화하는 메서드 (Provider 기반)
  void _resetAllScrollsToTop() {
    final scrollControllerMap = ref.read(kdsScrollControllerMapProvider);

    // 탭별 스크롤 컨트롤러 초기화
    _resetScrollToTop(scrollControllerMap[_mainGridScrollerId]);
    _resetScrollToTop(scrollControllerMap[_progressTabScrollerId]);
    _resetScrollToTop(scrollControllerMap[_pickupTabScrollerId]);
    _resetScrollToTop(scrollControllerMap[_completedTabScrollerId]);
    _resetScrollToTop(scrollControllerMap[_cancelledTabScrollerId]);

    // 개별 주문 카드의 스크롤 컨트롤러들도 초기화
    for (final controller in scrollControllerMap.values) {
      _resetScrollToTop(controller);
    }
  }

  // 특정 탭의 스크롤을 맨 앞으로 이동시키는 메서드 (Provider 기반, Timer 사용)
  void _resetScrollForTab(int tabIndex) {
    // 약간의 지연을 두고 실행하여 위젯이 완전히 렌더링된 후 스크롤 초기화
    _setTimer('reset_scroll_tab_$tabIndex', const Duration(milliseconds: 100),
        () {
      final scrollControllerMap = ref.read(kdsScrollControllerMapProvider);

      switch (tabIndex) {
        case 0: // 전체 탭
          final controller = scrollControllerMap[_mainGridScrollerId];
          if (controller != null && controller.hasClients) {
            _resetScrollToTop(controller);
            logger.d('KDS: 전체 탭 GridView 스크롤을 맨 앞으로 이동');
          }
          break;
        case 1: // 진행 탭
          final controller = scrollControllerMap[_progressTabScrollerId];
          if (controller != null && controller.hasClients) {
            _resetScrollToTop(controller);
            logger.d('KDS: 진행 탭 스크롤을 맨 앞으로 이동');
          }
          break;
        case 2: // 픽업 탭
          final controller = scrollControllerMap[_pickupTabScrollerId];
          if (controller != null && controller.hasClients) {
            _resetScrollToTop(controller);
            logger.d('KDS: 픽업 탭 스크롤을 맨 앞으로 이동');
          }
          break;
        case 3: // 완료 탭
          final controller = scrollControllerMap[_completedTabScrollerId];
          if (controller != null && controller.hasClients) {
            _resetScrollToTop(controller);
            logger.d('KDS: 완료 탭 스크롤을 맨 앞으로 이동');
          }
          break;
        case 4: // 취소 탭
          final controller = scrollControllerMap[_cancelledTabScrollerId];
          if (controller != null && controller.hasClients) {
            _resetScrollToTop(controller);
            logger.d('KDS: 취소 탭 스크롤을 맨 앞으로 이동');
          }
          break;
      }
    });
  }

  // CardType에 따라 해당하는 스크롤 컨트롤러를 반환하는 메서드 (Provider 기반)
  ScrollController? _getScrollControllerForCardType(CardType cardType) {
    final scrollControllerMap = ref.read(kdsScrollControllerMapProvider);
    switch (cardType) {
      case CardType.progress:
        return scrollControllerMap[_progressTabScrollerId];
      case CardType.pickup:
        return scrollControllerMap[_pickupTabScrollerId];
      case CardType.completed:
        return scrollControllerMap[_completedTabScrollerId];
      case CardType.cancelled:
        return scrollControllerMap[_cancelledTabScrollerId];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, child) {
        final sortDirection = ref.watch(kdsSortDirectionProvider);
        final currentTabIndex = ref.watch(kdsTabIndexProvider);
        final selectedDate = ref.watch(selectedDateProvider);
        final todayDateString = DateTime.now().toString().substring(0, 10);
        final isToday = selectedDate == todayDateString;

        logger.d(
            'KDS: build 호출됨 (최적화됨) - 선택된 날짜: $selectedDate, 오늘 여부: $isToday');

        // 설정 화면에서 돌아왔을 때 등, 탭/페이지 불일치가 생기면 강제 동기화
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final savedTabIndex = ref.read(kdsTabIndexProvider);
          final tabIndex = _tabController.index;

          // PageController가 초기화되었는지 확인
          if (_pageController.hasClients) {
            final currentPage = _pageController.page?.round();

            if (currentPage == null ||
                currentPage != savedTabIndex ||
                tabIndex != savedTabIndex) {
              // PageView와 TabBar를 저장된 인덱스로 동기화
              _pageController.jumpToPage(savedTabIndex);
              if (_tabController.index != savedTabIndex) {
                _tabController.animateTo(savedTabIndex);
              }
            }
          } else {
            // PageController가 아직 초기화되지 않은 경우 탭만 동기화
            if (tabIndex != savedTabIndex) {
              _tabController.animateTo(savedTabIndex);
            }
          }
        });

        // 정렬 변경 감지 및 스크롤 위치 초기화
        _detectSortChangeAndResetScroll(sortDirection);

        // 주문 데이터를 직접 watch (Consumer 제거)
        final orderState = ref.watch(orderProvider);

        // KDS 주문 상태 변화 트래커 활성화 (highlight 로직)
        ref.watch(kdsOrderTrackingProvider);

        return Container(
          padding: const EdgeInsets.only(
            bottom: 0,
          ),
          child: Builder(
            builder: (context) {
              // 로딩 중이거나 주문이 비어있으면 이전 상태 유지 (중간 상태 방지)
              if (orderState.isLoading && orderState.orders.isEmpty) {
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('주문 정보를 불러오는 중...'),
                    ],
                  ),
                );
              }

              final orders = orderState.orders;
              final filteredOrders = orders;

              // 상태별 카운트 계산 (안정적 계산)
              final allCount = filteredOrders.length;
              final pendingCount = filteredOrders
                  .where((o) => o.status == OrderStatus.PREPARING)
                  .length;
              final pickupCount = filteredOrders
                  .where((o) => o.status == OrderStatus.READY)
                  .length;
              final completedCount = filteredOrders
                  .where((o) => o.status == OrderStatus.DONE)
                  .length;
              final cancelledCount = filteredOrders
                  .where((o) => o.status == OrderStatus.CANCELLED)
                  .length;

              // 신규 주문 감지는 한 번만 실행 (깜빡임 방지)
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  _detectNewOrdersAndResetScroll(orders);
                }
              });

              // 전체 탭용 주문 목록 (날짜에 따라 다름)
              List<OrderModel> allOrders;
              if (isToday) {
                // 오늘 날짜: 실시간 주문 데이터 사용
                allOrders = List<OrderModel>.from(filteredOrders);
              } else {
                // 다른 날짜: orderHistoryProvider에서 해당 날짜 데이터 가져오기
                final historyAsync = ref.watch(orderHistoryProvider);
                allOrders = historyAsync.when(
                  data: (historyOrders) {
                    logger
                        .d('KDS: 과거 날짜 데이터 로드됨 - ${historyOrders.length}개 주문');
                    return List<OrderModel>.from(historyOrders);
                  },
                  loading: () {
                    logger.d('KDS: 과거 날짜 데이터 로딩 중');
                    return <OrderModel>[];
                  },
                  error: (error, stackTrace) {
                    logger.d('KDS: 과거 날짜 데이터 로드 오류: $error');
                    return <OrderModel>[];
                  },
                );
              }

              // 진행/완료/취소 탭용 주문 목록 (항상 실시간 데이터 사용)
              final pendingOrders = filteredOrders
                  .where((o) => o.status == OrderStatus.PREPARING)
                  .toList();
              final pickupOrders = filteredOrders
                  .where((o) => o.status == OrderStatus.READY)
                  .toList();
              final completedOrders = filteredOrders
                  .where((o) => o.status == OrderStatus.DONE)
                  .toList();
              final cancelledOrders = filteredOrders
                  .where((o) => o.status == OrderStatus.CANCELLED)
                  .toList();

              // 각 탭별 정렬 방향 적용 (watch로 변경하여 상태 변경 감지)
              final tabSortDirections = ref.watch(kdsTabSortDirectionsProvider);
              final allTabSortDirection =
                  tabSortDirections[0] ?? OrderSortDirection.ASC;
              final progressTabSortDirection =
                  tabSortDirections[1] ?? OrderSortDirection.ASC;
              final pickupTabSortDirection =
                  tabSortDirections[2] ?? OrderSortDirection.DESC;
              final completedTabSortDirection =
                  tabSortDirections[3] ?? OrderSortDirection.DESC;
              final cancelledTabSortDirection =
                  tabSortDirections[4] ?? OrderSortDirection.DESC;

              // 각 탭별로 해당하는 정렬 방향 적용
              kds_utils.sortOrders(allOrders, allTabSortDirection);
              kds_utils.sortOrders(pendingOrders, progressTabSortDirection);
              kds_utils.sortOrders(pickupOrders, pickupTabSortDirection);
              kds_utils.sortOrders(completedOrders, completedTabSortDirection);
              kds_utils.sortOrders(cancelledOrders, cancelledTabSortDirection);

              // Pagination 적용 (상세 데이터 로딩 최적화 + Progressive Loading)
              final visibleCount = orderState.visibleOrderCount;
              final visibleAllOrders = allOrders.take(visibleCount).toList();
              final visiblePendingOrders =
                  pendingOrders.take(visibleCount).toList();
              final visiblePickupOrders =
                  pickupOrders.take(visibleCount).toList();
              final visibleCompletedOrders =
                  completedOrders.take(visibleCount).toList();
              final visibleCancelledOrders =
                  cancelledOrders.take(visibleCount).toList();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 탭 바 (이미 계산된 카운트 사용)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: const Border(
                        bottom: BorderSide(
                          color: Colors.transparent, // 구분선 삭제 요청에 따라 투명 처리
                        ),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.only(
                          right: 12, left: 8, top: 4, bottom: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildTabBarWithCounts(
                            allCount,
                            pendingCount,
                            pickupCount,
                            completedCount,
                            cancelledCount,
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (currentTabIndex == 0) ...[
                                if (!isToday) ...[
                                  _buildHistoryCountWidget(),
                                  const SizedBox(width: 8),
                                ],
                                _buildDateSelectorWidget(),
                                const SizedBox(width: 8),
                                _buildTodaySearchButton(),
                                const SizedBox(width: 8),
                              ],
                              _buildBatchCompleteButton(),
                              if (currentTabIndex == 2)
                                const SizedBox(width: 8),
                              _buildSortButton(),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 탭 내용 (이미 계산된 목록 사용 - 추가 Consumer 없음)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(0),
                      child: PageView(
                        key: const PageStorageKey('kds_page_view'),
                        physics: const NeverScrollableScrollPhysics(),
                        controller: _pageController,
                        onPageChanged: (index) {
                          logger.d(
                              'KDS: PageView.onPageChanged 호출 - 페이지: $index');
                          Future.microtask(() {
                            if (mounted) {
                              ref
                                  .read(kdsTabIndexProvider.notifier)
                                  .updateIndex(index);
                            }
                          });
                        },
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: _buildStaticAllTab(visibleAllOrders),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child:
                                _buildStaticProgressTab(visiblePendingOrders),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: _buildStaticPickupTab(visiblePickupOrders),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: _buildStaticCompletedTab(
                                visibleCompletedOrders),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: _buildStaticCancelledTab(
                                visibleCancelledOrders),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  // 탭 바 생성 (카운트만 받아서 깜빡임 최소화)
  Widget _buildTabBarWithCounts(int allCount, int pendingCount, int pickupCount,
      int completedCount, int cancelledCount) {
    return TabBar(
      controller: _tabController,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      indicatorPadding: const EdgeInsets.only(top: 8),
      dividerColor: Colors.transparent,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      labelColor: AppStyles.kMainColor,
      unselectedLabelColor: Colors.grey,
      labelStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      unselectedLabelStyle:
          const TextStyle(fontSize: 18, fontWeight: FontWeight.normal),
      indicator: const BoxDecoration(
        border:
            Border(bottom: BorderSide(color: AppStyles.kMainColor, width: 3)),
        borderRadius: BorderRadius.zero, // 각진 형태
      ),
      indicatorSize: TabBarIndicatorSize.label,
      onTap: (int index) {
        // 중복 선택 감지: 같은 탭을 다시 선택한 경우 스크롤 초기화
        if (_lastSelectedTabIndex == index) {
          _resetScrollForTab(index);
        }
        // 마지막 선택된 탭 인덱스 업데이트
        _lastSelectedTabIndex = index;
      },
      tabs: [
        Tab(
          height: 40.0,
          child: Text(
            t.kds.tabs.all(n: allCount),
            style: const TextStyle(fontSize: AppStyles.kSectionTitleSize),
          ),
        ),
        Tab(
          height: 40.0,
          child: Text(
            t.kds.tabs.progress(n: pendingCount),
            style: const TextStyle(fontSize: AppStyles.kSectionTitleSize),
          ),
        ),
        Tab(
          height: 40.0,
          child: Text(
            t.kds.tabs.pickup(n: pickupCount),
            style: const TextStyle(fontSize: AppStyles.kSectionTitleSize),
          ),
        ),
        Tab(
          height: 40.0,
          child: Text(
            t.kds.tabs.completed(n: completedCount),
            style: const TextStyle(fontSize: AppStyles.kSectionTitleSize),
          ),
        ),
        Tab(
          height: 40.0,
          child: Text(
            t.kds.tabs.cancelled(n: cancelledCount),
            style: const TextStyle(fontSize: AppStyles.kSectionTitleSize),
          ),
        ),
      ],
    );
  }

  Widget _buildSortButton() {
    final currentTabIndex = ref.watch(kdsTabIndexProvider);
    final tabSortDirections = ref.watch(kdsTabSortDirectionsProvider);
    final currentTabSortDirection =
        tabSortDirections[currentTabIndex] ?? OrderSortDirection.ASC;
    return PopupMenuButton<OrderSortDirection>(
      offset: const Offset(0, 40), // 팝업 메뉴 위치 조정
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey[300]!),
      ),
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: 0.1),
      color: Colors.white,
      child: Container(
        width: 130,
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              spreadRadius: 1,
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              currentTabSortDirection == OrderSortDirection.ASC
                  ? t.kds.sort.oldest
                  : t.kds.sort.newest,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            Icon(
              Icons.unfold_more,
              size: 18,
              color: Colors.grey[600],
            ),
          ],
        ),
      ),
      onSelected: (OrderSortDirection value) {
        // 정렬 변경 전에 즉시 모든 스크롤 초기화
        _resetAllScrollsToTop();

        // 현재 탭의 정렬 방향만 변경 (다음 프레임으로 지연)
        Future.microtask(() {
          if (mounted) {
            ref
                .read(kdsTabSortDirectionsProvider.notifier)
                .setSortDirection(currentTabIndex, value);
            ref.read(kdsSortDirectionProvider.notifier).updateDirection(value);
            logger.d(
                'KDS: 탭 $currentTabIndex 정렬 변경 - ${value == OrderSortDirection.ASC ? "오래된 주문순" : "최신 주문순"}');
            logger.d(
                'KDS: 정렬 변경 후 상태 - ${ref.read(kdsTabSortDirectionsProvider)}');
          }
        });
      },
      itemBuilder: (BuildContext context) => [
        PopupMenuItem(
          value: OrderSortDirection.ASC,
          height: 48,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 12),
            child: Text(
              t.kds.sort.oldest,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: currentTabSortDirection == OrderSortDirection.ASC
                    ? AppStyles.kMainColor
                    : Colors.black87,
              ),
            ),
          ),
        ),
        PopupMenuItem(
          value: OrderSortDirection.DESC,
          height: 48,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 12),
            child: Text(
              t.kds.sort.newest,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: currentTabSortDirection == OrderSortDirection.DESC
                    ? AppStyles.kMainColor
                    : Colors.black87,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 픽업 탭의 주문을 한 번에 완료 처리하는 버튼
  Widget _buildBatchCompleteButton() {
    final currentTabIndex = ref.watch(kdsTabIndexProvider);
    if (currentTabIndex != 2) return const SizedBox.shrink();

    return Container(
      height: 40, // 다른 버튼들과 높이 통일
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppStyles.kMainColor,
            AppStyles.kMainColor.withValues(alpha: 0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: AppStyles.kMainColor.withValues(alpha: 0.3),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () async {
            // 현재 픽업 탭의 주문 목록 가져오기 (READY 상태)
            final currentOrdersResult = ref.read(orderHistoryProvider);
            const READY_STATUS = OrderStatus.READY;

            currentOrdersResult.whenData((orders) async {
              final pickupOrders =
                  orders.where((o) => o.status == READY_STATUS).toList();

              if (pickupOrders.isEmpty) {
                CommonDialog.showErrorDialog(
                  context: context,
                  title: t.common.error,
                  content: "완료할 픽업 주문이 없습니다.",
                );
                return;
              }

              final confirmed = await CommonDialog.showConfirmDialog(
                context: context,
                title: t.kds.btn_batch_complete,
                content: "${pickupOrders.length}건의 주문을 모두 완료 처리하시겠습니까?",
                confirmText: t.common.confirm,
                cancelText: t.common.cancel,
              );

              if (confirmed == true) {
                try {
                  final result = await ref
                      .read(orderProvider.notifier)
                      .completeReadyOrders();

                  // KDS 전용: 히스토리 뷰 갱신
                  ref.invalidate(orderHistoryProvider);

                  if (!context.mounted) return;
                  final String resultMessage;
                  if (result.failCount == 0 && result.successCount > 0) {
                    resultMessage = t.order_status
                        .batch_result_success(n: result.successCount);
                  } else if (result.successCount > 0) {
                    resultMessage = t.order_status.batch_result_partial(
                        success: result.successCount, fail: result.failCount);
                  } else {
                    resultMessage = t.order_status
                        .batch_result_fail(error: result.failCount);
                  }

                  CommonDialog.showInfoDialog(
                    context: context,
                    title: t.kds.btn_batch_complete,
                    content: resultMessage,
                  );
                } catch (e) {
                  if (!context.mounted) return;
                  CommonDialog.showErrorDialog(
                    context: context,
                    title: t.common.error,
                    content: t.order_status.batch_result_error,
                  );
                }
              }
            });
          },
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.done_all, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text(
                  t.kds.btn_batch_complete,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 날짜 선택기 위젯 (높이 40px로 통일)
  Widget _buildDateSelectorWidget() {
    final selectedDate = ref.watch(selectedDateProvider);
    return InkWell(
      onTap: _showCalendarDialog,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12.0),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(8.0),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              spreadRadius: 1,
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.calendar_today,
                color: AppStyles.kMainColor, size: 18),
            const SizedBox(width: 8.0),
            Text(
              selectedDate,
              style: const TextStyle(
                fontSize: 14.0,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down, color: Colors.grey[600], size: 20),
          ],
        ),
      ),
    );
  }

  /// 오늘 조회 버튼 (높이 40px로 통일)
  Widget _buildTodaySearchButton() {
    final todayDateString = DateTime.now().toString().substring(0, 10);
    return InkWell(
      onTap: () async {
        logger.d('KDS: 오늘날짜조회 버튼 클릭');
        ref.read(selectedDateProvider.notifier).updateDate(todayDateString);
        _ensureTabSyncAfterRefresh();
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12.0),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(8.0),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              spreadRadius: 1,
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Center(
          child: Text(
            t.order_history.search_today,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ),
      ),
    );
  }

  // 과거 날짜 조회 건수 위젯 (스타일 동일화)
  Widget _buildHistoryCountWidget() {
    final historyAsync = ref.watch(orderHistoryProvider);
    return historyAsync.when(
      data: (orders) => Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppStyles.kMainColor.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
          border:
              Border.all(color: AppStyles.kMainColor.withValues(alpha: 0.2)),
        ),
        child: Center(
          child: Text(
            '조회: ${orders.length}건',
            style: const TextStyle(
              color: AppStyles.kMainColor,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
      ),
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  // 달력 다이얼로그 표시
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

  // 달력에서 날짜 선택 시 처리
  void _onDaySelectedInCalendar(
      DateTime newSelectedDay, DateTime focusedDay) async {
    final dateString = newSelectedDay.toString().substring(0, 10);
    final todayDateString = DateTime.now().toString().substring(0, 10);
    final isToday = dateString == todayDateString;

    logger.d('KDS: 날짜 선택 - $dateString, 오늘 여부: $isToday');

    // 선택된 날짜 업데이트
    ref.read(selectedDateProvider.notifier).updateDate(dateString);

    // 다른 날짜 선택 시에만 orderHistoryProvider 갱신
    if (!isToday) {
      logger.d('KDS: 과거 날짜 선택 - orderHistoryProvider 갱신');
      ref.invalidate(orderHistoryProvider);
    }

    // 새로고침 후 탭 동기화 보장
    _ensureTabSyncAfterRefresh();

    Navigator.of(context).pop();
  }

  // order_history_screen과 동일한 주문 목록 위젯 (성능 최적화를 위해 사용 중단)
  // Widget _buildOrderListWidget() {
  //   // KDS 모드에서는 키오스크 주문 항상 노출
  //   final showKioskOrder = true;

  //   // 모든 날짜에 대해 filteredOrderHistoryProvider 사용 (통일된 로직)
  //   final filteredOrdersAsync = ref.watch(filteredOrderHistoryProvider);
  //   final filter = ref.watch(orderFilterProvider);

  //   logger.d('KDS: 주문 조회 - filter: $filter, showKioskOrder: $showKioskOrder');

  //   return filteredOrdersAsync.when(
  //     data: (orders) {
  //       logger.d('KDS: 주문 데이터 로드됨 - orders.length: ${orders.length}');

  //       // KDS 모드에서는 키오스크 주문 항상 노출
  //       final kioskFilteredOrders =
  //           _filterOrdersByKioskSetting(orders, showKioskOrder);

  //       logger.d(
  //           'KDS: 키오스크 필터링 후 - kioskFilteredOrders.length: ${kioskFilteredOrders.length}');

  //       if (kioskFilteredOrders.isEmpty) {
  //         return Center(
  //           child: Text(
  //             filter == OrderFilter.ALL
  //                 ? '해당 날짜에 주문 내역이 없습니다.'
  //                 : filter == OrderFilter.COMPLETED
  //                     ? '해당 날짜에 완료된 주문이 없습니다.'
  //                     : '해당 날짜에 취소된 주문이 없습니다.',
  //             style: const TextStyle(
  //               fontSize: 16.0,
  //               color: Colors.grey,
  //             ),
  //           ),
  //         );
  //       }
  //       return _buildOrderGrid(kioskFilteredOrders);
  //     },
  //     loading: () => const Center(child: CircularProgressIndicator()),
  //     error: (error, stackTrace) {
  //       logger.e('Build Error State for History',
  //           error: error, stackTrace: stackTrace);
  //       return Center(
  //         child: Text(
  //           '주문 내역 로딩 실패: $error.\n매장 정보가 로드되었는지 확인하세요.',
  //           textAlign: TextAlign.center,
  //           style: const TextStyle(color: Colors.red),
  //         ),
  //       );
  //     },
  //   );
  // }

  // 키오스크 주문인지 확인하는 함수 (사용 중단 - 성능 최적화)
  // bool _isKioskOrder(OrderModel order) {
  //   return order.mbrId == '3740002700000000' ||
  //       (order.payMthd.contains('KIOSK'));
  // }

  // 키오스크 노출 설정에 따라 주문을 필터링하는 함수 (사용 중단 - 성능 최적화)
  // List<OrderModel> _filterOrdersByKioskSetting(
  //     List<OrderModel> orders, bool showKioskOrder) {
  //   if (showKioskOrder) {
  //     // 키오스크 주문도 표시하는 경우 모든 주문 반환
  //     return orders;
  //   } else {
  //     // 키오스크 주문을 숨기는 경우 키오스크가 아닌 주문만 반환
  //     return orders.where((order) => !_isKioskOrder(order)).toList();
  //   }
  // }

  // 새로고침 후 탭 동기화 보장
  void _ensureTabSyncAfterRefresh() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final savedTabIndex = ref.read(kdsTabIndexProvider);

      // PageController가 초기화되었는지 확인
      if (_pageController.hasClients) {
        final currentPage = _pageController.page?.round() ?? 0;
        logger.d(
            'KDS: 탭 동기화 - 현재 탭: ${_tabController.index}, 저장된 탭: $savedTabIndex, 페이지: $currentPage');

        // 페이지 컨트롤러가 저장된 탭과 다르면 강제로 동기화
        if (currentPage != savedTabIndex) {
          logger.d('KDS: 페이지 동기화 필요 - $currentPage → $savedTabIndex');
          _pageController
              .jumpToPage(savedTabIndex); // animateToPage 대신 jumpToPage 사용
        }
      }

      // 탭 컨트롤러도 저장된 탭과 다르면 동기화
      if (_tabController.index != savedTabIndex) {
        logger.d('KDS: 탭 동기화 필요 - ${_tabController.index} → $savedTabIndex');
        _tabController.animateTo(savedTabIndex);
      }

      // 탭 동기화 후 해당 탭의 정렬 방향 적용 (다음 프레임으로 지연)
      Future.microtask(() {
        if (mounted) {
          final tabSortDirection = ref
              .read(kdsTabSortDirectionsProvider.notifier)
              .getSortDirection(savedTabIndex);
          ref
              .read(kdsSortDirectionProvider.notifier)
              .updateDirection(tabSortDirection);
        }
      });
    });
  }

  // Order history screen과 동일한 그리드 형태 (전체 탭용 - 직접 OrderCardWidget 사용)
  Widget _buildOrderGrid(List<OrderModel> orders) {
    // 스크롤 컨트롤러가 dispose되지 않았는지 확인
    if (!mounted) {
      return const SizedBox.shrink();
    }

    logger.d('KDS: 전체 탭 그리드 빌드 - ${orders.length}개 주문 (직접 OrderCardWidget 사용)');

    final mainGridController =
        ref.read(kdsScrollControllerMapProvider)[_mainGridScrollerId];

    return RawScrollbar(
      controller: mainGridController, // Provider에서 가져온 스크롤 컨트롤러 사용
      radius: const Radius.circular(10),
      thumbColor: Colors.grey[400],
      fadeDuration: const Duration(milliseconds: 300),
      child: GridView.builder(
        controller: mainGridController, // Provider에서 가져온 스크롤 컨트롤러 사용
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
              key: ValueKey('grid_card_${order.orderId}'),
              order: order,
              onTap: () => _showOrderDetail(context, order, cardType: null),
            ),
          );
        },
      ),
    );
  }

  // 통합 카드 리스트 생성 함수 (개별 카드 최적화)
  Widget buildOrderCardGrid(List<OrderModel> orders, CardType cardType) {
    if (orders.isEmpty) {
      String emptyText = '';
      switch (cardType) {
        case CardType.progress:
          emptyText = '진행 중인 주문이 없습니다.';
          break;
        case CardType.pickup:
          emptyText = '픽업 대기 중인 주문이 없습니다.';
          break;
        case CardType.completed:
          emptyText = '완료된 주문이 없습니다.';
          break;
        case CardType.cancelled:
          emptyText = '취소된 주문이 없습니다.';
          break;
      }
      return Center(
        child: Text(
          emptyText,
          style: const TextStyle(fontSize: 18, color: Colors.grey),
        ),
      );
    }

    logger
        .d('KDS: ${cardType.name} 탭 그리드 빌드 - ${orders.length}개 주문 (개별 카드 사용)');

    logger.d('KDS: ${cardType.name} 탭 - 개별 카드로 구성');

    final sortedOrders = List<OrderModel>.from(orders);

    switch (cardType) {
      case CardType.progress:
      case CardType.pickup:
      case CardType.completed:
      case CardType.cancelled:
        return KdsCardGridLayoutWidget(
          items: sortedOrders,
          cardType: cardType,
          scrollController: _getScrollControllerForCardType(cardType),
        );
    }
  }

  // 정적 탭 메서드들 (이미 계산된 목록 사용, Consumer 없음 - 깜빡임 완전 제거)
  Widget _buildStaticAllTab(List<OrderModel> allOrders) {
    // 탭 바 영역으로 날짜 버튼들이 이동했으므로, 여기서는 그리드만 표시
    return _buildOrderGrid(allOrders);
  }

  Widget _buildStaticProgressTab(List<OrderModel> pendingOrders) {
    return buildOrderCardGrid(pendingOrders, CardType.progress);
  }

  Widget _buildStaticPickupTab(List<OrderModel> pickupOrders) {
    return buildOrderCardGrid(pickupOrders, CardType.pickup);
  }

  Widget _buildStaticCompletedTab(List<OrderModel> completedOrders) {
    return buildOrderCardGrid(completedOrders, CardType.completed);
  }

  Widget _buildStaticCancelledTab(List<OrderModel> cancelledOrders) {
    return buildOrderCardGrid(cancelledOrders, CardType.cancelled);
  }

  // 스크롤 버튼 가시성 업데이트 함수 (Provider 기반)
  void _updateScrollButtonVisibility(String orderId) {
    if (!mounted) {
      return;
    }

    final scrollControllerMap = ref.read(kdsScrollControllerMapProvider);
    final controller = scrollControllerMap[orderId];
    if (controller == null || !controller.hasClients) {
      return;
    }

    try {
      // position이 준비되었는지 다시 한번 확인 (hasClients가 true여도 시점에 따라 오류 가능)
      if (controller.positions.isEmpty) return;

      final maxScrollExtent = controller.position.maxScrollExtent;
      final currentOffset = controller.offset;

      // 스크롤할 내용이 있는지 확인 (maxScrollExtent > 0)
      final hasScrollableContent = maxScrollExtent > 0;

      // 정확한 스크롤 버튼 가시성 계산
      // 상단 화살표: 스크롤 가능하고 현재 위치가 상단에서 충분히 떨어져 있을 때만 표시
      final canScrollUp = hasScrollableContent && currentOffset > 5.0;

      // 하단 스크롤 버튼: 최하단에 가까우면 숨김 (더 정확한 계산)
      final isNearBottom = currentOffset >= (maxScrollExtent - 3.0);
      final canScrollDown = hasScrollableContent && !isNearBottom;

      // Provider 상태 변경을 다음 프레임으로 지연시켜 빌드 중 상태 변경 방지
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref
              .read(kdsScrollButtonStatesProvider.notifier)
              .updateScrollButtons(orderId, canScrollUp, canScrollDown);
        }
      });
    } catch (e) {
      logger.d('KDS: 스크롤 버튼 가시성 업데이트 오류 무시됨: $e');
    }
  }

  void _showOrderDetail(BuildContext context, OrderModel order,
      {CardType? cardType}) {
    showDialog(
      context: context,
      builder: (context) => OrderDetailPopup(
        order: order,
        isFromKds: true, // KDS 모드로 설정
        isFromAllTab: cardType == null, // 전체 탭 여부 (cardType이 null이면 전체 탭)
        isFromCompletedOrCancelled: cardType == CardType.completed ||
            cardType == CardType.cancelled, // 완료/취소 탭 여부
      ),
    );
  }
}
