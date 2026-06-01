import 'package:flutter/material.dart';
import 'package:appfit_order_agent/constants/app_styles.dart';

/// 개별 설정 항목 위젯.
///
/// 제목 + 설명 + trailing 위젯의 조합으로 설정 항목을 표시한다.
/// [isVertical] 이 true면 제목/설명 아래에 trailing을 배치하고,
/// false면 좌측에 제목/설명, 우측에 trailing을 배치한다.
/// [showDivider] 가 true면 하단에 구분선을 표시한다.
class SettingsItemWidget extends StatelessWidget {
  const SettingsItemWidget({
    super.key,
    required this.title,
    required this.description,
    required this.trailing,
    this.additionalContent,
    this.enabled = true,
    this.isVertical = false,
    this.showDivider = true,
  });

  final String title;
  final String description;
  final Widget trailing;
  final Widget? additionalContent;
  final bool enabled;
  final bool isVertical;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: enabled ? 1.0 : 0.4,
      duration: const Duration(milliseconds: 200),
      child: IgnorePointer(
        ignoring: !enabled,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s16),
              child: isVertical
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildLabel(),
                        const SizedBox(height: AppSpacing.s12),
                        trailing,
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: _buildLabel()),
                        const SizedBox(width: AppSpacing.s16),
                        trailing,
                      ],
                    ),
            ),
            if (additionalContent != null) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.s16),
                child: additionalContent,
              ),
            ],
            if (showDivider) const Divider(color: AppStyles.gray2, height: 1),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTextStyles.body.copyWith(
            fontWeight: FontWeight.w600,
            color: AppStyles.gray9,
          ),
        ),
        const SizedBox(height: AppSpacing.s4),
        Text(
          description,
          style: AppTextStyles.bodySm.copyWith(color: AppStyles.gray6),
        ),
      ],
    );
  }
}
