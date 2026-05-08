import 'package:flutter/material.dart';
import 'package:appfit_order_agent/constants/app_styles.dart';
import 'package:appfit_order_agent/models/order_model.dart';
import 'package:appfit_order_agent/i18n/strings.g.dart';

class OrderInfoPanelWidget extends StatefulWidget {
  final OrderModel order;

  const OrderInfoPanelWidget({
    super.key,
    required this.order,
  });

  @override
  State<OrderInfoPanelWidget> createState() => _OrderInfoPanelWidgetState();
}

class _OrderInfoPanelWidgetState extends State<OrderInfoPanelWidget> {
  // 메모 영역 SingleChildScrollView 와 RawScrollbar 를 attach 하는 전용 controller.
  // StatelessWidget 이었을 때는 controller 없이 RawScrollbar 가 PrimaryScrollController
  // 로 fallback -> Windows 에서 자동 attach 안 됨 -> "Scrollbar's ScrollController
  // has no ScrollPosition attached" 에러 발생. 명시적 controller 로 회피.
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  OrderModel get order => widget.order;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final hasCustomer = order.userName != null && order.userName!.isNotEmpty;

    return Expanded(
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: AppRadius.bLg,
          boxShadow: AppElevation.soft,
        ),
        padding: const EdgeInsets.all(AppSpacing.s20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasCustomer) ...[
              Text(
                t.order.customer_honorific(name: order.userName!),
                style: AppTextStyles.titleSm,
              ),
              const SizedBox(height: AppSpacing.s16),
            ],
            Text(
              t.order.memo,
              style: AppTextStyles.bodySm.copyWith(color: AppStyles.gray6),
            ),
            const SizedBox(height: AppSpacing.s8),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: AppStyles.gray1,
                  borderRadius: AppRadius.bSm,
                ),
                padding: const EdgeInsets.all(AppSpacing.s12),
                child: Builder(builder: (context) {
                  final scrollView = SingleChildScrollView(
                    controller: _scrollController,
                    child: Text(
                      _editNote(order.note),
                      style: AppTextStyles.bodySm.copyWith(
                        color: order.note == null || order.note!.isEmpty
                            ? AppStyles.gray6
                            : AppStyles.gray9,
                      ),
                    ),
                  );
                  // attach 안 된 첫 frame 은 RawScrollbar 없이 표시.
                  if (!_scrollController.hasClients) return scrollView;
                  return RawScrollbar(
                    thumbVisibility: true,
                    radius: const Radius.circular(AppRadius.sm),
                    thickness: AppSpacing.s4,
                    controller: _scrollController,
                    child: scrollView,
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _editNote(String? note) {
    if (note == null) return '';
    return note.replaceAll('\\n', ' ');
  }
}
