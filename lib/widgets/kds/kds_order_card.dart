import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:appfit_order_agent/constants/app_styles.dart';
import 'package:appfit_order_agent/constants/card_types.dart';
import 'package:appfit_order_agent/models/order_model.dart';
import 'package:appfit_order_agent/providers/kds/kds_unified_providers.dart';
import 'package:appfit_order_agent/providers/order/order_provider.dart';
import 'package:appfit_order_agent/utils/logger.dart';
import 'package:appfit_order_agent/widgets/order/order_detail_popup.dart';
import 'package:appfit_order_agent/widgets/kds/kds_button_widget.dart';
import 'package:appfit_order_agent/widgets/kds/kds_card_metrics.dart';
import 'package:appfit_order_agent/widgets/kds/kds_card_widget.dart';
import 'package:appfit_order_agent/widgets/kds/kds_memo_widget.dart';
import 'package:appfit_order_agent/widgets/kds/kds_menu_list_widget.dart';
import 'package:appfit_order_agent/widgets/kds/kds_scroll_button_widget.dart';
import 'package:appfit_order_agent/widgets/kds/w_kds_card_skeleton.dart';

/// 가로 그리드 한 열에 들어가는 단일 카드 컬럼.
///
/// 현재 그룹핑 전략은 1카드/1열이지만, 향후 다중 카드 묶음을 지원할 수 있도록
/// `group` 파라미터를 그대로 보존한다.
class KdsOrderCardColumn extends ConsumerWidget {
  final List<OrderModel> group;
  final double availableHeight;
  final CardType cardType;

