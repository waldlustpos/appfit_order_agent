import 'package:flutter/material.dart';
import 'package:appfit_order_agent/constants/app_styles.dart';

class NumericKeypadWidget extends StatelessWidget {
  final void Function(String value) onKeyPressed;
  final VoidCallback onClear;
  final VoidCallback onDelete;
  final String clearLabel;
  final String deleteLabel;

  /// false 면 모든 키를 비활성(회색·무반응)으로 그린다.
  /// 스탬프 미운영 매장에서 회원 조회 후 입력을 막을 때 쓴다.
  final bool enabled;

  const NumericKeypadWidget({
    super.key,
    required this.onKeyPressed,
    required this.onClear,
    required this.onDelete,
    required this.clearLabel,
    required this.deleteLabel,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final buttonStyle = TextButton.styleFrom(
      shape: const RoundedRectangleBorder(
        borderRadius: AppRadius.bSm,
        side: BorderSide(color: AppStyles.gray3),
      ),
      backgroundColor: Colors.white,
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.s16, vertical: 0),
      textStyle: AppTextStyles.display.copyWith(fontSize: 28),
      foregroundColor: AppStyles.gray9,
      // 비활성 키가 흰 배경 위에서 확실히 회색으로 읽히게 명시한다
      // (기본 disabled 색은 테마 onSurface 38% 라 대비가 약하다).
      disabledForegroundColor: AppStyles.gray3,
      disabledBackgroundColor: AppStyles.gray1,
      minimumSize: const Size(double.infinity, double.infinity),
      alignment: Alignment.center,
    );

    Widget keyButton(String label,
        {VoidCallback? onPressed, IconData? icon, TextStyle? style}) {
      return TextButton(
        style: buttonStyle,
        onPressed: enabled ? (onPressed ?? () => onKeyPressed(label)) : null,
        child: icon != null
            ? Icon(icon, size: 26)
            : Text(
                label,
                style: style,
              ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 3열 x 4행 그리드. 행/열 간격(AppSpacing.s8)을 정확히 빼서 셀 크기를
          // 산출해야 콘텐츠가 뷰포트를 넘지 않는다. 고정 상수(-60)를 쓰면
          // 바코드 스캔 버튼 노출로 키패드 높이가 줄어든 가로 화면에서
          // 음수가 되어 행이 거대해지고 키패드가 버튼 영역을 덮는다.
          const cols = 3;
          const rows = 4;
          final cellWidth =
              (constraints.maxWidth - AppSpacing.s8 * (cols - 1)) / cols;
          final cellHeight =
              (constraints.maxHeight - AppSpacing.s8 * (rows - 1)) / rows;
          final aspectRatio = cellHeight > 0 ? cellWidth / cellHeight : 1.0;

          return GridView.count(
            crossAxisCount: 3,
            mainAxisSpacing: AppSpacing.s8,
            crossAxisSpacing: AppSpacing.s8,
            childAspectRatio: aspectRatio,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              keyButton('1'),
              keyButton('2'),
              keyButton('3'),
              keyButton('4'),
              keyButton('5'),
              keyButton('6'),
              keyButton('7'),
              keyButton('8'),
              keyButton('9'),
              keyButton(clearLabel,
                  onPressed: onClear, style: AppTextStyles.titleSm),
              keyButton('0'),
              keyButton(deleteLabel,
                  onPressed: onDelete, icon: Icons.backspace_outlined),
            ],
          );
        },
      ),
    );
  }
}
