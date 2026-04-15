import 'package:flutter/material.dart';
import 'package:appfit_order_agent/constants/app_styles.dart';
import 'package:appfit_order_agent/utils/common_util.dart';
import 'package:appfit_order_agent/i18n/strings.g.dart';

class OrderPaymentInfoWidget extends StatelessWidget {
  final double totalAmount;
  final double discountAmount;
  final double paymentAmount;
  final String currencySymbol;

  const OrderPaymentInfoWidget({
    super.key,
    required this.totalAmount,
    required this.discountAmount,
    required this.paymentAmount,
    required this.currencySymbol,
  });

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.bLg,
        boxShadow: AppElevation.soft,
      ),
      padding: const EdgeInsets.all(AppSpacing.s20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildRow(
            t.order.amount,
            totalAmount,
            style: AppTextStyles.body,
          ),
          const SizedBox(height: AppSpacing.s12),
          _buildRow(
            t.order.discount,
            discountAmount,
            isDiscount: true,
            style: AppTextStyles.body.copyWith(color: AppStyles.gray6),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.s12),
            child: Divider(height: 1, color: AppStyles.gray3),
          ),
          _buildRow(
            t.order.payment,
            paymentAmount,
            style: AppTextStyles.titleSm.copyWith(
              color: AppStyles.kMainColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(
    String label,
    double amount, {
    bool isDiscount = false,
    required TextStyle style,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: style),
        Text(
          isDiscount
              ? '-${CommonUtil.formatPrice(amount, currencyUnit: currencySymbol)}'
              : CommonUtil.formatPrice(amount, currencyUnit: currencySymbol),
          style: style,
        ),
      ],
    );
  }
}
