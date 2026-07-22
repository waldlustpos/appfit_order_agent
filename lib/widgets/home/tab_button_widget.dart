import 'package:flutter/material.dart';
import 'package:appfit_order_agent/constants/app_styles.dart';

class TabButtonWidget extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const TabButtonWidget({
    super.key,
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;

    final containerSize = keyboardVisible ? 36.0 : 48.0;
    final iconSize = keyboardVisible ? 20.0 : AppStyles.kTabIconSize;
    final verticalPadding = keyboardVisible ? 4.0 : 12.0;
    final spacerHeight = keyboardVisible ? 2.0 : 6.0;
    final fontSize = keyboardVisible ? 12.0 : AppStyles.kTabTextSize;

    return InkWell(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: EdgeInsets.symmetric(vertical: verticalPadding),
        decoration: BoxDecoration(
          color: isSelected
              ? AppStyles.kMainColor.withAlpha(18)
              : Colors.transparent,
          // 비선택 행도 같은 폭의 투명 보더를 둬 선택 시 컨텐츠가 밀리지 않게 한다.
          border: Border(
            left: BorderSide(
              color: isSelected ? AppStyles.kMainColor : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
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
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
