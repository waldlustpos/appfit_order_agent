import 'package:flutter/material.dart';
import '../../constants/app_styles.dart';

/// 데이터가 없을 때 표시하는 빈 상태 위젯.
class AppEmptyView extends StatelessWidget {
  const AppEmptyView({
    super.key,
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.subMessage,
  });

  final String message;
  final String? subMessage;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: AppStyles.gray4),
          const SizedBox(height: AppSpacing.s12),
          Text(
            message,
            style: AppTextStyles.body.copyWith(color: AppStyles.gray6),
            textAlign: TextAlign.center,
          ),
          if (subMessage != null) ...[
            const SizedBox(height: AppSpacing.s4),
            Text(
              subMessage!,
              style: AppTextStyles.bodySm.copyWith(color: AppStyles.gray4),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}
