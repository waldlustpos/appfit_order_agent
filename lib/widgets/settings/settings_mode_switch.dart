import 'package:flutter/material.dart';
import '../../constants/app_styles.dart';
import 'package:appfit_order_agent/i18n/strings.g.dart';

/// 메인 모드 ↔ KDS 모드 전환 세그먼티드 탭.
///
/// 로그인 화면의 _ModeSegmentedTabs 스타일을 참고하여
/// AnimatedContainer 200ms 전환 애니메이션으로 구현된다.
/// 탭 선택 시 [onSwitch] 콜백이 호출된다.
class SettingsModeSwitch extends StatelessWidget {
  const SettingsModeSwitch({
    super.key,
    required this.isKdsMode,
    required this.onSwitch,
  });

  final bool isKdsMode;
  final VoidCallback onSwitch;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);

    return Container(
      decoration: const BoxDecoration(
        color: AppStyles.gray2,
        borderRadius: AppRadius.bSm,
      ),
      padding: const EdgeInsets.all(AppSpacing.s4),
      child: Row(
        children: [
          Expanded(
            child: _ModeTab(
              label: t.login.tabs.order,
              icon: Icons.point_of_sale,
              isSelected: !isKdsMode,
              onTap: isKdsMode ? onSwitch : null,
            ),
          ),
          Expanded(
            child: _ModeTab(
              label: t.login.tabs.kitchen,
              icon: Icons.display_settings,
              isSelected: isKdsMode,
              onTap: isKdsMode ? null : onSwitch,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeTab extends StatelessWidget {
  const _ModeTab({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = isSelected ? AppStyles.kMainColor : AppStyles.gray6;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.s12,
          horizontal: AppSpacing.s8,
        ),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: AppRadius.bSm,
          boxShadow: isSelected ? AppElevation.soft : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: AppSpacing.s8),
            Text(
              label,
              style: AppTextStyles.body.copyWith(
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
