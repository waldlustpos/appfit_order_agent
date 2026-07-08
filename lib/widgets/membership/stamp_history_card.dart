import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:appfit_order_agent/constants/app_styles.dart';
import 'package:appfit_order_agent/i18n/strings.g.dart';
import 'package:appfit_order_agent/models/membership_model.dart';

/// 스탬프 내역 1행 카드.
///
/// 상태(적립/취소/변환/발급) 별 배지·텍스트·액션 버튼을 분기한다.
class StampHistoryCard extends StatelessWidget {
  const StampHistoryCard({
    super.key,
    required this.stamp,
    required this.isLoading,
    required this.onCancel,
  });

  final StampInfo stamp;
  final bool isLoading;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final variant = _variantFor(stamp.status);
    final subtitle = _subtitleFor(stamp, variant);

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
            _StampBadge(variant: variant, count: stamp.stampCount),
            const SizedBox(width: AppSpacing.s16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    DateFormat('yyyy-MM-dd HH:mm').format(stamp.logDate),
                    style: AppTextStyles.titleSm,
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: AppSpacing.s4),
                    subtitle,
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.s8),
            if (variant == _StampVariant.accrued)
              _CancelButton(isLoading: isLoading, onPressed: onCancel)
            else
              const SizedBox.shrink(),
          ],
        ),
      ),
    );
  }

  static _StampVariant _variantFor(String status) {
    switch (status.toUpperCase()) {
      case 'SUCCESS':
      case 'ACCRUED':
      case '0':
        return _StampVariant.accrued;
      case 'CANCELLED':
      case 'CANCELED':
      case '7':
        return _StampVariant.cancelled;
      case 'EXPIRED':
        return _StampVariant.expired;
      case 'USED':
      case 'CONVERTED':
      case '9':
        return _StampVariant.converted;
      case 'ISSUED':
        return _StampVariant.issued;
      default:
        return _StampVariant.other;
    }
  }

  Widget? _subtitleFor(StampInfo stamp, _StampVariant variant) {
    switch (variant) {
      case _StampVariant.accrued:
        return null;
      case _StampVariant.cancelled:
        return Text(
          t.membership.history.stamp_status_canceled,
          style: AppTextStyles.bodySm.copyWith(color: AppStyles.kMainColor),
        );
      case _StampVariant.expired:
        return Text(
          t.membership.history.stamp_status_expired,
          style: AppTextStyles.bodySm.copyWith(color: AppStyles.gray6),
        );
      case _StampVariant.converted:
        return Text(
          t.membership.history.stamp_status_used,
          style: AppTextStyles.bodySm.copyWith(color: AppStyles.gray6),
        );
      case _StampVariant.issued:
        return Text(
          t.membership.history.stamp_status_issued,
          style: AppTextStyles.bodySm.copyWith(color: AppStyles.gray6),
        );
      case _StampVariant.other:
        final text = stamp.memo.isNotEmpty
            ? stamp.memo
            : (stamp.status.isNotEmpty ? stamp.status : '-');
        return Text(
          text,
          style: AppTextStyles.bodySm.copyWith(color: AppStyles.gray6),
        );
    }
  }
}

enum _StampVariant { accrued, cancelled, expired, converted, issued, other }

class _StampBadge extends StatelessWidget {
  const _StampBadge({required this.variant, required this.count});

  final _StampVariant variant;
  final int count;

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = switch (variant) {
      _StampVariant.accrued => (
          '+$count',
          AppStyles.kMainColorAlpha,
          AppStyles.kMainColor,
        ),
      _StampVariant.cancelled => (
          '−$count',
          AppStyles.gray2,
          AppStyles.gray6,
        ),
      _StampVariant.expired => (
          '$count',
          AppStyles.gray2,
          AppStyles.gray6,
        ),
      _StampVariant.converted => (
          '⇄$count',
          AppStyles.kBlueAlpha,
          AppStyles.kBlue,
        ),
      _StampVariant.issued => (
          '+$count',
          AppStyles.kAmberAlpha,
          AppStyles.kAmber,
        ),
      _StampVariant.other => (
          '$count',
          AppStyles.gray2,
          AppStyles.gray6,
        ),
    };

    return Container(
      constraints: const BoxConstraints(minWidth: 56),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s12,
        vertical: AppSpacing.s8,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadius.bSm,
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: AppTextStyles.titleSm
            .copyWith(color: fg, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _CancelButton extends StatelessWidget {
  const _CancelButton({required this.isLoading, required this.onPressed});

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
          : Text(t.membership.history.btn_cancel_save),
    );
  }
}
