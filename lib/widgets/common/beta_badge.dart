import 'package:flutter/material.dart';
import 'package:appfit_order_agent/constants/app_styles.dart';

/// 'BETA' 라벨 pill. 아직 실험 단계인 설정/기능임을 표시한다.
///
/// 'BETA'는 만국공통 표기라 i18n 대상이 아니다. 색상은 브랜드 강조색을 따른다.
class BetaBadge extends StatelessWidget {
  const BetaBadge({super.key, this.label = 'BETA'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s8,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: AppStyles.kMainColor,
        borderRadius: AppRadius.bSm,
      ),
      child: Text(
        label,
        style: AppTextStyles.caption.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
