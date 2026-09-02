import 'dart:async';
import 'package:flutter/material.dart';
import 'package:appfit_order_agent/widgets/common/app_loading_indicator.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:appfit_order_agent/widgets/kds/kds_card_grid_layout_widget.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:appfit_order_agent/providers/kds/kds_order_tracking_provider.dart';
import 'package:appfit_order_agent/providers/providers.dart';
import 'package:appfit_order_agent/constants/app_styles.dart';
import 'package:appfit_order_agent/constants/card_types.dart';
import 'package:appfit_order_agent/utils/logger.dart';
import 'package:appfit_order_agent/services/platform_service.dart';
import 'package:appfit_order_agent/utils/model_parse_utils.dart';
import 'package:appfit_order_agent/widgets/order/order_detail_popup.dart';
import 'package:appfit_order_agent/widgets/common/common_dialog.dart';
import 'package:appfit_order_agent/widgets/common/app_toolbar_button.dart';
import 'package:appfit_order_agent/widgets/common/fault_injection_ribbon.dart';
import 'package:appfit_order_agent/models/order_model.dart';
import 'package:appfit_order_agent/widgets/home/order_card_widget.dart';
import 'package:appfit_order_agent/i18n/strings.g.dart';

// 키오스크 주문 노출 설정을 위한 StateProvider (order_history_screen과 동일)
final kioskOrderVisibilityProvider = StateProvider<bool>((ref) {
  final preferenceService = ref.read(preferenceServiceProvider);
  return preferenceService.getShowKioskOrder();
});

class KdsScreen extends ConsumerStatefulWidget {
  const KdsScreen({super.key});

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

