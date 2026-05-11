import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../constants/app_styles.dart';
import '../../providers/providers.dart';
import '../../providers/locale_provider.dart';
import '../../providers/currency_provider.dart';
import '../../providers/rotation_provider.dart';
import '../../services/platform_service.dart';
import '../../services/print_service.dart';
import '../../utils/currency_unit.dart';
import '../../widgets/custom_switch.dart';
import 'package:appfit_order_agent/i18n/strings.g.dart';
import 'settings_section_card.dart';
import 'settings_item_widget.dart';
import 'settings_mode_switch.dart';
import 'settings_connection_status.dart';
import 'external_printer_sub_settings.dart';

/// 설정화면 좌측 패널 — 기기/언어/프린터 설정.
class SettingsLeftPanel extends ConsumerStatefulWidget {
  const SettingsLeftPanel({
    super.key,
    required this.isKdsMode,
    required this.isRotated180,
    required this.isAutoStart,
    required this.isIgnoreOtherDeviceKds,
    required this.isAutoReceipt,
    required this.isPrintOrder,
    required this.isUseBuiltinPrinter,
    required this.isUseExternalPrinter,
    required this.isUseLabelPrinter,
    required this.isTpcpStore,
    required this.labelFilterMode,
    required this.isShowOrderTypeBadge,
    required this.onModeSwitch,
    required this.onRotated180Changed,
    required this.onAutoStartChanged,
    required this.onIgnoreOtherDeviceKdsChanged,
    required this.onAutoReceiptChanged,
    required this.onPrintOrderChanged,
    required this.onUseBuiltinPrinterChanged,
    required this.onUseExternalPrinterChanged,
    required this.onUseLabelPrinterChanged,
    required this.onLabelFilterModeChanged,
    required this.onShowOrderTypeBadgeChanged,
    required this.isSoundGraphEnabled,
    required this.soundGraphMarketId,
    required this.onSoundGraphEnabledChanged,
    required this.onSoundGraphMarketIdChanged,
  });

  final bool isKdsMode;
  final bool isRotated180;
  final bool isAutoStart;
  final bool isIgnoreOtherDeviceKds;
  final bool isAutoReceipt;
  final bool isPrintOrder;
  final bool isUseBuiltinPrinter;
  final bool isUseExternalPrinter;
  final bool isUseLabelPrinter;
  final bool isTpcpStore;
  final int labelFilterMode;
  final bool isShowOrderTypeBadge;

  final VoidCallback onModeSwitch;
  final void Function(bool) onRotated180Changed;
  final void Function(bool) onAutoStartChanged;
  final void Function(bool) onIgnoreOtherDeviceKdsChanged;
  final void Function(bool) onAutoReceiptChanged;
  final void Function(bool) onPrintOrderChanged;
  final void Function(bool) onUseBuiltinPrinterChanged;
  final void Function(bool) onUseExternalPrinterChanged;
  final void Function(bool) onUseLabelPrinterChanged;
  final void Function(int) onLabelFilterModeChanged;
  final void Function(bool) onShowOrderTypeBadgeChanged;
  final bool isSoundGraphEnabled;
  final String soundGraphMarketId;
  final void Function(bool) onSoundGraphEnabledChanged;
  final void Function(String) onSoundGraphMarketIdChanged;

  @override
  ConsumerState<SettingsLeftPanel> createState() => _SettingsLeftPanelState();
}

