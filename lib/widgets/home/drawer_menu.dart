import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:appfit_order_agent/constants/app_styles.dart';
import 'package:appfit_order_agent/providers/kds/kds_unified_providers.dart';
import 'package:appfit_order_agent/providers/store_provider.dart';
import 'package:appfit_order_agent/providers/app_info_provider.dart';
import 'package:appfit_order_agent/services/platform_service.dart';
import 'package:appfit_order_agent/i18n/strings.g.dart';

class DrawerMenu extends ConsumerWidget {
  final int currentIndex;
  final Future<void> Function(int) onItemSelected;

  const DrawerMenu({
    Key? key,
    required this.currentIndex,
    required this.onItemSelected,
  }) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isKdsMode = ref.watch(kdsModeProvider);
    final store = ref.watch(storeProvider);
    final appInfoAsync = ref.watch(appInfoProvider);

    final captionStyle = AppTextStyles.caption.copyWith(color: AppStyles.gray6);
    final versionWidget = appInfoAsync.when(
      data: (appInfo) => Text(
        t.drawer.version(version: appInfo.version, build: appInfo.buildNumber),
        style: captionStyle,
      ),
      loading: () => Text(t.drawer.version_loading, style: captionStyle),
      error: (_, __) => Text(t.drawer.version_error, style: captionStyle),
    );

    return Drawer(
      child: Column(
        children: [
          _DrawerHeader(
            storeName: store.value?.name ?? '',
            onClose: () => Navigator.pop(context),
          ),
          const SizedBox(height: AppSpacing.s8),
          if (isKdsMode) ...[
            _DrawerMenuItem(
              icon: Icons.inventory_2_outlined,
              label: t.drawer.product_management,
              isSelected: false,
              onTap: () async {
                await onItemSelected(2);
                logToFile(tag: LogTag.UI_ACTION, message: '상품관리 선택 (KDS)');
              },
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.s8),
              child: Divider(color: AppStyles.gray2),
            ),
          ],
          _DrawerMenuItem(
            icon: Icons.settings_outlined,
            label: t.drawer.settings,
            isSelected: currentIndex == 1,
            onTap: () async {
              await onItemSelected(1);
              logToFile(tag: LogTag.UI_ACTION, message: '설정 선택');
            },
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.s8),
            child: Divider(color: AppStyles.gray2),
          ),
          _DrawerMenuItem(
            icon: Icons.logout_outlined,
            label: t.drawer.logout,
            isSelected: false,
            onTap: () async {
              await onItemSelected(-1);
              logToFile(tag: LogTag.UI_ACTION, message: '로그아웃 선택');
            },
          ),
          const Spacer(),
          _DrawerFooter(versionWidget: versionWidget),
        ],
      ),
    );
  }
}

class _DrawerHeader extends StatelessWidget {
  final String storeName;
  final VoidCallback onClose;

  const _DrawerHeader({required this.storeName, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s16,
        vertical: AppSpacing.s20,
      ),
      decoration: BoxDecoration(color: AppStyles.kMainColor),
      child: Row(
        children: [
          Image.asset(
            'assets/icons/app_icon_transparent.png',
            width: 36,
            height: 36,
          ),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Text(
              storeName,
              style: AppTextStyles.titleSm.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

class _DrawerMenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _DrawerMenuItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s8,
        vertical: AppSpacing.s4,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: AppRadius.bMd,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.bMd,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s12,
              vertical: AppSpacing.s12,
            ),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppStyles.kMainColor.withValues(alpha: 0.08)
                  : Colors.transparent,
              borderRadius: AppRadius.bMd,
              border: isSelected
                  ? Border.all(color: AppStyles.kMainColor, width: 1)
                  : null,
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: isSelected ? AppStyles.kMainColor : AppStyles.gray6,
                  size: 20,
                ),
                const SizedBox(width: AppSpacing.s12),
                Text(
                  label,
                  style: AppTextStyles.body.copyWith(
                    color: isSelected ? AppStyles.kMainColor : AppStyles.gray9,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DrawerFooter extends StatelessWidget {
  final Widget versionWidget;

  const _DrawerFooter({required this.versionWidget});

  @override
  Widget build(BuildContext context) {
    final style = AppTextStyles.caption.copyWith(color: AppStyles.gray6);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppStyles.gray2, width: 1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.drawer.customer_center,
                  style: style,
                  softWrap: true,
                ),
                const SizedBox(height: AppSpacing.s4),
                Text('070-7781-4531', style: style),
              ],
            ),
          ),
          versionWidget,
        ],
      ),
    );
  }
}
