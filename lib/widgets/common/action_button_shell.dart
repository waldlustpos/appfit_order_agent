import 'package:flutter/material.dart';
import 'package:appfit_order_agent/constants/app_styles.dart';

/// 다이얼로그 액션 버튼의 시각 표현(스타일 + 진행 인디케이터)을 캡슐화한
/// 내부 셸 위젯. PrintActionButton, AsyncActionButton 이 공유한다.
///
/// 외부에서 단독 사용을 권장하지 않으며, 진행 상태(`busy`)와 활성화 여부
/// (`onPressed == null`)는 상위 위젯이 관리한다.
class ActionButtonShell extends StatelessWidget {
  final String text;
  final bool busy;
  final bool isMainAction;
  final VoidCallback? onPressed;
  final ButtonStyle? styleOverride;

  const ActionButtonShell({
    super.key,
    required this.text,
    required this.busy,
    required this.onPressed,
    this.isMainAction = false,
    this.styleOverride,
  });

  @override
  Widget build(BuildContext context) {
    final ButtonStyle baseStyle = styleOverride ??
        (isMainAction
            ? AppStyles.primaryButton(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s24,
                  vertical: AppSpacing.s12,
                ),
                minimumSize: const Size(120, 44),
              )
            : AppStyles.outlinedButton(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s20,
                  vertical: AppSpacing.s12,
                ),
                minimumSize: const Size(100, 44),
                borderColor: AppStyles.gray3,
              ));

    final ButtonStyle finalStyle = baseStyle.copyWith(
      textStyle: WidgetStatePropertyAll(
        AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
      ),
    );

    return ElevatedButton(
      style: finalStyle,
      onPressed: onPressed,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Opacity(
            opacity: busy ? 0.0 : 1.0,
            child: Text(text),
          ),
          if (busy)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
              ),
            ),
        ],
      ),
    );
  }
}
