import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:appfit_order_agent/constants/app_styles.dart';
import 'package:appfit_order_agent/providers/providers.dart';
import 'package:appfit_order_agent/providers/brand_provider.dart';
import 'package:appfit_order_agent/providers/locale_provider.dart';
import 'package:appfit_order_agent/providers/currency_provider.dart';
import 'package:appfit_order_agent/providers/rotation_provider.dart';
import 'package:appfit_order_agent/services/platform_service.dart';
import 'package:appfit_order_agent/services/print_service.dart';
import 'package:appfit_order_agent/utils/brand_registry.dart';
import 'package:appfit_order_agent/utils/currency_unit.dart';
import 'package:appfit_order_agent/widgets/custom_switch.dart';
import 'package:appfit_order_agent/i18n/strings.g.dart';
import 'package:appfit_order_agent/widgets/settings/settings_section_card.dart';
import 'package:appfit_order_agent/widgets/settings/settings_item_widget.dart';
import 'package:appfit_order_agent/widgets/settings/settings_mode_switch.dart';
import 'package:appfit_order_agent/widgets/settings/builtin_printer_sub_settings.dart';
import 'package:appfit_order_agent/widgets/settings/external_printer_sub_settings.dart';
import 'package:appfit_order_agent/widgets/settings/label_printer_sub_settings.dart';
import 'package:appfit_order_agent/widgets/settings/settings_dual_monitor_section.dart';

/// 설정화면 좌측 패널 — 기기/언어/프린터 설정.
class SettingsLeftPanel extends ConsumerStatefulWidget {
  const SettingsLeftPanel({
    super.key,
    required this.isKdsMode,
    required this.isRotated180,
    required this.isAutoStart,
    required this.isIgnoreOtherDeviceKds,
    required this.isKdsAcceptOrders,
    required this.isAutoReceipt,
    required this.isPrintOrder,
    required this.isUseBuiltinPrinter,
    required this.isUseExternalPrinter,
    required this.isUseLabelPrinter,
    required this.isUseQrPrint,
    required this.builtinPrintOrder,
    required this.builtinPrintReceipt,
    required this.externalPrintOrder,
    required this.externalPrintReceipt,
    required this.labelFilterMode,
    required this.labelLayoutVersion,
    required this.isShowOrderTypeBadge,
    required this.isOrderSourceColor,
    required this.onModeSwitch,
    required this.onRotated180Changed,
    required this.onAutoStartChanged,
    required this.onIgnoreOtherDeviceKdsChanged,
    required this.onKdsAcceptOrdersChanged,
    required this.onAutoReceiptChanged,
    required this.onPrintOrderChanged,
    required this.onUseBuiltinPrinterChanged,
    required this.onUseExternalPrinterChanged,
    required this.onUseLabelPrinterChanged,
    required this.onUseQrPrintChanged,
    required this.onBuiltinPrintOrderChanged,
    required this.onBuiltinPrintReceiptChanged,
    required this.onExternalPrintOrderChanged,
    required this.onExternalPrintReceiptChanged,
    required this.onLabelFilterModeChanged,
    required this.onLabelLayoutVersionChanged,
    required this.onShowOrderTypeBadgeChanged,
    required this.onOrderSourceColorChanged,
    required this.isSoundGraphEnabled,
    required this.soundGraphMarketId,
    required this.onSoundGraphEnabledChanged,
    required this.onSoundGraphMarketIdChanged,
  });

  final bool isKdsMode;
  final bool isRotated180;
  final bool isAutoStart;
  final bool isIgnoreOtherDeviceKds;
  final bool isKdsAcceptOrders;
  final bool isAutoReceipt;
  final bool isPrintOrder;
  final bool isUseBuiltinPrinter;
  final bool isUseExternalPrinter;
  final bool isUseLabelPrinter;
  final bool isUseQrPrint;
  final bool builtinPrintOrder;
  final bool builtinPrintReceipt;
  final bool externalPrintOrder;
  final bool externalPrintReceipt;
  final int labelFilterMode;
  final int labelLayoutVersion;
  final bool isShowOrderTypeBadge;
  final bool isOrderSourceColor;

  final VoidCallback onModeSwitch;
  final void Function(bool) onRotated180Changed;
  final void Function(bool) onAutoStartChanged;
  final void Function(bool) onIgnoreOtherDeviceKdsChanged;
  final void Function(bool) onKdsAcceptOrdersChanged;
  final void Function(bool) onAutoReceiptChanged;
  final void Function(bool) onPrintOrderChanged;
  final void Function(bool) onUseBuiltinPrinterChanged;
  final void Function(bool) onUseExternalPrinterChanged;
  final void Function(bool) onUseLabelPrinterChanged;
  final void Function(bool) onUseQrPrintChanged;
  final void Function(bool) onBuiltinPrintOrderChanged;
  final void Function(bool) onBuiltinPrintReceiptChanged;
  final void Function(bool) onExternalPrintOrderChanged;
  final void Function(bool) onExternalPrintReceiptChanged;
  final void Function(int) onLabelFilterModeChanged;
  final void Function(int) onLabelLayoutVersionChanged;
  final void Function(bool) onShowOrderTypeBadgeChanged;
  final void Function(bool) onOrderSourceColorChanged;
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

