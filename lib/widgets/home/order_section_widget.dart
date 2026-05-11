import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../constants/app_styles.dart';
import '../../models/order_model.dart';
import '../../providers/order_provider.dart';
import 'order_card_widget.dart';
import 'order_section_card.dart';
import 'order_section_header.dart';
import '../common/horizontal_scroll_arrow_overlay.dart';
import '../../widgets/common/common_dialog.dart';
import 'package:appfit_order_agent/utils/logger.dart';
import 'package:appfit_order_agent/i18n/strings.g.dart';

class OrderSectionWidget extends ConsumerStatefulWidget {
  final String title;
  final List<OrderModel> orders;
  final OrderStatus status;
  final Function(OrderModel) onOrderTap;

  const OrderSectionWidget({
    Key? key,
    required this.title,
    required this.orders,
    required this.status,
    required this.onOrderTap,
  }) : super(key: key);

  @override
  ConsumerState<OrderSectionWidget> createState() => _OrderSectionWidgetState();
}

class _OrderSectionWidgetState extends ConsumerState<OrderSectionWidget> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _handleBatchComplete() async {
    final confirm = await CommonDialog.showConfirmDialog(
      context: context,
      title: t.order_status.batch_complete_confirm_title,
      content: t.order_status
          .batch_complete_confirm_content(n: widget.orders.length),
      confirmText: t.common.confirm,
      cancelText: t.common.cancel,
    );

    if (confirm != true) return;

    logger.i('일괄 완료 처리 시작: ${widget.orders.length}건');
    final int totalCount = widget.orders.length;
    String resultMessage;
    try {
      final result =
          await ref.read(orderProvider.notifier).completeReadyOrders();
      if (result.errorMessage != null) {
        if (result.successCount > 0) {
          resultMessage = t.order_status.batch_result_partial(
              success: result.successCount, fail: result.failCount);
        } else {
          resultMessage = t.order_status
              .batch_result_fail(error: result.errorMessage ?? '');
        }
      } else {
        resultMessage = t.order_status.batch_result_success(n: totalCount);
      }
    } catch (e, s) {
      logger.e('일괄 완료 처리 UI 오류', error: e, stackTrace: s);
      resultMessage = t.order_status.batch_result_error;
    }

    if (mounted) {
      CommonDialog.showInfoDialog(
        context: context,
        title: t.order_status.batch_result_title,
        content: resultMessage,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool showBadgeHighlight =
        widget.status == OrderStatus.READY && widget.orders.isNotEmpty;

    return OrderSectionCard(
      header: OrderSectionHeader(
        title: widget.title,
        orderCount: widget.orders.length,
        showBadgeHighlight: showBadgeHighlight,
        onBadgeTap: showBadgeHighlight ? _handleBatchComplete : null,
      ),
      content: Stack(
        children: [
          ListView.builder(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s12),
            itemCount: widget.orders.length,
            itemBuilder: (context, index) {
              const double cardSize = 100.0;
              final order = widget.orders[index];
              return SizedBox(
                key: ValueKey(order.orderId),
                height: cardSize,
                child: OrderCardWidget(
                  order: order,
                  onTap: () {
                    ref.read(orderProvider.notifier).stopBlinking();
                    widget.onOrderTap(order);
                  },
                ),
              );
            },
          ),
          if (widget.orders.isNotEmpty)
            HorizontalScrollArrowOverlay(
              controller: _scrollController,
              listVersion: widget.orders.length,
              tooltipStart: t.order_status.scroll_to_start,
              tooltipEnd: t.order_status.scroll_to_end,
            ),
        ],
      ),
    );
  }
}
