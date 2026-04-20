import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../constants/app_styles.dart';
import '../../i18n/strings.g.dart';
import '../../models/membership_model.dart';

/// 쿠폰 사용 내역 1행 카드.
///
/// 현재 provider에서 `USED`/`9` 상태만 필터링하지만, 방어적으로 그 외 상태
/// 표시도 분기해둔다.
class CouponHistoryCard extends StatelessWidget {
  const CouponHistoryCard({
    super.key,
    required this.coupon,
    required this.isLoading,
    required this.onCancelUse,
  });

  final CouponHistoryInfo coupon;
  final bool isLoading;
  final VoidCallback onCancelUse;

  @override
  Widget build(BuildContext context) {
    final statusLabel = _statusLabel(coupon.status);

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
            const _CouponLeading(icon: Icons.local_activity_outlined),
            const SizedBox(width: AppSpacing.s16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    coupon.title,
                    style: AppTextStyles.titleSm,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.s4),
                  Row(
                    children: [
                      Text(
                        DateFormat('yyyy-MM-dd HH:mm').format(coupon.useDate),
                        style: AppTextStyles.bodySm
                            .copyWith(color: AppStyles.gray6),
                      ),
                      if (statusLabel != null) ...[
                        const SizedBox(width: AppSpacing.s8),
                        Text('·',
                            style: AppTextStyles.bodySm
                                .copyWith(color: AppStyles.gray4)),
                        const SizedBox(width: AppSpacing.s8),
                        statusLabel,
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.s8),
            if (_isUsed(coupon.status))
              _CancelUseButton(isLoading: isLoading, onPressed: onCancelUse)
            else
              const SizedBox.shrink(),
          ],
        ),
      ),
    );
  }

  static bool _isUsed(String status) {
    final s = status.toUpperCase();
    return s == 'USED' || s == '9';
  }

  Widget? _statusLabel(String status) {
    switch (status.toUpperCase()) {
      case 'USED':
      case '9':
        return null;
      case 'EXPIRED':
      case '7':
        return Text(
          t.membership.history.status_expired,
          style: AppTextStyles.bodySm.copyWith(color: AppStyles.gray6),
        );
      case 'ISSUED':
        return Text(
          t.membership.history.status_issued,
          style: AppTextStyles.bodySm.copyWith(color: AppStyles.kBlue),
        );
      case 'CANCELLED':
      case 'CANCELED':
        return Text(
          t.membership.history.status_cancelled,
          style: AppTextStyles.bodySm.copyWith(color: AppStyles.kMainColor),
        );
      default:
        return Text(
          status.isNotEmpty ? status : t.common.unknown,
          style: AppTextStyles.bodySm.copyWith(color: AppStyles.gray6),
        );
    }
  }
}

class _CouponLeading extends StatelessWidget {
  const _CouponLeading({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: const BoxDecoration(
        color: AppStyles.kAmberAlpha,
        borderRadius: AppRadius.bSm,
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 22, color: AppStyles.kAmber),
    );
  }
}

class _CancelUseButton extends StatelessWidget {
  const _CancelUseButton({required this.isLoading, required this.onPressed});

  final bool isLoading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: isLoading ? null : onPressed,
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
          : Text(t.membership.history.btn_cancel_use),
    );
  }
}
