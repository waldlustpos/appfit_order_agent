import 'package:flutter/material.dart';

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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey[300]!),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      textStyle: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
      foregroundColor: Colors.black87,
      minimumSize: const Size(double.infinity, double.infinity),
      alignment: Alignment.center,
    );

    Widget keyButton(String label,
        {VoidCallback? onPressed, IconData? icon, double fontSize = 30}) {
      return TextButton(
        style: buttonStyle,
        onPressed: onPressed ?? () => onKeyPressed(label),
        child: icon != null
            ? Icon(icon, size: 28)
            : Text(label, style: TextStyle(fontSize: fontSize)),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10.0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final aspectRatio = (constraints.maxWidth / 3) /
              ((constraints.maxHeight - 60) / 4);

          return GridView.count(
            crossAxisCount: 3,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
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
              keyButton(clearLabel, onPressed: onClear, fontSize: 19),
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
