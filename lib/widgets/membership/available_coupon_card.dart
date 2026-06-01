import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:appfit_order_agent/constants/app_styles.dart';
import 'package:appfit_order_agent/i18n/strings.g.dart';
import 'package:appfit_order_agent/models/membership_model.dart';

/// 보유 쿠폰 1행 카드. 유효기간 노출 + '사용' 버튼.
class AvailableCouponCard extends StatelessWidget {
  const AvailableCouponCard({
    super.key,
    required this.coupon,
    required this.isLoading,
    required this.onUse,
  });

  final CouponInfo coupon;
  final bool isLoading;
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppStyles.gray1,
      borderRadius: AppRadius.bMd,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s16,
          vertical: AppSpacing.s12,
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: AppStyles.kAmberAlpha,
                borderRadius: AppRadius.bSm,
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.confirmation_number_outlined,
                size: 22,
                color: AppStyles.kAmber,
              ),
            ),
            const SizedBox(width: AppSpacing.s16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    coupon.couponTitle,
                    style: AppTextStyles.titleSm,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.s4),
                  Text(
                    '${t.membership.history.col_expiry}: '
                    '${DateFormat('yyyy-MM-dd').format(coupon.expireDate)}',
                    style:
                        AppTextStyles.bodySm.copyWith(color: AppStyles.gray6),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.s8),
            ElevatedButton(
              onPressed: isLoading ? null : onUse,
              style: AppStyles.outlinedPrimaryButton(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s12,
                  vertical: AppSpacing.s8,
                ),
                minimumSize: const Size(80, 36),
              ).copyWith(
                textStyle: WidgetStatePropertyAll(
                  AppTextStyles.bodySm.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              child: isLoading
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppStyles.kMainColor,
                      ),
                    )
                  : Text(t.membership.history.btn_use),
            ),
          ],
        ),
      ),
    );
  }
}
