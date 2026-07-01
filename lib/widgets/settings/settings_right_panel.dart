import 'dart:io' show Platform;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:appfit_order_agent/constants/app_styles.dart';
import 'package:appfit_order_agent/constants/brand_theme.dart';
import 'package:appfit_order_agent/providers/providers.dart';
import 'package:appfit_order_agent/providers/brand_provider.dart';
import 'package:appfit_order_agent/services/local_server_service.dart';
import 'package:appfit_order_agent/services/platform_service.dart';
import 'package:appfit_order_agent/utils/logger.dart';
import 'package:appfit_order_agent/widgets/custom_switch.dart';
import 'package:appfit_order_agent/i18n/strings.g.dart';
import 'package:appfit_order_agent/widgets/settings/settings_section_card.dart';
import 'package:appfit_order_agent/widgets/settings/settings_item_widget.dart';
import 'package:appfit_order_agent/widgets/settings/settings_developer_options.dart';
import 'package:appfit_order_agent/widgets/settings/settings_brand_theme_section.dart';

/// 설정화면 우측 패널 — 알림/키오스크/출력/업데이트 설정.
class SettingsRightPanel extends ConsumerStatefulWidget {
  const SettingsRightPanel({
    super.key,
    required this.isKdsMode,
    required this.notificationVolume,
    required this.selectedSound,
    required this.alertCount,
    required this.isKioskOrderVisible,
    required this.isKioskOrderSoundEnabled,
    required this.isLocalServerEnabled,
    required this.isLocalServerRunning,
    required this.printCount,
    required this.isAutoCheckUpdate,
    required this.isCheckingUpdate,
    required this.updateInfo,
    required this.isDevOptionsVisible,
    required this.devOptionsTapCount,
    required this.forceSocketReconnect,
    required this.selectedEnv,
    // 라벨 테스트 props
    required this.labelAutoReplyMode,
    required this.labelUseFeedToTear,
    required this.labelUseBackToPrint,
    required this.labelUseCalibrate,
    // 콜백
    required this.onVolumeChanged,
    required this.onVolumeChangeEnd,
    required this.onSoundChanged,
    required this.onAlertCountChanged,
    required this.onKioskOrderVisibleChanged,
    required this.onKioskOrderSoundChanged,
    required this.onLocalServerChanged,
    required this.onPrintCountChanged,
    required this.onAutoCheckUpdateChanged,
    required this.onCheckUpdate,
    required this.onPerformUpdate,
    required this.onDevOptionsTap,
    required this.onForceSocketReconnectChanged,
    required this.onEnvChanged,
    required this.onAutoReplyModeChanged,
    required this.onFeedToTearChanged,
    required this.onBackToPrintChanged,
    required this.onCalibrateChanged,
    required this.isParanmanjanTestRunning,
    required this.onParanmanjanTest,
  });

  final bool isKdsMode;
  final int notificationVolume;
  final String selectedSound;
  final int alertCount;
  final bool isKioskOrderVisible;
  final bool isKioskOrderSoundEnabled;
  final bool isLocalServerEnabled;
  final bool isLocalServerRunning;
  final int printCount;
  final bool isAutoCheckUpdate;
  final bool isCheckingUpdate;
  final dynamic updateInfo; // UpdateInfo?
  final bool isDevOptionsVisible;
  final int devOptionsTapCount;
  final bool forceSocketReconnect;
  final String selectedEnv;
  final int labelAutoReplyMode;
  final bool labelUseFeedToTear;
  final bool labelUseBackToPrint;
  final bool labelUseCalibrate;

  final void Function(int) onVolumeChanged;
  final void Function(double) onVolumeChangeEnd;
  final void Function(String) onSoundChanged;
  final void Function(int) onAlertCountChanged;
  final void Function(bool) onKioskOrderVisibleChanged;
  final void Function(bool) onKioskOrderSoundChanged;
  final void Function(bool) onLocalServerChanged;
  final void Function(int) onPrintCountChanged;
  final void Function(bool) onAutoCheckUpdateChanged;
  final VoidCallback onCheckUpdate;
  final VoidCallback onPerformUpdate;
  final VoidCallback onDevOptionsTap;
  final void Function(bool) onForceSocketReconnectChanged;
  final void Function(String) onEnvChanged;
  final void Function(int) onAutoReplyModeChanged;
  final void Function(bool) onFeedToTearChanged;
  final void Function(bool) onBackToPrintChanged;
  final void Function(bool) onCalibrateChanged;
  final bool isParanmanjanTestRunning;
  final VoidCallback onParanmanjanTest;

