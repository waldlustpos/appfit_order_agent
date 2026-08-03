import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:appfit_order_agent/i18n/strings.g.dart';
import 'package:appfit_order_agent/constants/app_styles.dart';
import 'package:appfit_order_agent/providers/brand_provider.dart';
import 'package:appfit_order_agent/providers/dual_monitor_provider.dart';
import 'package:appfit_order_agent/providers/preference_provider.dart';
import 'package:appfit_order_agent/services/platform_service.dart';
import 'package:appfit_order_agent/widgets/settings/settings_section_card.dart';
import 'package:appfit_order_agent/widgets/settings/settings_item_widget.dart';

/// 설정 화면의 "전면 모니터 콘텐츠"(D3 MINI 듀얼 모니터) 섹션.
///
/// 노출 조건: 기기에 보조 디스플레이가 있고(`hasSecondaryDisplay`) 현재 브랜드의
/// 콘텐츠(영상/이미지)가 하나라도 존재할 때만. 둘 다 없으면 섹션 자체를 숨기고
/// 모니터는 검은 화면이 된다.
///
/// 선택지: 영상+이미지 둘 다 → [영상/이미지/노출안함], 하나만 → [그것/노출안함].
/// 명시적으로 고르지 않았으면 이미지 우선 자동(effectiveMode)으로 표시되며, 그 상태가
/// 버튼 하이라이트로 보인다.
class SettingsDualMonitorSection extends ConsumerStatefulWidget {
  const SettingsDualMonitorSection({super.key});

  @override
  ConsumerState<SettingsDualMonitorSection> createState() =>
      _SettingsDualMonitorSectionState();
}

class _SettingsDualMonitorSectionState
    extends ConsumerState<SettingsDualMonitorSection> {
  // 운영자가 명시적으로 고른 모드. null=미설정 → effectiveMode 가 이미지 우선 자동 해석.
  String? _explicitMode;

  @override
  void initState() {
    super.initState();
    _explicitMode = ref.read(preferenceServiceProvider).getDualMonitorMode();
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    // currentBrandProvider 는 일반 Provider 라 세션 첫 값을 캐시하고 브랜드 전환
    // (로그아웃→다른 브랜드 로그인) 시 갱신되지 않는다. 매장 ID 를 즉석에서 읽는
    // currentBrandMeta() 로 항상 현재 브랜드를 해석한다.
    final brand = currentBrandMeta();
    if (brand == null) return const SizedBox.shrink();

    final capAsync =
        ref.watch(dualMonitorCapabilityProvider(brand.assetFolder));

    return capAsync.maybeWhen(
      data: (cap) {
        final hasSecondary = cap['hasSecondaryDisplay'] ?? false;
        final hasVideo = cap['hasVideo'] ?? false;
        final hasImage = cap['hasImage'] ?? false;

        // 보조 디스플레이가 없거나 콘텐츠가 하나도 없으면 섹션 비노출(검은 화면).
        if (!hasSecondary || (!hasVideo && !hasImage)) {
          return const SizedBox.shrink();
        }

        final options = <_DualMode>[
          if (hasVideo) _DualMode.video,
          if (hasImage) _DualMode.image,
          _DualMode.none,
        ];
        final effective = _effectiveMode(_explicitMode, hasVideo, hasImage);

        return SettingsSectionCard(
          title: t.settings.dual_monitor.title,
          icon: Icons.cast_outlined,
          children: [
            SettingsItemWidget(
              title: t.settings.dual_monitor.title,
              description: t.settings.dual_monitor.desc,
              isVertical: true,
              showDivider: false,
              trailing: SizedBox(
                width: double.infinity,
                child: Row(
                  children: [
                    for (final mode in options)
                      Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.s8),
                        child: ElevatedButton(
                          onPressed: () => _onSelect(mode),
                          style:
                              AppStyles.settingsToggleButton(effective == mode),
                          child: Text(
                            _labelFor(t, mode),
                            style: TextStyle(
                              fontWeight: effective == mode
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }

  String _labelFor(Translations t, _DualMode mode) {
    switch (mode) {
      case _DualMode.video:
        return t.settings.dual_monitor.option_video;
      case _DualMode.image:
        return t.settings.dual_monitor.option_image;
      case _DualMode.none:
        return t.settings.dual_monitor.option_none;
    }
  }

  /// 네이티브 DualMonitorPresentation 과 동일한 해석 규칙(effectiveMode):
  /// 명시 선택이 존재 콘텐츠와 맞으면 그것, 아니면 이미지 우선 자동(image>video>none).
  _DualMode _effectiveMode(String? explicit, bool hasVideo, bool hasImage) {
    if (explicit == 'none') return _DualMode.none;
    if (explicit == 'image' && hasImage) return _DualMode.image;
    if (explicit == 'video' && hasVideo) return _DualMode.video;
    if (hasImage) return _DualMode.image;
    if (hasVideo) return _DualMode.video;
    return _DualMode.none;
  }

  Future<void> _onSelect(_DualMode mode) async {
    await ref.read(preferenceServiceProvider).setDualMonitorMode(mode.name);
    await PlatformService.setDualMonitorMode(mode.name);
    logToFile(tag: LogTag.UI_ACTION, message: '듀얼모니터 콘텐츠 모드 변경: ${mode.name}');
    if (!mounted) return;
    setState(() => _explicitMode = mode.name);
  }
}

enum _DualMode { video, image, none }
