import 'package:flutter/material.dart';
import 'package:appfit_order_agent/constants/app_styles.dart';
import 'package:appfit_order_agent/i18n/strings.g.dart';

/// 프린터 연결 상태를 표시하는 위젯.
///
/// 연결됨/끊김 상태를 색상과 아이콘으로 구분하고,
/// 재연결 버튼을 제공한다.
class SettingsConnectionStatus extends StatelessWidget {
  const SettingsConnectionStatus({
    super.key,
    required this.isConnected,
    required this.onReconnect,
    this.detail,
    this.isBusy = false,
  });

  final bool isConnected;
  final VoidCallback onReconnect;

  /// 연결 상태 옆에 덧붙이는 부가 정보 (예: 식별된 프린터 기종명).
  /// 연결됨 상태에서만 표시한다.
  final String? detail;

  /// 재연결이 진행 중이면 true — 버튼을 잠그고 스피너를 보여준다.
  /// Windows 외부 프린터 재연결은 COM 포트를 순차로 열어보므로 수 초가 걸릴 수
  /// 있어, 진행 표시가 없으면 "눌러도 반응이 없다" 로 보인다.
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final fg = isConnected ? AppStyles.green100 : AppStyles.kRed;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s12,
        vertical: AppSpacing.s8,
      ),
      decoration: BoxDecoration(
        color: isConnected
            ? AppStyles.green100.withValues(alpha: 0.1)
            : AppStyles.kRed.withValues(alpha: 0.08),
        borderRadius: AppRadius.bSm,
        border: Border.all(
          color: isConnected
              ? AppStyles.green100.withValues(alpha: 0.3)
              : AppStyles.kRed.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isConnected ? Icons.check_circle_outline : Icons.error_outline,
            size: 15,
            color: fg,
          ),
          const SizedBox(width: AppSpacing.s8),
          Text(
            isConnected
                ? t.settings.connection.connected
                : t.settings.connection.disconnected,
            style: AppTextStyles.bodySm.copyWith(
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
          if (isConnected && detail != null) ...[
            const SizedBox(width: AppSpacing.s8),
            Text(
              '· $detail',
              style: AppTextStyles.bodySm.copyWith(color: AppStyles.gray6),
            ),
          ],
          const SizedBox(width: AppSpacing.s12),
          SizedBox(
            height: 28,
            child: ElevatedButton(
              onPressed: isBusy ? null : onReconnect,
              style: AppStyles.outlinedButton(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s12,
                ),
                borderColor: AppStyles.gray4,
              ).copyWith(
                foregroundColor: const WidgetStatePropertyAll(AppStyles.gray6),
                textStyle: const WidgetStatePropertyAll(
                  AppTextStyles.bodySm,
                ),
              ),
              child: isBusy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(t.settings.connection.reconnect),
            ),
          ),
        ],
      ),
    );
  }
}
