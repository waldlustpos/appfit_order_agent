import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:appfit_order_agent/constants/app_styles.dart';
import 'package:appfit_order_agent/models/order_model.dart';
import 'package:appfit_order_agent/i18n/strings.g.dart';

class OrderInfoPanelWidget extends StatelessWidget {
  final OrderModel order;

  const OrderInfoPanelWidget({
    super.key,
    required this.order,
  });

  Color _getStatusColor(OrderStatus status) {
    switch (status) {
      case OrderStatus.NEW:
        return Colors.blue;
      case OrderStatus.PREPARING:
        return Colors.orange;
      case OrderStatus.READY:
        return AppStyles.kMainColor;
      case OrderStatus.DONE:
        return Colors.green;
      case OrderStatus.CANCELLED:
        return Colors.red;
    }
  }

  String _getStatusText(OrderStatus status, Translations t) {
    switch (status) {
      case OrderStatus.NEW:
        return t.order.new_order;
      case OrderStatus.PREPARING:
        return t.order.preparing;
      case OrderStatus.READY:
        return t.order.ready;
      case OrderStatus.DONE:
        return t.order.done;
      case OrderStatus.CANCELLED:
        return t.order.cancelled;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);

    return Expanded(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[400]!),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Text(
                order.displayNum,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: AppStyles.kOrderCardTitleSize,
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (order.userName != null) ...[
              Center(
                child: Text(
                  t.order.customer_honorific(name: order.userName!),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: AppStyles.kSectionTitleSize,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Center(
              child: Text(
                DateFormat('yyyy-MM-dd HH:mm:ss').format(order.orderedAt),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: AppStyles.kAppBarTitleSize,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                decoration: BoxDecoration(
                  color: _getStatusColor(order.status),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  _getStatusText(order.status, t),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              t.order.memo,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.grey[400]!),
                ),
                child: RawScrollbar(
                  thumbVisibility: true,
                  radius: const Radius.circular(10),
                  thickness: 5,
                  child: SingleChildScrollView(
                    child: Text(
                      _editNote(order.note),
                      style: TextStyle(
                        fontSize: 13,
                        color: order.note == null ? Colors.grey : Colors.black,
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
