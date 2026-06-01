import 'package:flutter/material.dart';
import 'package:appfit_order_agent/constants/app_styles.dart';

/// 주문현황 섹션 하나를 감싸는 카드 컨테이너.
///
/// 흰색 배경 + `AppRadius.bLg` 라운딩 + `AppElevation.soft` 그림자로
/// 각 섹션을 독립적으로 부각시킨다.
/// [header]와 [content] 사이에 회색 구분선이 자동으로 삽입된다.
class OrderSectionCard extends StatelessWidget {
  const OrderSectionCard({
    super.key,
    required this.header,
    required this.content,
  });

  final Widget header;
  final Widget content;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s12,
        vertical: AppSpacing.s4,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.bLg,
        boxShadow: AppElevation.soft,
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          header,
          const VerticalDivider(
            width: 1,
            thickness: 1,
            color: AppStyles.gray3,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: AppSpacing.s8),
              child: content,
            ),
          ),
        ],
      ),
    );
  }
}
