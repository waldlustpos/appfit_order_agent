import 'package:flutter/material.dart';
import '../../constants/app_styles.dart';

class NumericKeypadWidget extends StatelessWidget {
  final void Function(String value) onKeyPressed;
  final VoidCallback onClear;
  final VoidCallback onDelete;
  final String clearLabel;
  final String deleteLabel;

  const NumericKeypadWidget({
    super.key,
    required this.onKeyPressed,
    required this.onClear,
    required this.onDelete,
    required this.clearLabel,
    required this.deleteLabel,
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
      minimumSize: const Size(double.infinity, double.infinity),
      alignment: Alignment.center,
    );

    Widget keyButton(String label,
        {VoidCallback? onPressed, IconData? icon, TextStyle? style}) {
      return TextButton(
        style: buttonStyle,
        onPressed: onPressed ?? () => onKeyPressed(label),
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
          final aspectRatio =
              (constraints.maxWidth / 3) / ((constraints.maxHeight - 60) / 4);

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