  const KdsOrderCardColumn({
    super.key,
    required this.group,
    required this.availableHeight,
    required this.cardType,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: availableHeight,
      child: Column(
        mainAxisSize: MainAxisSize.max,
        mainAxisAlignment: MainAxisAlignment.start,
        children: group.map((order) {
          return Align(
            alignment: Alignment.topCenter,
            child: KdsOrderCard(
              key: ValueKey('card_${order.orderId}'),
              order: order,
              availableHeight: availableHeight,
              cardType: cardType,
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// KDS 모드 가로 스크롤 카드.
///
/// 두 가지 모드:
/// - **Simple** (`order.kdsOrderType == 1` 또는 상세 미로딩): 메뉴 리스트가
///   카드 높이를 결정. 스크롤 없음.
/// - **Scrollable**: 메뉴 영역이 `availableHeight - headerFooterReserve`로
///   제한되고 위/아래 스크롤 버튼이 등장.
class KdsOrderCard extends ConsumerStatefulWidget {
  final OrderModel order;
  final double availableHeight;
  final CardType cardType;

  const KdsOrderCard({
    super.key,
    required this.order,
    required this.availableHeight,
    required this.cardType,
  });

  @override
  ConsumerState<KdsOrderCard> createState() => _KdsOrderCardState();
}

class _KdsOrderCardState extends ConsumerState<KdsOrderCard> {
  ScrollController? _internalScrollController;
  late String _orderId;

  @override
  void initState() {
    super.initState();
    _orderId = widget.order.orderId;

    _triggerFetchIfNeeded();

    final notifier = ref.read(kdsScrollControllerMapProvider.notifier);
    _internalScrollController = notifier.getExistingController(_orderId);

    // controller 가 이미 존재하든 새로 생성하든 동일 흐름:
    //   frame N (PostFrame 1): controller 확보 → setState(필요 시) → addListener
    //   frame N+1 (PostFrame 2, nested): layout 완료 후 maxScrollExtent 안정 →
    //     _restoreScrollPosition + _updateScrollButtonVisibility
    // 카드별 `Future.delayed` 타이머를 PostFrame chain 으로 대체해 race-safe + timer 등록 0.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      var controller = _internalScrollController ??
          notifier.getExistingController(_orderId) ??
          notifier.getOrCreateController(_orderId);
      if (_internalScrollController != controller) {
        if (!mounted) return;
        setState(() {
          _internalScrollController = controller;
        });
      }
      controller.addListener(_scrollListener);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _restoreScrollPosition();
        _updateScrollButtonVisibility();
      });
    });
  }

  @override
  void didUpdateWidget(KdsOrderCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.order.orderId != oldWidget.order.orderId ||
        !widget.order.isDetailLoaded) {
      _triggerFetchIfNeeded();
    }
  }

  void _triggerFetchIfNeeded() {
    if (widget.order.isDetailLoaded) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      logger.d('KDS: 주문 카드 표시됨(업데이트), 상세 정보 로드 트리거 - ${widget.order.orderId}');
      ref.read(orderProvider.notifier).fetchOrderDetail(widget.order.orderId);
    });
  }

  void _scrollListener() {
    final controller = _internalScrollController;
    if (!mounted || controller == null || !controller.hasClients) return;
    try {
      _updateScrollButtonVisibility();
      if (controller.position.maxScrollExtent > 0) {
        ref
            .read(kdsScrollPositionsProvider.notifier)
            .saveScrollPosition(_orderId, controller.offset);
      }
    } catch (e) {
      logger.d('KDS: 스크롤 리스너 오류 - $_orderId: $e');
    }
  }

  void _updateScrollButtonVisibility() {
    if (!mounted) return;
    final controller = _internalScrollController;
    final notifier = ref.read(kdsScrollButtonStatesProvider.notifier);

    if (controller == null || !controller.hasClients) {
      notifier.updateScrollButtons(_orderId, false, false);
      return;
    }

    try {
      final position = controller.position;
      if (position.maxScrollExtent <= 0) {
        notifier.updateScrollButtons(_orderId, false, false);
        return;
      }
      final canScrollUp = position.pixels > KdsCardMetrics.scrollEdgeThreshold;
      final canScrollDown = position.pixels <
          position.maxScrollExtent - KdsCardMetrics.scrollEdgeThreshold;
      notifier.updateScrollButtons(_orderId, canScrollUp, canScrollDown);
    } catch (e) {
      logger.d('KDS: 스크롤 버튼 상태 업데이트 오류 - $_orderId: $e');
      notifier.updateScrollButtons(_orderId, false, false);
    }
  }

  void _restoreScrollPosition() {
    final controller = _internalScrollController;
    if (!mounted || controller == null || !controller.hasClients) return;
    try {
      final maxScrollExtent = controller.position.maxScrollExtent;
      if (maxScrollExtent <= 0) {
        logger.d('KDS: 스크롤 불가능한 내용 - 위치 복원 스킵 - $_orderId');
        _updateScrollButtonVisibility();
        return;
      }
      final saved = ref
          .read(kdsScrollPositionsProvider.notifier)
          .getScrollPosition(_orderId);
      if (saved > 0.0) {
        controller.jumpTo(saved <= maxScrollExtent ? saved : maxScrollExtent);
      }
      _updateScrollButtonVisibility();
    } catch (e) {
      logger.d('KDS: 스크롤 위치 복원 오류 - $_orderId: $e');
      _updateScrollButtonVisibility();
    }
  }

  @override
  void dispose() {
    _internalScrollController?.removeListener(_scrollListener);
    // ScrollController 인스턴스 자체는 kdsScrollControllerMapProvider가 관리.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    // 상세 정보가 아직 없으면 항상 Simple 카드로 표시 (로딩 스켈레톤만 메뉴 영역에).
    final orderType = !order.isDetailLoaded ? 1 : order.kdsOrderType;
    return orderType == 1
        ? _buildSimpleCard(context, order, widget.cardType,
            height: widget.availableHeight)
        : _buildScrollableCard(
            context, order, widget.cardType, widget.availableHeight);
  }

  Widget _buildSimpleCard(
    BuildContext context,
    OrderModel order,
    CardType cardType, {
    double? height,
  }) {
    final animationState = ref
        .watch(kdsCardAnimationsProvider.select((map) => map[order.orderId]));
    final borderColor = animationState?.borderColor ?? AppStyles.gray3;
    final opacity = animationState?.opacity ?? 1.0;

    return RepaintBoundary(
      child: AnimatedOpacity(
        opacity: opacity,
        duration: KdsCardMetrics.opacityAnimDuration,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
          child: AnimatedContainer(
            duration: KdsCardMetrics.cardSizeAnimDurationShort,
            width: KdsCardMetrics.cardWidth,
            constraints: BoxConstraints(
              minHeight: (height ?? 300) / 2,
              maxHeight: height ?? 300,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: AppRadius.bMd,
              border: Border.all(color: borderColor, width: 1.0),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    KdsCardHeaderWidget(
                      order: order,
                      detailedOrder: order,
                      cardType: cardType,
                    ),
                    const Divider(
                      color: AppStyles.gray3,
                      thickness: 1,
                      height: 1,
                    ),
                    KdsMemoWidget(order: order),
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.s8),
                      child: !order.isDetailLoaded
                          ? const KdsMenuSkeleton()
                          : KdsMenuListWidget(
                              menuList: order.orderMenuList,
                              order: order,
                              cardType: cardType,
                            ),
                    ),
                  ],
                ),
                if (order.isDetailLoaded)
                  _buildBottomButtons(context, order, cardType),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScrollableCard(
    BuildContext context,
    OrderModel order,
    CardType cardType,
    double totalCardHeight,
  ) {
    final scrollButtonState = ref.watch(
        kdsScrollButtonStatesProvider.select((map) => map[order.orderId]));
    final canScrollUp = scrollButtonState?.canScrollUp ?? false;
    final canScrollDown = scrollButtonState?.canScrollDown ?? false;

    final animationState = ref
        .watch(kdsCardAnimationsProvider.select((map) => map[order.orderId]));
    final borderColor = animationState?.borderColor ?? AppStyles.gray3;
    final opacity = animationState?.opacity ?? 1.0;

    return RepaintBoundary(
      child: AnimatedOpacity(
        opacity: opacity,
        duration: KdsCardMetrics.opacityAnimDuration,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
          child: AnimatedContainer(
            duration: KdsCardMetrics.cardSizeAnimDuration,
            curve: Curves.easeInOutCubic,
            width: KdsCardMetrics.cardWidth,
            constraints: BoxConstraints(
              minHeight: totalCardHeight / 2,
              maxHeight: totalCardHeight,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: AppRadius.bMd,
              border: Border.all(color: borderColor, width: 1.0),
            ),
            child: Stack(
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    KdsCardHeaderWidget(
                      order: order,
                      detailedOrder: order,
                      cardType: cardType,
                    ),
                    const Divider(
                      color: AppStyles.gray3,
                      thickness: 1,
                      height: 1,
                    ),
                    KdsMemoWidget(order: order),
                    ConstrainedBox(
                      // headerFooterReserve가 totalCardHeight를 초과하면 음수가 되어
                      // ConstrainedBox 어쌔션에 걸리거나 카드가 사일런트하게 사라진다.
                      // 최소 60px는 메뉴 영역에 보장하되, totalCardHeight 자체가
                      // 60 미만인 transient(예: 윈도우 size 변경 직후)에는 lower를
                      // upper로 cap해 clamp(lower>upper) ArgumentError를 막는다.
                      constraints: BoxConstraints(
                        maxHeight: () {
                          final upper =
                              totalCardHeight > 0 ? totalCardHeight : 0.0;
                          final lower = upper < 60.0 ? upper : 60.0;
                          return (totalCardHeight -
                                  KdsCardMetrics.headerFooterReserve)
                              .clamp(lower, upper);
                        }(),
                      ),
                      child: Stack(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(AppSpacing.s8),
                            child: !order.isDetailLoaded
                                ? const KdsMenuSkeleton()
                                : SingleChildScrollView(
                                    controller: _internalScrollController,
                                    physics: const BouncingScrollPhysics(),
                                    child: KdsMenuListWidget(
                                      menuList: order.orderMenuList,
                                      order: order,
                                      cardType: cardType,
                                    ),
                                  ),
                          ),
                          if (canScrollUp || canScrollDown) ...[
                            if (canScrollUp)
                              Positioned(
                                top: 0,
                                left: 0,
                                right: 0,
                                child: KdsScrollUpButtonWidget(
                                  orderId: order.orderId,
                                  scrollControllers:
                                      ref.read(kdsScrollControllerMapProvider),
                                  updateScrollButtonVisibility: (_) =>
                                      _updateScrollButtonVisibility(),
                                ),
                              ),
                            if (canScrollDown)
                              Positioned(
                                bottom: 0,
                                left: 0,
                                right: 0,
                                child: KdsScrollDownButtonWidget(
                                  orderId: order.orderId,
                                  scrollControllers:
                                      ref.read(kdsScrollControllerMapProvider),
                                  updateScrollButtonVisibility: (_) =>
                                      _updateScrollButtonVisibility(),
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                    if (order.isDetailLoaded)
                      const SizedBox(
                          height: KdsCardMetrics.bottomButtonReserve),
                  ],
                ),
                if (order.isDetailLoaded)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: _buildBottomButtons(context, order, cardType),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Widget _buildBottomButtons(
  BuildContext context,
  OrderModel order,
  CardType cardType,
) {
  switch (cardType) {
    case CardType.progress:
      return KdsProgressBottomButtonsWidget(
        order: order,
        onOrderDetailTap: () =>
            _showOrderDetail(context, order, cardType: cardType),
      );
    case CardType.pickup:
      return KdsPickupBottomButtonsWidget(
        order: order,
        onOrderDetailTap: () =>
            _showOrderDetail(context, order, cardType: cardType),
      );
    case CardType.completed:
      return KdsCompletedBottomButtonsWidget(
        order: order,
        onOrderDetailTap: () =>
            _showOrderDetail(context, order, cardType: cardType),
      );
    case CardType.cancelled:
      return KdsCancelledBottomButtonsWidget(
        order: order,
        onOrderDetailTap: () =>
            _showOrderDetail(context, order, cardType: cardType),
      );
  }
}

void _showOrderDetail(
  BuildContext context,
  OrderModel order, {
  CardType? cardType,
}) {
  showDialog(
    context: context,
    builder: (context) => OrderDetailPopup(
      order: order,
      isFromKds: true,
      isFromAllTab: cardType == null,
      isFromCompletedOrCancelled:
          cardType == CardType.completed || cardType == CardType.cancelled,
    ),
  );
}