  @override
  ConsumerState<SettingsRightPanel> createState() => _SettingsRightPanelState();
}

class _SettingsRightPanelState extends ConsumerState<SettingsRightPanel> {
  final ScrollController _scrollController = ScrollController();
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isVolumeChanging = false;

  @override
  void dispose() {
    _scrollController.dispose();
    // Sentry APPFIT-ORDER-AGENT-N: 이미 dispose 된 플레이어에 다시 dispose 가
    // 호출되면 IllegalStateException 이 발생하므로 안전하게 감싼다.
    try {
      _audioPlayer.dispose();
    } catch (e) {
      logger.w('[SettingsRightPanel] AudioPlayer dispose 중 예외 무시: $e');
    }
    super.dispose();
  }

  Future<void> _playSound(String soundFile) async {
    try {
      await _audioPlayer.play(AssetSource('sounds/$soundFile'));
    } catch (e) {
      logger.e('Error playing sound: $e');
    }
  }

  Future<void> _playSoundSafely(String soundFile) async {
    try {
      await _audioPlayer.play(AssetSource('sounds/$soundFile'));
    } catch (_) {
      try {
        await Future.delayed(const Duration(milliseconds: 100));
        await _audioPlayer.play(AssetSource('sounds/$soundFile'));
      } catch (e) {
        logger.e('사운드 재생 재시도도 실패: $e');
      }
    }
  }

  // ── 버튼 빌더들 ───────────────────────────────────────────────────────────

