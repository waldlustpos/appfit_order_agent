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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[400]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildRow(t.order.amount, totalAmount),
          const SizedBox(height: 12),
          _buildRow(t.order.discount, discountAmount, isDiscount: true),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(thickness: 1),
          ),
          _buildRow(
            t.order.payment,
            paymentAmount,
            isBold: true,
            textSize: 18,
            color: AppStyles.kMainColor,
          ),
        ],
      ),
    );
  }

  Widget _buildRow(
    String label,
    double amount, {
    bool isDiscount = false,
    bool isBold = false,
    double textSize = 14,
    Color color = Colors.black,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            fontSize: textSize,
          ),
        ),
        Text(
          isDiscount
              ? '-${CommonUtil.formatPrice(amount, currencyUnit: currencySymbol)}'
              : CommonUtil.formatPrice(amount, currencyUnit: currencySymbol),
          style: TextStyle(
            color: color,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            fontSize: textSize,
          ),
        ),
      ],
    );
  }
}
