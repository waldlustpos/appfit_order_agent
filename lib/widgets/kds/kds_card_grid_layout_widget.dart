import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../constants/app_styles.dart';
import '../../constants/card_types.dart';
import '../../models/order_model.dart';
import '../../providers/order_provider.dart';
import 'kds_card_metrics.dart';
import 'kds_order_card.dart';

/// KDS 카드의 가로 스크롤 그리드.
///
/// 카드 본체는 [KdsOrderCardColumn] / [KdsOrderCard]로 분리되어 있고,
/// 본 위젯은 가로 ListView, 좌/우 스크롤 화살표, 무한 스크롤 트리거만 담당한다.
class KdsCardGridLayoutWidget extends ConsumerStatefulWidget {
  final List<OrderModel> items;
  final CardType cardType;

  /// 초기 그룹핑 시 사용할 최대 아이템 수 (선택적 최적화 목적, 현재는 무제한).
  final int maxInitialItemsToProcess;
  final ScrollController? scrollController;

  const KdsCardGridLayoutWidget({
    super.key,
    required this.items,
    this.maxInitialItemsToProcess = 100,
    required this.cardType,
    this.scrollController,
  });

  @override
  ConsumerState<KdsCardGridLayoutWidget> createState() =>
      _KdsCardGridLayoutWidgetState();
}

class _KdsCardGridLayoutWidgetState
    extends ConsumerState<KdsCardGridLayoutWidget> {
  late ScrollController _scrollController;
  List<List<OrderModel>> _groupedOrderColumns = [];

  bool _canScrollLeft = false;
  bool _canScrollRight = false;

  @override
  void initState() {
    super.initState();
    _scrollController = widget.scrollController ?? ScrollController();
    _scrollController.addListener(_updateScrollArrowState);
    _prepareGroupedData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateScrollArrowState();
    });
  }

  @override
  void didUpdateWidget(KdsCardGridLayoutWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 실제 배열 내용이 바뀐 경우에만 그룹핑을 다시 수행 (참조 변경 무시).
    if (!listEquals(widget.items, oldWidget.items)) {
      _prepareGroupedData();
      // ScrollController listener는 offset 변경에만 반응하므로,
      // 우측 끝에 멈춰 있는 상태에서 새 주문이 추가되면 자동 갱신되지 않는다.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _updateScrollArrowState();
      });
    }

    if (widget.scrollController != oldWidget.scrollController) {
      _scrollController.removeListener(_updateScrollArrowState);
      _scrollController = widget.scrollController ?? _scrollController;
      _scrollController.addListener(_updateScrollArrowState);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _updateScrollArrowState();
      });
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateScrollArrowState);
    if (widget.scrollController == null) {
      _scrollController.dispose();
    }
    super.dispose();
  }

  void _updateScrollArrowState() {
    if (!_scrollController.hasClients) return;
    final offset = _scrollController.offset;
    final maxExtent = _scrollController.position.maxScrollExtent;
    final newCanScrollLeft = offset > KdsCardMetrics.scrollEdgeThreshold;
    final newCanScrollRight =
        offset < maxExtent - KdsCardMetrics.scrollEdgeThreshold;
    if (newCanScrollLeft != _canScrollLeft ||
        newCanScrollRight != _canScrollRight) {
      setState(() {
        _canScrollLeft = newCanScrollLeft;
        _canScrollRight = newCanScrollRight;
      });
    }
  }

  void _prepareGroupedData() {
    setState(() {
      _groupedOrderColumns = _groupItems(widget.items);
    });
  }

  /// items → column 단위로 그룹핑.
  ///
  /// 현재 정책: 1열 1카드. (변경 시 KdsOrderCardColumn 멀티카드 시나리오도 검토 필요)
  List<List<OrderModel>> _groupItems(List<OrderModel> items) {
    return items.map((item) => [item]).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_groupedOrderColumns.isEmpty && widget.items.isNotEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_groupedOrderColumns.isEmpty && widget.items.isEmpty) {
      return const Center(child: Text('표시할 주문이 없습니다.'));
    }

    return LayoutBuilder(builder: (context, constraints) {
      final screenHeight = MediaQuery.of(context).size.height;
      final availableHeight =
          constraints.maxHeight.isFinite && constraints.maxHeight > 0
              ? constraints.maxHeight - 17
              : screenHeight;

      return Stack(
        children: [
          NotificationListener<ScrollNotification>(
            onNotification: (scrollInfo) {
              if (scrollInfo.metrics.pixels >=
                  scrollInfo.metrics.maxScrollExtent -
                      KdsCardMetrics.loadMoreThreshold) {
                // loadMoreOrders 내부에서 state 가 갱신되는데, 레이아웃 단계에서
                // 직접 호출하면 `Tried to modify a provider while the widget tree
                // was building.` (Sentry APPFIT-ORDER-AGENT-D) 이 발생하므로
                // 다음 마이크로태스크로 미룬다.
                Future.microtask(
                    () => ref.read(orderProvider.notifier).loadMoreOrders());
              }
              return false;
            },
            child: ListView.builder(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              itemCount: _groupedOrderColumns.length,
              itemBuilder: (context, index) {
                final columnGroup = _groupedOrderColumns[index];
                return SizedBox(
                  width: KdsCardMetrics.columnWidth,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
                    child: KdsOrderCardColumn(
                      key: ValueKey(
                          'column_${columnGroup.isNotEmpty ? columnGroup.first.orderId : index}'),
                      group: columnGroup,
                      availableHeight: availableHeight,
                      cardType: widget.cardType,
                    ),
                  ),
                );
              },
            ),
          ),
          if (_canScrollLeft)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: _HorizontalScrollArrow(
                isLeft: true,
                onTap: () => _scrollToEdge(left: true),
              ),
            ),
          if (_canScrollRight)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: _HorizontalScrollArrow(
                isLeft: false,
                onTap: () => _scrollToEdge(left: false),
              ),
            ),
        ],
      );
    });
  }

  void _scrollToEdge({required bool left}) {
    if (!_scrollController.hasClients) return;
    final target = left ? 0.0 : _scrollController.position.maxScrollExtent;
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }
}

class _HorizontalScrollArrow extends StatelessWidget {
  final bool isLeft;
  final VoidCallback onTap;

  const _HorizontalScrollArrow({
    required this.isLeft,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: isLeft ? Alignment.centerLeft : Alignment.centerRight,
          end: isLeft ? Alignment.centerRight : Alignment.centerLeft,
          colors: [
            Colors.white,
            Colors.white.withValues(alpha: 0.0),
          ],
        ),
      ),
      child: Center(
        child: Container(
          width: 44,
          height: 44,
          decoration: const BoxDecoration(
            border: Border.fromBorderSide(BorderSide(color: AppStyles.gray4)),
            shape: BoxShape.circle,
            color: Colors.white,
          ),
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: Center(
                child: Icon(
                  isLeft
                      ? Icons.arrow_back_ios_rounded
                      : Icons.arrow_forward_ios_rounded,
                  size: 22,
                  color: AppStyles.gray9,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
