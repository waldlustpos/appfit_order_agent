import 'package:flutter/material.dart';
import '../../constants/app_styles.dart';

class TabButtonWidget extends StatelessWidget {
  final String label;
  final IconData icon;
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
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;

    final containerSize = keyboardVisible ? 36.0 : 48.0;
    final iconSize = keyboardVisible ? 20.0 : AppStyles.kTabIconSize;
    final verticalPadding = keyboardVisible ? 4.0 : 12.0;
    final spacerHeight = keyboardVisible ? 2.0 : 6.0;
    final fontSize = keyboardVisible ? 12.0 : AppStyles.kTabTextSize;

    return Stack(
      children: [
        InkWell(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: double.infinity,
            padding: EdgeInsets.symmetric(vertical: verticalPadding),
            color: isSelected
                ? AppStyles.kMainColor.withAlpha(18)
                : Colors.transparent,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: containerSize,
                  height: containerSize,
                  decoration: BoxDecoration(
                    color:
                        isSelected ? AppStyles.kMainColor : Colors.transparent,
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
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
        // 좌측 선택 인디케이터 바
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: isSelected ? 3.0 : 0.0,
            decoration: const BoxDecoration(
              color: AppStyles.kMainColor,
              borderRadius: BorderRadius.only(
                topRight: Radius.circular(2),
                bottomRight: Radius.circular(2),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