class _SettingsLeftPanelState extends ConsumerState<SettingsLeftPanel> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // ── 언어 스위처 ──────────────────────────────────────────────────────────

  Widget _buildLanguageSwitcher() {
    final currentLocale = ref.watch(localeNotifierProvider);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: AppLocale.values.map((locale) {
        final isSelected = currentLocale == locale;
        return Padding(
          padding: const EdgeInsets.only(right: AppSpacing.s8),
          child: ElevatedButton(
            onPressed: () {
              ref.read(localeNotifierProvider.notifier).changeLocale(locale);
              logToFile(
                  tag: LogTag.UI_ACTION,
                  message: '언어 변경 -> ${locale.languageCode}');
            },
            style: AppStyles.settingsToggleButton(isSelected),
            child: Text(
              _localeLabel(locale),
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  String _localeLabel(AppLocale locale) => switch (locale) {
        AppLocale.ko => '한국어',
        AppLocale.en => 'English',
        AppLocale.ja => '日本語',
      };

  // ── 화폐 스위처 ──────────────────────────────────────────────────────────

  Widget _buildCurrencySwitcher() {
    final currentCurrency = ref.watch(currencyNotifierProvider);
    final t = Translations.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: CurrencyUnit.values.map((unit) {
        final isSelected = currentCurrency == unit;
        return Padding(
          padding: const EdgeInsets.only(right: AppSpacing.s8),
          child: ElevatedButton(
            onPressed: () {
              ref.read(currencyNotifierProvider.notifier).changeCurrency(unit);
              logToFile(
                  tag: LogTag.UI_ACTION, message: '화폐단위 변경 -> ${unit.name}');
            },
            style: AppStyles.settingsToggleButton(isSelected),
            child: Text(
              unit == CurrencyUnit.krw
                  ? t.settings.currency.krw
                  : t.settings.currency.jpy,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── 라벨 필터 버튼 ────────────────────────────────────────────────────────

  Widget _buildFilterModeButton(String label, int mode) {
    final isSelected = widget.labelFilterMode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          widget.onLabelFilterModeChanged(mode);
          logToFile(tag: LogTag.UI_ACTION, message: '라벨 출력 필터 모드 변경 -> $mode');
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.s12),
          decoration: BoxDecoration(
            color: isSelected ? AppStyles.kMainColor : AppStyles.gray2,
            borderRadius: AppRadius.bSm,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: AppTextStyles.bodySm.copyWith(
              color: isSelected ? Colors.white : AppStyles.gray9,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  // ── 화면 회전 처리 ────────────────────────────────────────────────────────

  Future<void> _handleRotationChange(bool value) async {
    final hasPermission = await PlatformService.checkWriteSettingsPermission();
    if (!hasPermission) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('권한 필요'),
          content: const Text('시스템 설정을 변경하려면 "시스템 설정 수정" 권한이 필요합니다.\n'
              '설정 화면으로 이동하시겠습니까?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                PlatformService.requestWriteSettingsPermission();
              },
              child: const Text('설정으로 이동'),
            ),
          ],
        ),
      );
      return;
    }
    widget.onRotated180Changed(value);
    await ref.read(rotationNotifierProvider.notifier).setRotated180(value);
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);

    return Scrollbar(
      controller: _scrollController,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.only(
            left: AppSpacing.s16, right: AppSpacing.s16, top: AppSpacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── 모드 전환 카드 ─────────────────────────────────────────────
            SettingsSectionCard(
              children: [
                SettingsModeSwitch(
                  isKdsMode: widget.isKdsMode,
                  onSwitch: widget.onModeSwitch,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s16),

            // ── 일반 설정 카드 ─────────────────────────────────────────────
            SettingsSectionCard(
              title: t.settings.section_general,
              icon: Icons.tune,
              children: [
                SettingsItemWidget(
                  title: t.settings.language.title,
                  description: t.settings.language.desc,
                  isVertical: true,
                  trailing: _buildLanguageSwitcher(),
                ),
                SettingsItemWidget(
                  title: t.settings.currency.title,
                  description: t.settings.currency.desc,
                  isVertical: true,
                  trailing: _buildCurrencySwitcher(),
                ),
                SettingsItemWidget(
                  title: t.settings.display_rotate.title,
                  description: t.settings.display_rotate.desc,
                  trailing: CustomSwitch(
                    value: widget.isRotated180,
                    activeColor: AppStyles.kMainColor,
                    inactiveColor: AppStyles.gray4,
                    onChanged: _handleRotationChange,
                  ),
                ),
                SettingsItemWidget(
                  title: t.settings.order_type_badge.title,
                  description: t.settings.order_type_badge.desc,
                  trailing: CustomSwitch(
                    value: widget.isShowOrderTypeBadge,
                    activeColor: AppStyles.kMainColor,
                    inactiveColor: AppStyles.gray4,
                    activeText: t.settings.auto_start.on,
                    inactiveText: t.settings.auto_start.off,
                    onChanged: (v) {
                      logToFile(
                          tag: LogTag.UI_ACTION, message: '매장/포장 표시 변경 -> $v');
                      widget.onShowOrderTypeBadgeChanged(v);
                    },
                  ),
                ),
                SettingsItemWidget(
                  title: t.settings.auto_start.title,
                  description: widget.isKdsMode
                      ? t.settings.auto_start.desc
                      : t.settings.auto_start.desc_general,
                  trailing: CustomSwitch(
                    value: widget.isAutoStart,
                    activeColor: AppStyles.kMainColor,
                    inactiveColor: AppStyles.gray4,
                    activeText: t.settings.auto_start.on,
                    inactiveText: t.settings.auto_start.off,
                    onChanged: (v) {
                      logToFile(
                          tag: LogTag.UI_ACTION,
                          message: 'PC시작 시 자동 실행 변경 -> $v');
                      widget.onAutoStartChanged(v);
                    },
                  ),
                ),
                if (widget.isKdsMode)
                  SettingsItemWidget(
                    title: t.settings.kds_ignore_status.title,
                    description: t.settings.kds_ignore_status.desc,
                    showDivider: false,
                    trailing: CustomSwitch(
                      value: widget.isIgnoreOtherDeviceKds,
                      activeColor: AppStyles.kMainColor,
                      inactiveColor: AppStyles.gray4,
                      activeText: t.settings.auto_start.on,
                      inactiveText: t.settings.auto_start.off,
                      onChanged: (v) {
                        logToFile(
                            tag: LogTag.UI_ACTION,
                            message: 'KDS 타 기기 진행상태 무시 변경 -> $v');
                        widget.onIgnoreOtherDeviceKdsChanged(v);
                      },
                    ),
                  ),
                if (!widget.isKdsMode)
                  SettingsItemWidget(
                    title: t.settings.auto_receipt.title,
                    description: t.settings.auto_receipt.desc,
                    showDivider: false,
                    trailing: CustomSwitch(
                      value: widget.isAutoReceipt,
                      activeColor: AppStyles.kMainColor,
                      inactiveColor: AppStyles.gray4,
                      activeText: t.settings.auto_start.on,
                      inactiveText: t.settings.auto_start.off,
                      onChanged: (v) {
                        logToFile(
                            tag: LogTag.UI_ACTION,
                            message: '픽업 오더 자동 접수 변경 -> $v');
                        widget.onAutoReceiptChanged(v);
                        ref.read(orderProvider.notifier).updateAutoReceipt(v);
                      },
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.s16),

            // ── 프린터 설정 카드 ───────────────────────────────────────────
            SettingsSectionCard(
              title: t.settings.section_printer,
              icon: Icons.print_outlined,
              children: [
                SettingsItemWidget(
                  title: t.settings.print_order.title,
                  description: t.settings.print_order.desc,
                  trailing: CustomSwitch(
                    value: widget.isPrintOrder,
                    activeColor: AppStyles.kMainColor,
                    inactiveColor: AppStyles.gray4,
                    activeText: t.settings.auto_start.on,
                    inactiveText: t.settings.auto_start.off,
                    onChanged: (v) {
                      final printService = ref.read(printServiceProvider);
                      if (!v) {
                        printService.updatePrinterSettings(
                          builtinPrinter: false,
                          externalPrinter: false,
                        );
                      } else {
                        if (!widget.isUseBuiltinPrinter &&
                            !widget.isUseExternalPrinter) {
                          printService.updatePrinterSettings(
                            builtinPrinter: true,
                            externalPrinter: false,
                          );
                        }
                      }
                      logToFile(
                          tag: LogTag.UI_ACTION, message: '주문서 출력 변경 -> $v');
                      widget.onPrintOrderChanged(v);
                    },
                  ),
                ),
                SettingsItemWidget(
                  title: t.settings.builtin_printer.title,
                  description: t.settings.builtin_printer.desc,
                  enabled: widget.isPrintOrder,
                  trailing: CustomSwitch(
                    value: widget.isUseBuiltinPrinter,
                    activeColor: AppStyles.kMainColor,
                    inactiveColor: AppStyles.gray4,
                    activeText: t.settings.auto_start.on,
                    inactiveText: t.settings.auto_start.off,
                    onChanged: (v) {
                      if (!widget.isPrintOrder) return;
                      ref.read(printServiceProvider).updatePrinterSettings(
                            builtinPrinter: v,
                          );
                      logToFile(
                          tag: LogTag.UI_ACTION,
                          message: '기기 내장 프린터 사용 변경 -> $v');
                      widget.onUseBuiltinPrinterChanged(v);
                    },
                  ),
                ),
                SettingsItemWidget(
                  title: t.settings.external_printer.title,
                  description: t.settings.external_printer.desc,
                  enabled: widget.isPrintOrder,
                  trailing: CustomSwitch(
                    value: widget.isUseExternalPrinter,
                    activeColor: AppStyles.kMainColor,
                    inactiveColor: AppStyles.gray4,
                    activeText: t.settings.auto_start.on,
                    inactiveText: t.settings.auto_start.off,
                    onChanged: (v) {
                      if (!widget.isPrintOrder) return;
                      final ps = ref.read(printServiceProvider);
                      ps.updatePrinterSettings(externalPrinter: v);
                      if (v) ps.checkConnection();
                      logToFile(
                          tag: LogTag.UI_ACTION, message: '외부 프린터 사용 변경 -> $v');
                      widget.onUseExternalPrinterChanged(v);
                    },
                  ),
                  additionalContent: ExternalPrinterSubSettings(
                    isUseExternalPrinter: widget.isUseExternalPrinter,
                  ),
                ),
                SettingsItemWidget(
                  title: t.settings.label_printer.title,
                  description: t.settings.label_printer.desc,
                  trailing: CustomSwitch(
                    value: widget.isUseLabelPrinter,
                    activeColor: AppStyles.kMainColor,
                    inactiveColor: AppStyles.gray4,
                    activeText: t.settings.auto_start.on,
                    inactiveText: t.settings.auto_start.off,
                    onChanged: (v) {
                      final ps = ref.read(printServiceProvider);
                      ps.updatePrinterSettings(labelPrinter: v);
                      // checkConnection() 이 Platform.isWindows 분기에서
                      // backend.warmupOpen() 호출까지 처리하므로 여기서는 단순 호출.
                      if (v) ps.checkConnection();
                      logToFile(
                          tag: LogTag.UI_ACTION, message: '라벨 프린터 사용 변경 -> $v');
                      widget.onUseLabelPrinterChanged(v);
                    },
                  ),
                  additionalContent: Consumer(
                    builder: (_, ref, __) {
                      final status = ref.watch(printerStatusProvider);
                      return SettingsConnectionStatus(
                        isConnected: status.isLabelConnected,
                        onReconnect: () =>
                            ref.read(printServiceProvider).checkConnection(),
                      );
                    },
                  ),
                  showDivider:
                      !(widget.isUseLabelPrinter && widget.isTpcpStore),
                ),
                if (widget.isUseLabelPrinter && widget.isTpcpStore)
                  SettingsItemWidget(
                    title: t.settings.label_filter.title,
                    description: switch (widget.labelFilterMode) {
                      0 => t.settings.label_filter.desc_all,
                      1 => t.settings.label_filter.desc_waffle_only,
                      _ => t.settings.label_filter.desc_waffle_exclude,
                    },
                    isVertical: true,
                    showDivider: false,
                    trailing: Row(
                      children: [
                        _buildFilterModeButton(
                            t.settings.label_filter.btn_all, 0),
                        const SizedBox(width: AppSpacing.s8),
                        _buildFilterModeButton(
                            t.settings.label_filter.btn_waffle_only, 1),
                        const SizedBox(width: AppSpacing.s8),
                        _buildFilterModeButton(
                            t.settings.label_filter.btn_waffle_exclude, 2),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.s16),

            // ── SoundGraph 설정 카드 ───────────────────────────────────────
            if (!widget.isKdsMode)
              SettingsSectionCard(
                title: t.settings.soundgraph.title,
                icon: Icons.notifications_active_outlined,
                children: [
                  SettingsItemWidget(
                    title: t.settings.soundgraph.title,
                    description: t.settings.soundgraph.desc,
                    showDivider: widget.isSoundGraphEnabled,
                    trailing: CustomSwitch(
                      value: widget.isSoundGraphEnabled,
                      activeColor: AppStyles.kMainColor,
                      inactiveColor: AppStyles.gray4,
                      activeText: t.settings.auto_start.on,
                      inactiveText: t.settings.auto_start.off,
                      onChanged: (v) {
                        logToFile(
                            tag: LogTag.UI_ACTION,
                            message: 'SoundGraph 주문전송 변경 -> $v');
                        widget.onSoundGraphEnabledChanged(v);
                      },
                    ),
                  ),
                  if (widget.isSoundGraphEnabled)
                    SettingsItemWidget(
                      title: t.settings.soundgraph.market_id_dialog_title,
                      description: widget.soundGraphMarketId.isEmpty
                          ? t.settings.soundgraph.market_id_placeholder
                          : widget.soundGraphMarketId,
                      showDivider: false,
                      trailing: IconButton(
                        icon: const Icon(Icons.edit_outlined,
                            color: AppStyles.gray6),
                        onPressed: () => _showMarketIdDialog(context, t),
                      ),
                    ),
                ],
              ),
            const SizedBox(height: AppSpacing.s16),
          ],
        ),
      ),
    );
  }

  Future<void> _showMarketIdDialog(BuildContext context, Translations t) async {
    final controller = TextEditingController(text: widget.soundGraphMarketId);
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(t.settings.soundgraph.market_id_dialog_title),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: t.settings.soundgraph.market_id_placeholder,
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t.settings.soundgraph.market_id_dialog_cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(t.settings.soundgraph.market_id_dialog_save),
          ),
        ],
      ),
    );
    if (result != null) {
      widget.onSoundGraphMarketIdChanged(result);
    }
  }
}
