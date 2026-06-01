import 'package:flutter/material.dart';
import 'package:appfit_order_agent/constants/app_styles.dart';

/// 오류 상태를 표시하는 위젯.
///
/// [onRetry]를 지정하면 재시도 버튼을 함께 표시한다.
class AppErrorView extends StatelessWidget {
  const AppErrorView({
    super.key,
    required this.message,
    this.onRetry,
    this.retryLabel,
    this.icon = Icons.error_outline,
  });

  final String message;
  final VoidCallback? onRetry;
  final String? retryLabel;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: AppStyles.kRed.withAlpha(180)),
          const SizedBox(height: AppSpacing.s12),
          Text(
            message,
            style: AppTextStyles.body.copyWith(color: AppStyles.gray6),
            textAlign: TextAlign.center,
          ),
          if (onRetry != null) ...[
            const SizedBox(height: AppSpacing.s16),
            ElevatedButton.icon(
              onPressed: onRetry,
              style: AppStyles.primaryButton(),
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(retryLabel ?? '다시 시도'),
            ),
          ],
        ],
      ),
    );
  }
}
