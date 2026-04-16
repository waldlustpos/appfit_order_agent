import 'package:flutter/material.dart';
import '../../constants/app_styles.dart';

/// 설정 섹션을 묶는 카드 컨테이너.
///
/// 흰색 배경 + AppRadius.bLg 라운딩 + AppElevation.soft 그림자로
/// 디자인 시스템에 맞는 섹션 구분을 제공한다.
class SettingsSectionCard extends StatelessWidget {
  const SettingsSectionCard({
    super.key,
    this.title,
    this.icon,
    required this.children,
  });

  final String? title;
  final IconData? icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.bLg,
        boxShadow: AppElevation.soft,
      ),
      padding: const EdgeInsets.all(AppSpacing.s20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null) ...[
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: AppStyles.gray6),
                  const SizedBox(width: AppSpacing.s8),
                ],
                Text(
                  title!,
                  style: AppTextStyles.titleSm.copyWith(
                    color: AppStyles.gray9,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s12),
          ],
          ...children,
        ],
      ),
    );
  }
}
