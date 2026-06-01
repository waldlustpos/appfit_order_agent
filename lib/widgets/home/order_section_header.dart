import 'package:flutter/material.dart';
import 'package:appfit_order_agent/constants/app_styles.dart';
import 'package:appfit_order_agent/i18n/strings.g.dart';

/// 주문현황 섹션의 좌측 120px 헤더 위젯.
///
/// 섹션 제목, 주문 건수 뱃지, (READY 섹션) 일괄완료 탭 영역을 담당한다.
/// 비즈니스 로직(일괄완료 API 호출)은 [onBadgeTap] 콜백으로 부모에 위임한다.
class OrderSectionHeader extends StatelessWidget {
  const OrderSectionHeader({
    super.key,
    required this.title,
    required this.orderCount,
    required this.showBadgeHighlight,
    this.onBadgeTap,
  });

  final String title;
  final int orderCount;

  /// 뱃지를 kMainColor 보더로 강조할지 (READY + 주문 있음).
  final bool showBadgeHighlight;

  /// null이면 뱃지 탭 비활성화.
  final VoidCallback? onBadgeTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTextStyles.titleSm.copyWith(
                color: AppStyles.gray9,
                fontSize: AppStyles.kSectionTitleSize,
              ),
            ),
            const SizedBox(height: AppSpacing.s8),
            GestureDetector(
              onTap: onBadgeTap,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s12,
                  vertical: AppSpacing.s4,
                ),
                decoration: BoxDecoration(
                  color: showBadgeHighlight
                      ? AppStyles.kMainColor.withValues(alpha: 0.08)
                      : AppStyles.gray2,
                  borderRadius: AppRadius.bMd,
                  border: showBadgeHighlight
                      ? Border.all(color: AppStyles.kMainColor)
                      : null,
                ),
                child: Text(
                  t.order_status.order_count(n: orderCount),
                  style: AppTextStyles.bodySm.copyWith(
                    fontSize: AppStyles.kSectionCountSize,
                    fontWeight: FontWeight.w600,
                    color: showBadgeHighlight
                        ? AppStyles.kMainColor
                        : AppStyles.gray9,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