  // 일괄완료 버튼 연타 방지 (5초 대기)
  static const _batchCompleteCooldownTimerKey = 'batch_complete_cooldown';
  static const _batchCompleteCooldown = Duration(seconds: 5);
  bool _batchCompleteBusy = false;

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
        } catch (e, s) {
          logger.d('KDS initState: 초기화 중 오류: $e');
        }
      }
    });

    // 탭과 페이지 동기화
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        final currentTabIndex = _tabController.index;

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
    } catch (e, s) {
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
    } catch (e, s) {
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
      } catch (e, s) {
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

  // 탭 인덱스 변경 시 PageController/TabBar 동기화 (build 내 반복 postFrameCallback 대체)
  void _syncTabOnIndexChange(int? prev, int next) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_pageController.hasClients && _pageController.page?.round() != next) {
        _pageController.jumpToPage(next);
      }
      if (_tabController.index != next) {
        _tabController.animateTo(next);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // 탭 인덱스 변경 시에만 동기화 (매 build마다 postFrameCallback 등록하는 안티패턴 제거)
    ref.listen<int>(kdsTabIndexProvider, _syncTabOnIndexChange);

    // 신규 주문 도착 시에만 스크롤 리셋 (매 build마다 등록하는 안티패턴 제거)
    ref.listen(orderProvider.select((s) => s.orders), (prev, next) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _detectNewOrdersAndResetScroll(next);
      });
    });

    return Consumer(
      builder: (context, ref, child) {
        final sortDirection = ref.watch(kdsSortDirectionProvider);
        final currentTabIndex = ref.watch(kdsTabIndexProvider);
        final selectedDate = ref.watch(selectedDateProvider);
        final isToday = selectedDate == todayDateString();

        logger.d(
            'KDS: build 호출됨 (최적화됨) - 선택된 날짜: $selectedDate, 오늘 여부: $isToday');

        // 정렬 변경 감지 및 스크롤 위치 초기화
        _detectSortChangeAndResetScroll(sortDirection);

        // 전체 watch 대신 필요한 단편만 select.
        final showLoadingOverlay = ref.watch(
            orderProvider.select((s) => s.isLoading && s.orders.isEmpty));
        final visibleCount =
            ref.watch(orderProvider.select((s) => s.visibleOrderCount));

        // 탭별 필터/정렬/카운트는 kdsTabOrdersProvider 가 처리 (오늘 데이터 기준).
        final tabOrders = ref.watch(kdsTabOrdersProvider);

        // KDS 주문 상태 변화 트래커 활성화 (highlight 로직)
        ref.watch(kdsOrderTrackingProvider);

        return Container(
          padding: const EdgeInsets.only(
            bottom: 0,
          ),
          child: Builder(
            builder: (context) {
              // PageView/_pageController 를 항상 유지해 탭과 페이지의 동기화를
              // 끊지 않는다.
              // 오버레이는 앱 시작/재로그인 직후 첫 로드에서만 노출.
              // 사용자가 누른 새로고침은 앱바 버튼 자체의 로딩 인디케이터로 충분하므로
              // 중앙 오버레이를 띄우지 않는다. 폴링도 조용히 갱신.

              // 카운트는 항상 오늘 데이터(실시간) 기준 — 기존 동작 유지.
              final allCount = tabOrders.allCount;
              final pendingCount = tabOrders.pendingCount;
              final pickupCount = tabOrders.pickupCount;
              final completedCount = tabOrders.completedCount;
              final cancelledCount = tabOrders.cancelledCount;

              // 전체 탭용 주문 목록: 오늘은 실시간, 과거 날짜는 history provider.
              List<OrderModel> allOrders;
              bool isHistoryLoading = false;
              if (isToday) {
                allOrders = tabOrders.all;
              } else {
                final history = ref.watch(kdsHistoryAllOrdersProvider);
                allOrders = history.orders;
                isHistoryLoading = history.isLoading;
              }

              // 진행/완료/취소 탭용 주문 목록 (항상 실시간 데이터 사용)
              // Pagination: 전체 탭은 GridView.builder 사용으로 제한 없음, 나머지는 take().
              final visibleAllOrders = allOrders;
              final visiblePendingOrders =
                  tabOrders.pending.take(visibleCount).toList();
              final visiblePickupOrders =
                  tabOrders.pickup.take(visibleCount).toList();
              final visibleCompletedOrders =
                  tabOrders.completed.take(visibleCount).toList();
              final visibleCancelledOrders =
                  tabOrders.cancelled.take(visibleCount).toList();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 장애 주입 무장 리본 (개발 전용, 비무장 시 높이 0)
                  const FaultInjectionRibbon(),
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
                    child: Stack(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(0),
                          child: PageView(
                            // PageStorageKey 제거: 화면 재생성(설정 진입 후 복귀) 시
                            // PageStorage 가 PageController.initialPage 를 덮어써
                            // 탭(provider 기준)과 내용(PageStorage 기준)이 어긋나는
                            // 문제를 유발했음. 탭 위치는 kdsTabIndexProvider 단일
                            // 소스로 복원하고, 탭별 가로 스크롤은 _KdsTabKeepAlive 가 보존.
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
                              _KdsTabKeepAlive(
                                child: Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: _buildStaticAllTab(
                                    visibleAllOrders,
                                    isLoading: isHistoryLoading,
                                  ),
                                ),
                              ),
                              _KdsTabKeepAlive(
                                child: Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: _buildStaticProgressTab(
                                      visiblePendingOrders),
                                ),
                              ),
                              _KdsTabKeepAlive(
                                child: Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: _buildStaticPickupTab(
                                      visiblePickupOrders),
                                ),
                              ),
                              _KdsTabKeepAlive(
                                child: Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: _buildStaticCompletedTab(
                                      visibleCompletedOrders),
                                ),
                              ),
                              _KdsTabKeepAlive(
                                child: Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: _buildStaticCancelledTab(
                                      visibleCancelledOrders),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (showLoadingOverlay)
                          const Positioned.fill(
                            child: ColoredBox(
                              color: Colors.white,
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    AppLoadingIndicator(size: 32),
                                    SizedBox(height: 16),
                                    Text('주문 정보를 불러오는 중...'),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
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
      indicator: BoxDecoration(
        border:
            Border(bottom: BorderSide(color: AppStyles.kMainColor, width: 3)),
        borderRadius: BorderRadius.zero, // 각진 형태
      ),
      indicatorSize: TabBarIndicatorSize.label,
      onTap: (int index) {
        const tabNames = ['전체', '진행', '픽업', '완료', '취소'];
        logToFile(
            tag: LogTag.UI_ACTION, message: 'KDS 탭 선택: ${tabNames[index]}');
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
    // 현재 탭의 정렬 방향만 watch — 다른 탭 정렬 변경에는 리빌드되지 않음.
    final currentTabSortDirection = ref.watch(kdsTabSortDirectionsProvider
            .select((map) => map[currentTabIndex])) ??
        OrderSortDirection.ASC;
    return PopupMenuButton<OrderSortDirection>(
      offset: const Offset(0, 40), // 팝업 메뉴 위치 조정
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey[300]!),
      ),
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: 0.1),
      color: Colors.white,
      child: SizedBox(
        width: 130,
        height: 40,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: AppStyles.gray3),
            borderRadius: AppRadius.bSm,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  currentTabSortDirection == OrderSortDirection.ASC
                      ? t.kds.sort.oldest
                      : t.kds.sort.newest,
                  style: AppTextStyles.bodySm.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppStyles.gray9,
                  ),
                ),
                const Icon(Icons.unfold_more, size: 18, color: AppStyles.gray6),
              ],
            ),
          ),
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
            logToFile(
                tag: LogTag.UI_ACTION,
                message: 'KDS 정렬방향 변경: '
                    '${value == OrderSortDirection.ASC ? "오래된순" : "최신순"}');
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

    return AppToolbarButton.primary(
      label: t.kds.btn_batch_complete,
      icon: Icons.done_all,
      isLoading: _batchCompleteBusy,
      onPressed: () async {
        if (_batchCompleteBusy) return;
        setState(() => _batchCompleteBusy = true);
        _setTimer(_batchCompleteCooldownTimerKey, _batchCompleteCooldown, () {
          setState(() => _batchCompleteBusy = false);
        });

        logToFile(tag: LogTag.UI_ACTION, message: 'KDS 일괄완료 버튼 터치');
        // 픽업 탭에 실제 표시되는 목록과 동일한 소스(kdsTabOrdersProvider, 오늘
        // 실시간 데이터)를 사용. orderHistoryProvider는 날짜별 이력 조회용이라
        // 대상이 어긋나 '완료할 픽업 주문이 없습니다'가 잘못 뜨는 문제가 있었음.
        final pickupOrders = ref.read(kdsTabOrdersProvider).pickup;

        if (pickupOrders.isEmpty) {
          CommonDialog.showErrorDialog(
            context: context,
            title: t.common.error,
            content: t.kds.msg_no_pickup_to_complete,
          );
          return;
        }

        final confirmed = await CommonDialog.showConfirmDialog(
          context: context,
          title: t.kds.btn_batch_complete,
          content: t.order_status
              .batch_complete_confirm_content(n: pickupOrders.length),
          confirmText: t.common.confirm,
          cancelText: t.common.cancel,
        );

        if (confirmed == true) {
          logToFile(
              tag: LogTag.UI_ACTION,
              message: 'KDS 일괄완료 확인: 대상 ${pickupOrders.length}건');
          try {
            final result =
                await ref.read(orderProvider.notifier).completeReadyOrders();

            ref.invalidate(orderHistoryProvider);

            logToFile(
                tag: LogTag.UI_ACTION,
                message: 'KDS 일괄완료 결과: 성공 ${result.successCount}건, '
                    '실패 ${result.failCount}건');

            if (!context.mounted) return;
            final String resultMessage;
            if (result.failCount == 0 && result.successCount > 0) {
              resultMessage =
                  t.order_status.batch_result_success(n: result.successCount);
            } else if (result.successCount > 0) {
              resultMessage = t.order_status.batch_result_partial(
                  success: result.successCount, fail: result.failCount);
            } else {
              resultMessage =
                  t.order_status.batch_result_fail(error: result.failCount);
            }

            CommonDialog.showInfoDialog(
              context: context,
              title: t.kds.btn_batch_complete,
              content: resultMessage,
            );
          } catch (e) {
            logToFile(tag: LogTag.UI_ACTION, message: 'KDS 일괄완료 오류: $e');
            if (!context.mounted) return;
            CommonDialog.showErrorDialog(
              context: context,
              title: t.common.error,
              content: t.order_status.batch_result_error,
            );
          }
        }
      },
    );
  }

  /// 날짜 선택기 위젯 (높이 40px로 통일)
  Widget _buildDateSelectorWidget() {
    final selectedDate = ref.watch(selectedDateProvider);
    return AppToolbarButton.secondary(
      label: selectedDate,
      icon: Icons.calendar_today,
      onPressed: _showCalendarDialog,
    );
  }

  Widget _buildTodaySearchButton() {
    return AppToolbarButton.secondary(
      label: t.order_history.search_today,
      onPressed: () {
        logToFile(tag: LogTag.UI_ACTION, message: 'KDS 오늘조회 버튼 터치');
        ref.read(selectedDateProvider.notifier).updateDate(todayDateString());
        _ensureTabSyncAfterRefresh();
      },
    );
  }

  // 과거 날짜 조회 건수 위젯
  Widget _buildHistoryCountWidget() {
    final historyAsync = ref.watch(orderHistoryProvider);
    return historyAsync.maybeWhen(
      data: (orders) => AppToolbarButton.ghost(
        label: '조회: ${orders.length}건',
      ),
      orElse: () => const SizedBox.shrink(),
    );
  }

  // 달력 다이얼로그 표시
  void _showCalendarDialog() {
    logToFile(tag: LogTag.UI_ACTION, message: 'KDS 달력 버튼 터치');
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

  // 달력에서 날짜 선택 시 처리
  void _onDaySelectedInCalendar(
      DateTime newSelectedDay, DateTime focusedDay) async {
    final dateString = newSelectedDay.toString().substring(0, 10);
    final isToday = dateString == todayDateString();

    logToFile(tag: LogTag.UI_ACTION, message: 'KDS 날짜 선택: $dateString');

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

    final grid = GridView.builder(
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
            isKdsMode: true,
            onTap: () => _showOrderDetail(context, order, cardType: null),
          ),
        );
      },
    );

    // ScrollController 가 ScrollView 와 attach 안 된 상태 (예: 첫 frame 또는
    // 다이얼로그가 떠서 GridView 가 일시 detach 된 frame) 에서 RawScrollbar 가
    // _debugCheckHasValidScrollPosition 검증을 trigger 해 throw. attach 된
    // 상태에서만 Scrollbar wrap 한다. attach 안 된 frame 은 thumb 잠깐 안
    // 보일 뿐 다음 frame 부터 정상 표시.
    final hasClients = mainGridController?.hasClients ?? false;
    if (!hasClients) return grid;

    return RawScrollbar(
      controller: mainGridController,
      radius: const Radius.circular(10),
      thumbColor: Colors.grey[400],
      fadeDuration: const Duration(milliseconds: 300),
      child: grid,
    );
  }

  // 통합 카드 리스트 생성 함수 (개별 카드 최적화)
  Widget buildOrderCardGrid(List<OrderModel> orders, CardType cardType) {
    if (orders.isEmpty) {
      String emptyText = '';
      switch (cardType) {
        case CardType.progress:
          emptyText = t.kds.empty_progress;
          break;
        case CardType.pickup:
          emptyText = t.kds.empty_pickup;
          break;
        case CardType.completed:
          emptyText = t.kds.empty_completed;
          break;
        case CardType.cancelled:
          emptyText = t.kds.empty_cancelled;
          break;
      }
      return Center(
        child: Text(
          emptyText,
          style: const TextStyle(fontSize: 18, color: Colors.grey),
        ),
      );
    }

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
  Widget _buildStaticAllTab(
    List<OrderModel> allOrders, {
    bool isLoading = false,
  }) {
    // 과거 날짜 주문 이력 조회 중일 때 진행 인디케이터 표시 (일반 주문내역과 동일 스타일)
    if (isLoading && allOrders.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AppLoadingIndicator(size: 32),
            SizedBox(height: 16),
            Text('주문 정보를 불러오는 중...'),
          ],
        ),
      );
    }
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
    } catch (e, s) {
      logger.d('KDS: 스크롤 버튼 가시성 업데이트 오류 무시됨: $e');
    }
  }

  void _showOrderDetail(BuildContext context, OrderModel order,
      {CardType? cardType}) {
    // KDS 자동접수(KEY_KDS_ACCEPT_ORDERS) ON + 전체 탭 진입은 일반 모드 "주문내역" 탭과
    // 동일한 동작(활성 주문→취소만, CANCELLED→닫기)을 따른다. OrderDetailPopup 의 분기
    // 순서상 isFromHistory 가 상태별 분기보다 먼저 매칭되어 적용된다.
    // (sub-display + 전체 탭 케이스는 그보다 더 앞 분기에서 처리되므로 영향 없음)
    final isAllTab = cardType == null;
    final isKdsAcceptOrders = ref.read(orderProvider).isKdsAcceptOrders;
    final useHistoryFlow = isAllTab && isKdsAcceptOrders;

    showDialog(
      context: context,
      builder: (context) => OrderDetailPopup(
        order: order,
        isFromKds: true, // KDS 모드로 설정
        isFromAllTab: isAllTab, // 전체 탭 여부 (cardType이 null이면 전체 탭)
        isFromCompletedOrCancelled: cardType == CardType.completed ||
            cardType == CardType.cancelled, // 완료/취소 탭 여부
        isFromHistory: useHistoryFlow,
      ),
    );
  }
}

// PageView 자식 State를 유지해 ScrollPosition(탭별 가로 스크롤 offset)을 보존.
class _KdsTabKeepAlive extends StatefulWidget {
  final Widget child;
  const _KdsTabKeepAlive({required this.child});

  @override
  State<_KdsTabKeepAlive> createState() => _KdsTabKeepAliveState();
}

class _KdsTabKeepAliveState extends State<_KdsTabKeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
