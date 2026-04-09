import 'package:flutter/material.dart';
import '../../constants/app_styles.dart';

class TabButtonWidget extends StatelessWidget {
  final String label;
  final IconData icon; // 아이콘 직접 주입으로 변경
  final bool isSelected;
  final VoidCallback onTap;

  const TabButtonWidget({
    Key? key,
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // 내부 아이콘 결정 로직 제거 (국제화 호환성)

    // Check if the keyboard is visible
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;

    // Adjust sizing based on keyboard visibility
    final containerSize = keyboardVisible ? 36.0 : 48.0;
    final iconSize = keyboardVisible ? 20.0 : AppStyles.kTabIconSize;
    final verticalPadding = keyboardVisible ? 4.0 : 12.0;
    final spacerHeight = keyboardVisible ? 2.0 : 6.0;
    final fontSize = keyboardVisible ? 12.0 : AppStyles.kTabTextSize;

    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(vertical: verticalPadding),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min, // 내용에 맞게 크기 조절
          children: [
            Container(
              width: containerSize,
              height: containerSize,
              decoration: BoxDecoration(
                color: isSelected ? AppStyles.kMainColor : Colors.transparent,
                borderRadius: BorderRadius.circular(containerSize / 2.4),
              ),
              child: Icon(
                icon,
                size: iconSize,
                color: isSelected ? Colors.white : Colors.grey[600],
              ),
            ),
            SizedBox(height: spacerHeight),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? AppStyles.kMainColor : Colors.grey[600],
                fontSize: fontSize,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis, // 텍스트가 넘치면 자름
            ),
          ],
        ),
      ),
    );
  }
}
