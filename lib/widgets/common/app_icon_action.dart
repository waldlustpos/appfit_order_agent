import 'package:flutter/material.dart';
import 'package:appfit_order_agent/constants/app_styles.dart';
import 'package:appfit_order_agent/widgets/common/app_loading_indicator.dart';

/// 앱바/툴바 아이콘 버튼 통일 컴포넌트.
///
/// [isLoading]이 true일 때 아이콘 자리에 작은 [AppLoadingIndicator]를 표시한다.
/// [isStatus]가 true이면 인터랙션 없는 상태 표시 아이콘으로 동작한다.
class AppIconAction extends StatelessWidget {
  const AppIconAction({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.color,
    this.size = 24,
    this.isLoading = false,
    this.isStatus = false,
    this.padding = const EdgeInsets.all(AppSpacing.s8),
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? color;
  final double size;
  final bool isLoading;

  /// true이면 터치 없는 상태 인디케이터로 렌더링
  final bool isStatus;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? AppStyles.gray9;

    final child = isLoading
        ? AppLoadingIndicator(size: size - 4, strokeWidth: 2)
        : Icon(icon, size: size, color: effectiveColor);

    if (isStatus) {
      return Padding(padding: padding, child: child);
    }

    final button = IconButton(
      onPressed: isLoading ? null : onPressed,
      icon: child,
      padding: padding,
      splashRadius: size,
      tooltip: tooltip,
      splashColor: AppStyles.kMainColor.withAlpha(30),
      highlightColor: AppStyles.kMainColor.withAlpha(15),
    );

    return button;
  }
}
