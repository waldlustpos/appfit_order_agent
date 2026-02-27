import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../constants/app_styles.dart';
import '../../constants/card_types.dart';
import '../../models/order_model.dart';
import '../../i18n/strings.g.dart';

// 통일된 카드 헤더 위젯
class KdsCardHeaderWidget extends StatelessWidget {
  final OrderModel order;
  final OrderModel detailedOrder;
  final CardType cardType;

  const KdsCardHeaderWidget({
    Key? key,
    required this.order,
    required this.detailedOrder,
    required this.cardType,
  }) : super(key: key);

  // 총 아이템 개수 계산 (메뉴 개수만)
  int _calculateTotalItems(OrderModel order) {
    int totalItems = 0;

    for (final menu in order.orderMenuList) {
      // 메뉴 개수만 추가
      totalItems += menu.qty;
    }

    return totalItems;
  }

  @override
  Widget build(BuildContext context) {
    Color headerColor;
    Color textColor;

    final productType = detailedOrder.detectSpecialProductType();

    switch (cardType) {
      case CardType.progress:
        // 매장/포장/매장+포장에 따른 색상 변경
        if (productType == SpecialProductType.dineIn) {
          headerColor = AppStyles.kSubAlpha;
          textColor = AppStyles.kSub;
        } else if (productType == SpecialProductType.both) {
          headerColor = AppStyles.gray2;
          textColor = AppStyles.gray9;
        } else {
          headerColor = AppStyles.kBlueAlpha;
          textColor = AppStyles.kBlue;
        }

        break;
      case CardType.pickup:
        if (productType == SpecialProductType.dineIn) {
          textColor = AppStyles.kSub;
        } else if (productType == SpecialProductType.both) {
          textColor = AppStyles.gray9;
        } else {
          textColor = AppStyles.kBlue;
        }
        headerColor = AppStyles.gray2;
        break;
      case CardType.completed:
        if (productType == SpecialProductType.dineIn) {
          textColor = AppStyles.kSub;
        } else if (productType == SpecialProductType.both) {
          textColor = AppStyles.gray9;
        } else {
          textColor = AppStyles.kBlue;
        }
        headerColor = AppStyles.gray2;
        break;
      case CardType.cancelled:
        headerColor = AppStyles.kRedAlpha;
        textColor = AppStyles.kRed;
        break;
    }

    return Container(
      decoration: BoxDecoration(
        color: headerColor,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(8),
          topRight: Radius.circular(8),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${detailedOrder.getOrderPrefix()}  ${order.displayNum}',
                  style: TextStyle(
                    fontSize: AppStyles.kOrderNumberSize,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
                Text(
                  t.kds.total_items(n: _calculateTotalItems(detailedOrder)),
                  style: const TextStyle(
                    fontSize: AppStyles.kOrderNumberSize,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
            Text(
              t.kds.order_time(
                  time: DateFormat('HH:mm:ss').format(order.orderedAt)),
              style: const TextStyle(
                fontSize: 12,
                color: AppStyles.gray6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
