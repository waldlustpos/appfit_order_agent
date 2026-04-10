import 'package:flutter/material.dart';
import '../../constants/app_styles.dart';

/// 앱 전반에서 사용하는 통일된 로딩 인디케이터.
///
/// [label]을 지정하면 스피너 아래에 안내 문구를 표시한다.
/// [size]로 스피너 크기를 조절할 수 있다 (기본 24px).
class AppLoadingIndicator extends StatelessWidget {
  const AppLoadingIndicator({
    super.key,
    this.label,
    this.size = 24,
    this.color,
    this.strokeWidth = 2.5,
  });

  final String? label;
  final double size;
  final Color? color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    final indicator = SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: strokeWidth,
        valueColor: AlwaysStoppedAnimation<Color>(
          color ?? AppStyles.kMainColor,
        ),
      ),
    );

    if (label == null) return indicator;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        indicator,
        const SizedBox(height: AppSpacing.s12),
        Text(
          label!,
          style: AppTextStyles.bodySm.copyWith(color: AppStyles.gray6),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// 화면 전체를 덮는 로딩 오버레이.
class AppLoadingOverlay extends StatelessWidget {
  const AppLoadingOverlay({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) => Center(
        child: AppLoadingIndicator(label: label, size: 32),
      );
}