  // 라벨 레이아웃 버전 선택 버튼 (filterMode 버튼과 동일 스타일)
  Widget _buildLayoutVersionButton(String label, int version) {
    final isSelected = widget.labelLayoutVersion == version;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          widget.onLabelLayoutVersionChanged(version);
          logToFile(
              tag: LogTag.UI_ACTION, message: '라벨 레이아웃 버전 변경 -> $version');
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
    // currentBrandProvider(일반 Provider)는 세션 첫 값을 캐시해 브랜드 전환 시
    // stale 된다. 매장 ID 를 즉석에서 읽는 currentBrandMeta() 로 현재 브랜드 해석.
    final brand = currentBrandMeta();
    final canLabelFilter =
        brand?.has(BrandFeature.labelCategoryFilter) ?? false;
    final canSoundGraph = brand?.has(BrandFeature.soundGraphSend) ?? false;
    // 라벨프린터 하위 아이템(필터/QR) 가시성. 라벨프린터 + 하위 아이템은
    // divider 없이 한 그룹으로 묶이므로(기존 디자인), 하위가 하나라도 있으면
    // 라벨프린터 아이템의 하단 divider 를 끈다.
    final showFilterItem = widget.isUseLabelPrinter && canLabelFilter;
    final showQrItem = widget.isUseLabelPrinter;
    final showLayoutItem = widget.isUseLabelPrinter;

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
              title: t.settings.section_mode,
              icon: Icons.dashboard_customize_outlined,
              children: [
                SettingsModeSwitch(
                  isKdsMode: widget.isKdsMode,
                  onSwitch: widget.onModeSwitch,
                ),
                if (widget.isKdsMode) ...[
                  const SizedBox(height: AppSpacing.s12),
                  SettingsItemWidget(
                    title: t.settings.kds_accept_orders.title,
                    description: t.settings.kds_accept_orders.desc,
                    showDivider: false,
                    trailing: CustomSwitch(
                      value: widget.isKdsAcceptOrders,
                      activeColor: AppStyles.kMainColor,
                      inactiveColor: AppStyles.gray4,
                      activeText: t.settings.auto_start.on,
                      inactiveText: t.settings.auto_start.off,
                      onChanged: (v) {
                        logToFile(
                            tag: LogTag.UI_ACTION,
                            message: 'KDS 주문 자동접수 변경 -> $v');
                        widget.onKdsAcceptOrdersChanged(v);
                      },
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.s16),

            // ── 일반 설정 카드 ─────────────────────────────────────────────
            SettingsSectionCard(
              title: t.settings.section_general,
              icon: Icons.tune,
              children: [
                // 1. 픽업 오더 자동 접수 (메인 모드 전용)
                if (!widget.isKdsMode)
                  SettingsItemWidget(
                    title: t.settings.auto_receipt.title,
                    description: t.settings.auto_receipt.desc,
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
                // 2. PC 시작 시 자동 실행
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
                // 3. 매장/포장 표시
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
                // 3-1. 주문 출처별 색상 (앱/키오스크) — 메인·KDS 공통
                SettingsItemWidget(
                  title: t.settings.order_source_color.title,
                  description: t.settings.order_source_color.desc,
                  trailing: CustomSwitch(
                    value: widget.isOrderSourceColor,
                    activeColor: AppStyles.kMainColor,
                    inactiveColor: AppStyles.gray4,
                    activeText: t.settings.auto_start.on,
                    inactiveText: t.settings.auto_start.off,
                    onChanged: (v) {
                      logToFile(
                          tag: LogTag.UI_ACTION, message: '주문 출처별 색상 변경 -> $v');
                      widget.onOrderSourceColorChanged(v);
                    },
                  ),
                ),
                // 4. 타 기기 진행상태 알림 무시 (KDS 모드 전용)
                if (widget.isKdsMode)
                  SettingsItemWidget(
                    title: t.settings.kds_ignore_status.title,
                    description: t.settings.kds_ignore_status.desc,
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
                // 5. 화면 상하 반전
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
                // 6. 언어 설정
                SettingsItemWidget(
                  title: t.settings.language.title,
                  description: t.settings.language.desc,
                  isVertical: true,
                  trailing: _buildLanguageSwitcher(),
                ),
                // 7. 화폐 단위 (마지막)
                SettingsItemWidget(
                  title: t.settings.currency.title,
                  description: t.settings.currency.desc,
                  isVertical: true,
                  showDivider: false,
                  trailing: _buildCurrencySwitcher(),
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
                Consumer(builder: (_, ref, __) {
                  // 내장 프린터 하드웨어 존재 여부. null = 아직 probe 중 → false 취급.
                  final builtinAvailable =
                      ref.watch(builtinPrinterAvailableProvider) ?? false;
                  return SettingsItemWidget(
                    title: t.settings.builtin_printer.title,
                    description: t.settings.builtin_printer.desc,
                    // 인쇄 자체가 OFF 이거나 내장 모듈이 없으면 토글 disable.
                    enabled: widget.isPrintOrder && builtinAvailable,
                    trailing: CustomSwitch(
                      // 미감지 시 강제 OFF 표시.
                      value:
                          builtinAvailable ? widget.isUseBuiltinPrinter : false,
                      activeColor: AppStyles.kMainColor,
                      inactiveColor: AppStyles.gray4,
                      activeText: t.settings.auto_start.on,
                      inactiveText: t.settings.auto_start.off,
                      onChanged: (v) {
                        if (!widget.isPrintOrder || !builtinAvailable) return;
                        ref.read(printServiceProvider).updatePrinterSettings(
                              builtinPrinter: v,
                            );
                        logToFile(
                            tag: LogTag.UI_ACTION,
                            message: '기기 내장 프린터 사용 변경 -> $v');
                        widget.onUseBuiltinPrinterChanged(v);
                      },
                    ),
                    additionalContent: BuiltinPrinterSubSettings(
                      isUseBuiltinPrinter: widget.isUseBuiltinPrinter,
                      available: builtinAvailable,
                      printOrder: widget.builtinPrintOrder,
                      printReceipt: widget.builtinPrintReceipt,
                      onPrintOrderChanged: widget.onBuiltinPrintOrderChanged,
                      onPrintReceiptChanged:
                          widget.onBuiltinPrintReceiptChanged,
                    ),
                  );
                }),
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
                      if (v) {
                        // Android: Posbank SDK 가 앱 시작 시점에만 한 번 discovery 를
                        // 돌리므로, 사용자가 토글을 켜는 시점에 명시적으로 재탐색을 시도.
                        // (USB 권한 dialog 도 이 시점에 표시.)
                        if (Platform.isAndroid) {
                          ps.reconnectExternalPrinter();
                        }
                        ps.checkConnection();
                      }
                      logToFile(
                          tag: LogTag.UI_ACTION, message: '외부 프린터 사용 변경 -> $v');
                      widget.onUseExternalPrinterChanged(v);
                    },
                  ),
                  additionalContent: ExternalPrinterSubSettings(
                    isUseExternalPrinter: widget.isUseExternalPrinter,
                    printOrder: widget.externalPrintOrder,
                    printReceipt: widget.externalPrintReceipt,
                    onPrintOrderChanged: widget.onExternalPrintOrderChanged,
                    onPrintReceiptChanged: widget.onExternalPrintReceiptChanged,
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
                      // checkConnection 이 Platform.isWindows 분기에서
                      // backend.warmupOpen 까지 처리. 라벨만 갱신해서 외부 status 토글 회피.
                      if (v) ps.checkConnection(external: false, label: true);
                      logToFile(
                          tag: LogTag.UI_ACTION, message: '라벨 프린터 사용 변경 -> $v');
                      widget.onUseLabelPrinterChanged(v);
                    },
                  ),
                  additionalContent: LabelPrinterSubSettings(
                    isUseLabelPrinter: widget.isUseLabelPrinter,
                  ),
                  showDivider:
                      !(showFilterItem || showQrItem || showLayoutItem),
                ),
                if (showFilterItem)
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
                if (showQrItem)
                  SettingsItemWidget(
                    title: t.settings.label_qr.title,
                    description: t.settings.label_qr.desc,
                    showDivider: false,
                    trailing: CustomSwitch(
                      value: widget.isUseQrPrint,
                      activeColor: AppStyles.kMainColor,
                      inactiveColor: AppStyles.gray4,
                      activeText: t.settings.auto_start.on,
                      inactiveText: t.settings.auto_start.off,
                      onChanged: (v) {
                        logToFile(
                            tag: LogTag.UI_ACTION,
                            message: 'QR 코드 출력 변경 -> $v');
                        widget.onUseQrPrintChanged(v);
                      },
                    ),
                  ),
                if (showLayoutItem)
                  SettingsItemWidget(
                    title: t.settings.label_layout.title,
                    description: switch (widget.labelLayoutVersion) {
                      1 => t.settings.label_layout.desc_v2,
                      _ => t.settings.label_layout.desc_v1,
                    },
                    isVertical: true,
                    showDivider: false,
                    trailing: Row(
                      children: [
                        _buildLayoutVersionButton(
                            t.settings.label_layout.btn_v1, 0),
                        const SizedBox(width: AppSpacing.s8),
                        _buildLayoutVersionButton(
                            t.settings.label_layout.btn_v2, 1),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.s16),

            // ── SoundGraph 설정 카드 (MHST 전용) ───────────────────────────
            if (!widget.isKdsMode && canSoundGraph)
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

            // ── 전면 모니터 콘텐츠 (D3 MINI 듀얼 모니터) ─────────────────────
            // 보조 디스플레이 + 현재 브랜드 콘텐츠(영상/이미지)가 있을 때만 섹션
            // 내부에서 노출(메인/KDS 모드 무관 — 듀얼 모니터는 두 모드 모두 동작).
            // 없으면 SizedBox.shrink() 로 숨김(모니터는 검은 화면).
            const SettingsDualMonitorSection(),
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