  Widget _soundButton(String value, String label) {
    final isSelected = widget.selectedSound == value;
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.s8),
      child: ElevatedButton(
        onPressed: () async {
          widget.onSoundChanged(value);
          await _playSound(value);
          ref.read(orderProvider.notifier).updateSoundSettings();
          logToFile(tag: LogTag.UI_ACTION, message: '알림음 변경 -> $value');
        },
        style: AppStyles.settingsToggleButton(isSelected),
        child: Text(
          label,
          style: TextStyle(
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
        ),
      ),
    );
  }

  Widget _countButton<T>(
      T value, String label, T current, void Function(T) onTap) {
    final isSelected = current == value;
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.s8),
      child: ElevatedButton(
        onPressed: () => onTap(value),
        style: AppStyles.settingsToggleButton(isSelected),
        child: Text(
          label,
          style: TextStyle(
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
        ),
      ),
    );
  }

  // ── 로컬 서버 정보 박스 ───────────────────────────────────────────────────

  Widget _buildLocalServerInfo() {
    final t = Translations.of(context);
    final localServer = LocalServerService.instance;
    final serverUrl = localServer?.serverUrl;
    final localIp = localServer?.localIp;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.s12),
      decoration: BoxDecoration(
        color: widget.isLocalServerRunning
            ? AppStyles.green100.withValues(alpha: 0.08)
            : AppStyles.gray2,
        borderRadius: AppRadius.bSm,
        border: Border.all(
          color: widget.isLocalServerRunning
              ? AppStyles.green100.withValues(alpha: 0.3)
              : AppStyles.gray3,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.settings.local_server.info,
            style: AppTextStyles.bodySm.copyWith(
              fontWeight: FontWeight.bold,
              color: widget.isLocalServerRunning
                  ? AppStyles.green100
                  : AppStyles.gray6,
            ),
          ),
          const SizedBox(height: AppSpacing.s8),
          Text(
            t.settings.local_server.ip(ip: localIp ?? 'Loading...'),
            style: AppTextStyles.bodySm.copyWith(color: AppStyles.gray6),
          ),
          const SizedBox(height: AppSpacing.s4),
          Text(
            t.settings.local_server.port(port: localServer?.port ?? 8080),
            style: AppTextStyles.bodySm.copyWith(color: AppStyles.gray6),
          ),
          if (serverUrl != null) ...[
            const SizedBox(height: AppSpacing.s4),
            Text(
              t.settings.local_server.url(url: serverUrl),
              style: AppTextStyles.bodySm.copyWith(color: AppStyles.gray6),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);

    // currentBrandProvider 는 세션 첫 값을 캐시해 브랜드 전환 시 stale 되므로,
    // 매장 ID 를 즉석에서 읽는 currentBrandMeta() 로 현재 브랜드를 해석한다
    // (settings_left_panel 의 SoundGraph/라벨필터 게이팅과 동일 관용구).
    final brand = currentBrandMeta();
    final brandThemes = brand?.selectableThemes ?? const <BrandTheme>[];
    // 일반 사용자용 테마 picker: 브랜드 고유 테마가 있을 때만(기본+브랜드 2종),
    // 개발자 옵션 OFF 일 때만. 개발자 옵션 ON 이면 하단의 전체 4종 picker 만 노출.
    final showBrandThemePicker =
        brandThemes.length > 1 && !widget.isDevOptionsVisible;

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
            // ── 테마 설정 카드 (브랜드별 기본+브랜드테마 2종) ──────────────────
            if (showBrandThemePicker) ...[
              SettingsBrandThemeSection(themes: brandThemes),
              const SizedBox(height: AppSpacing.s16),
            ],
            // ── 알림 설정 카드 ─────────────────────────────────────────────
            SettingsSectionCard(
              title: t.settings.section_sound,
              icon: Icons.notifications_outlined,
              children: [
                // 알림음 크기
                SettingsItemWidget(
                  title: t.settings.volume.title,
                  description: t.settings.volume.desc,
                  isVertical: true,
                  trailing: SizedBox(
                    width: double.infinity,
                    child: Row(
                      children: [
                        Expanded(
                          child: Slider(
                            value: widget.notificationVolume
                                .toDouble()
                                .clamp(0, 10),
                            min: 0,
                            max: 10,
                            divisions: 10,
                            label: widget.notificationVolume.round().toString(),
                            activeColor: AppStyles.kMainColor,
                            inactiveColor:
                                AppStyles.kMainColor.withValues(alpha: 0.2),
                            onChanged: (v) => widget.onVolumeChanged(v.toInt()),
                            onChangeEnd: (v) async {
                              if (_isVolumeChanging) return;
                              _isVolumeChanging = true;
                              try {
                                widget.onVolumeChangeEnd(v);
                                await _audioPlayer.stop();
                                await Future.delayed(
                                    const Duration(milliseconds: 100));
                                await _audioPlayer.setVolume(v / 10.0);
                                await _audioPlayer.setAudioContext(
                                  AudioContext(
                                    android: const AudioContextAndroid(
                                      audioFocus: AndroidAudioFocus.none,
                                    ),
                                  ),
                                );
                                await Future.delayed(
                                    const Duration(milliseconds: 50));
                                await _playSoundSafely('alert10.mp3');
                                ref
                                    .read(orderProvider.notifier)
                                    .updateSoundSettings();
                                logToFile(
                                    tag: LogTag.UI_ACTION,
                                    message: '알림음 크기 변경 -> ${v.toInt()}');
                              } catch (e) {
                                logger.e('음량 변경 중 오류: $e');
                              } finally {
                                _isVolumeChanging = false;
                              }
                            },
                          ),
                        ),
                        Text(
                          '${widget.notificationVolume.round()}',
                          style: AppTextStyles.body.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppStyles.gray9,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // 알림음 선택
                SettingsItemWidget(
                  title: t.settings.sound.title,
                  description: t.settings.sound.desc,
                  isVertical: true,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _soundButton('alert10.mp3', t.settings.sound.sound1),
                      _soundButton('alert_speech.mp3', t.settings.sound.sound2),
                    ],
                  ),
                ),
                // 알림 횟수
                SettingsItemWidget(
                  title: t.settings.alert_count.title,
                  description: t.settings.alert_count.desc,
                  isVertical: true,
                  showDivider: false,
                  trailing: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _countButton(1, t.settings.alert_count.count(n: 1),
                            widget.alertCount, (v) {
                          widget.onAlertCountChanged(v);
                          ref
                              .read(orderProvider.notifier)
                              .updateSoundSettings();
                          logToFile(
                              tag: LogTag.UI_ACTION, message: '알림횟수 변경 -> $v회');
                        }),
                        _countButton(3, t.settings.alert_count.count(n: 3),
                            widget.alertCount, (v) {
                          widget.onAlertCountChanged(v);
                          ref
                              .read(orderProvider.notifier)
                              .updateSoundSettings();
                        }),
                        _countButton(5, t.settings.alert_count.count(n: 5),
                            widget.alertCount, (v) {
                          widget.onAlertCountChanged(v);
                          ref
                              .read(orderProvider.notifier)
                              .updateSoundSettings();
                        }),
                        _countButton(10, t.settings.alert_count.count(n: 10),
                            widget.alertCount, (v) {
                          widget.onAlertCountChanged(v);
                          ref
                              .read(orderProvider.notifier)
                              .updateSoundSettings();
                        }),
                        _countButton(0, t.settings.alert_count.unlimited,
                            widget.alertCount, (v) {
                          widget.onAlertCountChanged(v);
                          ref
                              .read(orderProvider.notifier)
                              .updateSoundSettings();
                        }),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s16),

            // ── 키오스크 설정 카드 ─────────────────────────────────────────
            SettingsSectionCard(
              title: t.settings.section_kiosk,
              icon: Icons.tablet_outlined,
              children: [
                SettingsItemWidget(
                  title: t.settings.kiosk.visible_title,
                  description: t.settings.kiosk.visible_desc,
                  trailing: CustomSwitch(
                    value: widget.isKioskOrderVisible,
                    activeColor: AppStyles.kMainColor,
                    inactiveColor: AppStyles.gray4,
                    activeText: t.settings.auto_start.on,
                    inactiveText: t.settings.auto_start.off,
                    onChanged: (v) {
                      logToFile(
                          tag: LogTag.UI_ACTION,
                          message: '키오스크 주문 노출 변경 -> $v');
                      widget.onKioskOrderVisibleChanged(v);
                      ref.read(orderProvider.notifier).updateKioskSettings();
                    },
                  ),
                ),
                SettingsItemWidget(
                  title: t.settings.kiosk.sound_title,
                  description: t.settings.kiosk.sound_desc,
                  enabled: widget.isKioskOrderVisible,
                  showDivider: false,
                  trailing: CustomSwitch(
                    value: widget.isKioskOrderSoundEnabled,
                    activeColor: AppStyles.kMainColor,
                    inactiveColor: AppStyles.gray4,
                    activeText: t.settings.auto_start.on,
                    inactiveText: t.settings.auto_start.off,
                    onChanged: (v) {
                      if (!widget.isKioskOrderVisible) return;
                      logToFile(
                          tag: LogTag.UI_ACTION,
                          message: '키오스크 주문 출력/알람 변경 -> $v');
                      widget.onKioskOrderSoundChanged(v);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s16),

            // ── 서버 설정 카드 (일반 모드만) ───────────────────────────────
            if (!widget.isKdsMode) ...[
              SettingsSectionCard(
                title: t.settings.section_server,
                icon: Icons.dns_outlined,
                children: [
                  SettingsItemWidget(
                    title: t.settings.local_server.title,
                    description: t.settings.local_server.desc,
                    showDivider: !widget.isLocalServerEnabled,
                    trailing: CustomSwitch(
                      value: widget.isLocalServerEnabled,
                      activeColor: AppStyles.kMainColor,
                      inactiveColor: AppStyles.gray4,
                      activeText: 'ON',
                      inactiveText: 'OFF',
                      onChanged: widget.onLocalServerChanged,
                    ),
                  ),
                  if (widget.isLocalServerEnabled)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.s4),
                      child: _buildLocalServerInfo(),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.s16),
            ],

            // ── 출력 설정 카드 ─────────────────────────────────────────────
            SettingsSectionCard(
              title: t.settings.section_print_count,
              icon: Icons.content_copy_outlined,
              children: [
                SettingsItemWidget(
                  title: t.settings.print_count.title,
                  description: t.settings.print_count.desc,
                  isVertical: true,
                  showDivider: false,
                  trailing: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [1, 2, 3, 4, 5].map((n) {
                        return _countButton(
                            n,
                            t.settings.print_count.count(n: n),
                            widget.printCount, (v) {
                          widget.onPrintCountChanged(v);
                          logToFile(
                              tag: LogTag.UI_ACTION,
                              message: '주문서 출력 개수 변경 -> $v개');
                        });
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s16),

            // ── 업데이트 카드 ─────────────────────────────────────────────
            SettingsSectionCard(
              title: t.settings.section_update,
              icon: Icons.system_update_outlined,
              children: [
                SettingsItemWidget(
                  title: t.settings.app_update.auto_check_title,
                  description: t.settings.app_update.auto_check_desc,
                  trailing: CustomSwitch(
                    value: widget.isAutoCheckUpdate,
                    activeColor: AppStyles.kMainColor,
                    inactiveColor: AppStyles.gray4,
                    activeText: 'ON',
                    inactiveText: 'OFF',
                    onChanged: widget.onAutoCheckUpdateChanged,
                  ),
                ),
                SettingsItemWidget(
                  title: t.settings.app_update.manual_title,
                  description: widget.isCheckingUpdate
                      ? t.settings.app_update.checking
                      : (widget.updateInfo == null
                          ? t.settings.app_update.check_failed
                          : (widget.updateInfo!.hasUpdate
                              ? t.settings.app_update.version_info(
                                  currentVersion:
                                      widget.updateInfo!.currentVersion,
                                  latestVersion:
                                      widget.updateInfo!.latestVersion,
                                )
                              : t.settings.app_update.up_to_date)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OutlinedButton(
                        onPressed: widget.isCheckingUpdate
                            ? null
                            : widget.onCheckUpdate,
                        child: Text(t.settings.app_update.check_btn),
                      ),
                      if (widget.updateInfo != null &&
                          widget.updateInfo!.hasUpdate) ...[
                        const SizedBox(width: AppSpacing.s8),
                        ElevatedButton(
                          onPressed: widget.onPerformUpdate,
                          style: AppStyles.primaryButton(),
                          child: Text(t.settings.app_update.update_btn),
                        ),
                      ],
                    ],
                  ),
                ),
                // 앱 버전 (5번 탭 → 개발자 옵션)
                // 탭 영역을 넓고 관대하게: 가로 전체 + 넉넉한 padding +
                // 빈 공간도 히트되도록 opaque. 손이 빗나가도 개발자 옵션 진입 가능.
                GestureDetector(
                  onTap: widget.onDevOptionsTap,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    width: double.infinity,
                    alignment: Alignment.center,
                    padding:
                        const EdgeInsets.symmetric(vertical: AppSpacing.s24),
                    child: Platform.isWindows
                        ? Text(
                            'v${const String.fromEnvironment('WINDOWS_APP_VERSION', defaultValue: '0.0.0')} '
                            '(${const String.fromEnvironment('WINDOWS_APP_BUILD', defaultValue: '0')})',
                            style: AppTextStyles.caption
                                .copyWith(color: AppStyles.gray4),
                          )
                        : ref.watch(appInfoProvider).whenOrNull(
                                  data: (info) => Text(
                                    'v${info.version} (${info.buildNumber})',
                                    style: AppTextStyles.caption
                                        .copyWith(color: AppStyles.gray4),
                                  ),
                                ) ??
                            const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s16),

            // ── 개발자 옵션 (숨김) ─────────────────────────────────────────
            if (widget.isDevOptionsVisible) ...[
              const SettingsBrandThemeSection(),
              const SizedBox(height: AppSpacing.s16),
            ],
            if (widget.isDevOptionsVisible)
              SettingsDeveloperOptions(
                forceSocketReconnect: widget.forceSocketReconnect,
                selectedEnv: widget.selectedEnv,
                onForceSocketReconnectChanged:
                    widget.onForceSocketReconnectChanged,
                onEnvChanged: widget.onEnvChanged,
                labelAutoReplyMode: widget.labelAutoReplyMode,
                labelUseFeedToTear: widget.labelUseFeedToTear,
                labelUseBackToPrint: widget.labelUseBackToPrint,
                labelUseCalibrate: widget.labelUseCalibrate,
                onAutoReplyModeChanged: widget.onAutoReplyModeChanged,
                onFeedToTearChanged: widget.onFeedToTearChanged,
                onBackToPrintChanged: widget.onBackToPrintChanged,
                onCalibrateChanged: widget.onCalibrateChanged,
                isParanmanjanTestRunning: widget.isParanmanjanTestRunning,
                onParanmanjanTest: widget.onParanmanjanTest,
              ),
            const SizedBox(height: AppSpacing.s16),
          ],
        ),
      ),
    );
  }
}
