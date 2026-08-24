import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:appfit_order_agent/constants/app_styles.dart';
import 'package:appfit_order_agent/i18n/strings.g.dart';
import 'package:appfit_order_agent/models/membership_model.dart';

/// 스탬프 내역 1행 카드.
///
/// 상태(적립/취소/변환/발급) 별 배지·텍스트·액션 버튼을 분기한다. 같은
/// rewardId의 ISSUED+CANCELED/EXPIRED 짝이 병합된 [StampHistoryEntry]가
/// 들어오면(`entry.resolution != null`) 적립/취소(또는 만료) 시각을 한 카드에
/// 함께 표시하고, 이미 종결된 건이므로 취소 버튼은 렌더링하지 않는다.
class StampHistoryCard extends StatelessWidget {
  const StampHistoryCard({
    super.key,
    required this.entry,
    required this.isLoading,
    required this.onCancel,
  });

  final StampHistoryEntry entry;
  final bool isLoading;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final resolution = entry.resolution;
    if (resolution != null) {
      return _buildResolved(entry.primary, resolution);
    }
    return _buildSingle(entry.primary);
  }

  Widget _buildSingle(StampInfo stamp) {
    final variant = _variantFor(stamp.status);
    final subtitle = _subtitleFor(stamp, variant);

    return _StampCardShell(
      badge: _StampBadge(variant: variant, count: stamp.stampCount),
      title: Text(
        DateFormat('yyyy-MM-dd HH:mm').format(stamp.logDate),
        style: AppTextStyles.titleSm,
      ),
      subtitle: subtitle,
      trailing: stamp.status.toUpperCase() == 'ISSUED' && stamp.isCancelable
          ? _CancelButton(isLoading: isLoading, onPressed: onCancel)
          : null,
    );
  }

  /// ISSUED 행과 그 짝이 되는 CANCELED/EXPIRED 행을 한 카드로 합쳐, 적립
  /// 시각을 제목 줄에, 취소/만료 시각을 부제 줄에 표시한다. 배지는 최종
  /// 상태(취소/만료) 기준으로 그린다.
  Widget _buildResolved(StampInfo issued, StampInfo resolution) {
    final resolvedVariant = _variantFor(resolution.status);
    final isExpired = resolvedVariant == _StampVariant.expired;

    return _StampCardShell(
      badge: _StampBadge(variant: resolvedVariant, count: issued.stampCount),
      title: Text(
        '${t.membership.history.stamp_status_issued} '
        '${DateFormat('yyyy-MM-dd HH:mm').format(issued.logDate)}',
        style: AppTextStyles.titleSm,
      ),
      subtitle: Text(
        '${_resolutionLabel(isExpired)} '
        '${DateFormat('yyyy-MM-dd HH:mm').format(resolution.logDate)}',
        style: AppTextStyles.bodySm.copyWith(
          color: isExpired ? AppStyles.gray6 : AppStyles.kMainColor,
        ),
      ),
      trailing: null,
    );
  }

  String _resolutionLabel(bool isExpired) => isExpired
      ? t.membership.history.stamp_status_expired
      : t.membership.history.stamp_status_canceled;

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

/// 배지 + 제목/부제 + (선택) 우측 액션으로 구성된 스탬프 카드 공용 뼈대.
class _StampCardShell extends StatelessWidget {
  const _StampCardShell({
    required this.badge,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final Widget badge;
  final Widget title;
  final Widget? subtitle;
  final Widget? trailing;

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
            badge,
            const SizedBox(width: AppSpacing.s16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  title,
                  if (subtitle != null) ...[
                    const SizedBox(height: AppSpacing.s4),
                    subtitle!,
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: AppSpacing.s8),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}

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
