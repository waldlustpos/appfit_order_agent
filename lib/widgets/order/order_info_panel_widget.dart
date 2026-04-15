import 'package:flutter/material.dart';
import 'package:appfit_order_agent/constants/app_styles.dart';
import 'package:appfit_order_agent/models/order_model.dart';
import 'package:appfit_order_agent/i18n/strings.g.dart';

class OrderInfoPanelWidget extends StatelessWidget {
  final OrderModel order;

  const OrderInfoPanelWidget({
    super.key,
    required this.order,
  });

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
                child: RawScrollbar(
                  thumbVisibility: true,
                  radius: const Radius.circular(AppRadius.sm),
                  thickness: AppSpacing.s4,
                  child: SingleChildScrollView(
                    child: Text(
                      _editNote(order.note),
                      style: AppTextStyles.bodySm.copyWith(
                        color: order.note == null || order.note!.isEmpty
                            ? AppStyles.gray6
                            : AppStyles.gray9,
                      ),
                    ),
                  ),
                ),
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
