import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:appfit_order_agent/i18n/strings.g.dart';
import 'package:appfit_order_agent/constants/app_styles.dart';
import 'package:appfit_order_agent/constants/brand_theme.dart';
import 'package:appfit_order_agent/providers/brand_theme_provider.dart';
import 'package:appfit_order_agent/services/platform_service.dart';
import 'package:appfit_order_agent/widgets/common/beta_badge.dart';
import 'package:appfit_order_agent/widgets/settings/settings_section_card.dart';
import 'package:appfit_order_agent/widgets/settings/settings_item_widget.dart';

/// 설정 화면의 "테마(브랜드)" 섹션.
///
/// 선택 시 PreferenceService 에 저장되고 앱 재시작 후 색상/로고가 반영된다.
///
/// [themes] 가 주어지면 그 목록만 노출한다(일반 설정의 브랜드별 `기본 + 브랜드테마`
/// 2종). null 이면 [BrandTheme.values] 전체를 노출한다(개발자 옵션용).
class SettingsBrandThemeSection extends ConsumerWidget {
  const SettingsBrandThemeSection({super.key, this.themes});

  /// 노출할 테마 목록. null 이면 전체([BrandTheme.values]).
  final List<BrandTheme>? themes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final selected = ref.watch(brandThemeNotifierProvider);

    return SettingsSectionCard(
      title: t.settings.theme.title,
      icon: Icons.palette_outlined,
      titleBadge: const BetaBadge(),
      children: [
        SettingsItemWidget(
          title: t.settings.theme.title,
          description: t.settings.theme.desc,
          isVertical: true,
          showDivider: false,
          trailing: SizedBox(
            width: double.infinity,
            child: Row(
              children: [
                for (final theme in (themes ?? BrandTheme.values))
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.s8),
                    child: ElevatedButton(
                      onPressed: () => _onSelect(context, ref, theme),
                      style: AppStyles.settingsToggleButton(selected == theme),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _ThemeColorSwatch(theme: theme),
                          const SizedBox(width: AppSpacing.s8),
                          Text(
                            _labelFor(t, theme),
                            style: TextStyle(
                              fontWeight: selected == theme
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _labelFor(Translations t, BrandTheme theme) {
    switch (theme) {
      case BrandTheme.appfitDefault:
        return t.settings.theme.options.appfit_default;
      case BrandTheme.mammothCoffee:
        return t.settings.theme.options.mammoth_coffee;
      case BrandTheme.mata:
        return t.settings.theme.options.mata;
      case BrandTheme.paik:
        return t.settings.theme.options.paik;
      case BrandTheme.tljp:
        return t.settings.theme.options.tljp;
    }
  }

  Future<void> _onSelect(
    BuildContext context,
    WidgetRef ref,
    BrandTheme theme,
  ) async {
    if (ref.read(brandThemeNotifierProvider) == theme) return;

    await ref.read(brandThemeNotifierProvider.notifier).selectTheme(theme);
    logToFile(tag: LogTag.UI_ACTION, message: '브랜드 테마 선택: ${theme.id}');

    if (!context.mounted) return;
    await _showRestartDialog(context);
  }

  Future<void> _showRestartDialog(BuildContext context) async {
    final t = Translations.of(context);
    final shouldQuit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.settings.theme.restart_title),
        content: Text(t.settings.theme.restart_message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.settings.theme.restart_later),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t.settings.theme.restart_now),
          ),
        ],
      ),
    );

    if (shouldQuit == true) {
      logToFile(tag: LogTag.UI_ACTION, message: '브랜드 테마 변경 — 앱 재시작 호출');
      await PlatformService.restartApp();
    }
  }
}

/// 브랜드 테마의 대표 색상(또는 그라데이션)을 표현하는 원형 스와치.
class _ThemeColorSwatch extends StatelessWidget {
  const _ThemeColorSwatch({required this.theme});

  final BrandTheme theme;

  @override
  Widget build(BuildContext context) {
    final gradient = theme.loginGradient;
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: gradient == null ? theme.primary : null,
        gradient: gradient,
        shape: BoxShape.circle,
        border: Border.all(color: AppStyles.gray4, width: 1),
      ),
    );
  }
}
