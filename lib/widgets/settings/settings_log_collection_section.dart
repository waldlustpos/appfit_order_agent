import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:appfit_order_agent/constants/app_styles.dart';
import 'package:appfit_order_agent/i18n/strings.g.dart';
import 'package:appfit_order_agent/providers/providers.dart';
import 'package:appfit_order_agent/services/log_collection/log_collection_request.dart';
import 'package:appfit_order_agent/services/log_collection/log_collection_service.dart';
import 'package:appfit_order_agent/services/monitoring/device_identity_service.dart';
import 'package:appfit_order_agent/services/platform_service.dart';
import 'package:appfit_order_agent/widgets/settings/settings_section_card.dart';

// 기간 프리셋·캡션·파일명 조립은 log_collection_request.dart 가 정본이다.
// 원격 명령(FleetCommandHandler)이 같은 함수를 쓰므로 Slack 메시지 포맷이
// 수동/원격으로 갈라지지 않는다.

/// 설정화면 "로그 전송" 카드 (자기완결형).
///
/// 기기 식별(매장명+매장코드+시리얼/installId)을 표시하고, 날짜 프리셋으로
/// 로그를 수집 -> zip -> Slack(sink)으로 전송한다. 원격 명령(RemoteCommandHandler)
/// 과 동일한 [LogCollectionService] 경로를 쓰며, 수동 버튼으로 전체 시나리오를
/// 재현한다. provider 를 직접 watch 하므로 상위 패널에 파라미터 추가가 필요 없다.
class SettingsLogCollectionSection extends ConsumerStatefulWidget {
  const SettingsLogCollectionSection({super.key});

  @override
  ConsumerState<SettingsLogCollectionSection> createState() =>
      _SettingsLogCollectionSectionState();
}

class _SettingsLogCollectionSectionState
    extends ConsumerState<SettingsLogCollectionSection> {
  LogRangePreset _preset = LogRangePreset.today;
  DeviceIdentity? _identity;
  bool _busy = false;
  LogCollectionStage _stage = LogCollectionStage.idle;
  String? _resultText;
  bool _resultOk = false;

  @override
  void initState() {
    super.initState();
    _loadIdentity();
  }

  Future<void> _loadIdentity() async {
    final id = await ref.read(deviceIdentityServiceProvider).resolve();
    if (mounted) setState(() => _identity = id);
  }

  Future<void> _send() async {
    if (_busy) return;
    final t = Translations.of(context);
    final svc = ref.read(logCollectionServiceProvider);
    final sink = ref.read(logUploadSinkProvider);

    if (!sink.isConfigured) {
      setState(() {
        _resultOk = false;
        _resultText = t.settings.log_collection.not_configured;
      });
      return;
    }

    final id =
        _identity ?? await ref.read(deviceIdentityServiceProvider).resolve();
    final range = resolveLogRange(_preset);
    // 매장명은 앱바와 동일한 소스(storeProvider)를 사용한다.
    final storeName = ref.read(storeProvider).value?.name ?? '';
    // 캡션/파일명 조립은 원격 명령과 공유하는 정본 함수가 담당한다.
    final request = buildLogCollectionRequest(
      identity: id,
      storeName: storeName,
      from: range.from,
      to: range.to,
    );

    setState(() {
      _busy = true;
      _resultText = null;
      _stage = LogCollectionStage.flushing;
    });
    logToFile(
      tag: LogTag.UI_ACTION,
      message: '로그 전송 시작 '
          '(${formatLogDate(range.from)}~${formatLogDate(range.to)})',
    );

    final outcome = await svc.collectAndUpload(
      from: request.from,
      to: request.to,
      caption: request.caption,
      filename: request.filename,
      onStage: (s) {
        if (mounted) setState(() => _stage = s);
      },
    );

    if (!mounted) return;
    setState(() {
      _busy = false;
      _resultOk = outcome.success;
      _resultText = outcome.success
          ? t.settings.log_collection.success(
              count: outcome.fileCount,
              size: humanSize(outcome.zipBytes),
            )
          : t.settings.log_collection.failed(error: outcome.error ?? '-');
    });
  }

  String _stageText(BuildContext context) {
    final t = Translations.of(context);
    switch (_stage) {
      case LogCollectionStage.flushing:
        return t.settings.log_collection.stage_flushing;
      case LogCollectionStage.collecting:
        return t.settings.log_collection.stage_collecting;
      case LogCollectionStage.zipping:
        return t.settings.log_collection.stage_zipping;
      case LogCollectionStage.uploading:
        return t.settings.log_collection.stage_uploading;
      case LogCollectionStage.idle:
      case LogCollectionStage.done:
      case LogCollectionStage.failed:
        return t.settings.log_collection.send_btn;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final id = _identity;
    // 매장명은 앱바와 동일한 소스(storeProvider)를 사용한다.
    final storeName = ref.watch(storeProvider).value?.name ?? '';

    return SettingsSectionCard(
      title: t.settings.log_collection.section_title,
      icon: Icons.bug_report_outlined,
      children: [
        Text(
          t.settings.log_collection.section_desc,
          style: AppTextStyles.bodySm.copyWith(color: AppStyles.gray6),
        ),
        const SizedBox(height: AppSpacing.s12),
        if (id != null) ...[
          _kv(
            t.settings.log_collection.brand_label,
            (id.projectName?.isNotEmpty ?? false) ? id.projectName! : '-',
          ),
          _kv(
            t.settings.log_collection.store_name_label,
            storeName.isEmpty ? '-' : storeName,
          ),
          _kv(
            t.settings.log_collection.store_code_label,
            (id.shopCode?.isNotEmpty ?? false) ? id.shopCode! : '-',
          ),
          _kv(
            t.settings.log_collection.device_label,
            id.deviceLabel,
          ),
          const SizedBox(height: AppSpacing.s12),
        ],
        Row(
          children: [
            _presetChip(
                LogRangePreset.today, t.settings.log_collection.range_today),
            _presetChip(
                LogRangePreset.days7, t.settings.log_collection.range_7days),
            _presetChip(
                LogRangePreset.days30, t.settings.log_collection.range_30days),
          ],
        ),
        const SizedBox(height: AppSpacing.s12),
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: _busy ? null : _send,
              style: AppStyles.primaryButton(),
              icon: _busy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send_outlined, size: 16),
              label: Text(
                _busy
                    ? _stageText(context)
                    : t.settings.log_collection.send_btn,
              ),
            ),
          ],
        ),
        if (_resultText != null) ...[
          const SizedBox(height: AppSpacing.s8),
          Text(
            _resultText!,
            style: AppTextStyles.bodySm.copyWith(
              color: _resultOk ? AppStyles.green100 : AppStyles.kRed,
            ),
          ),
        ],
      ],
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.s4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 56,
              child: Text(
                k,
                style: AppTextStyles.caption.copyWith(color: AppStyles.gray6),
              ),
            ),
            Expanded(
              child: Text(
                v,
                style: AppTextStyles.bodySm.copyWith(color: AppStyles.gray9),
              ),
            ),
          ],
        ),
      );

  Widget _presetChip(LogRangePreset preset, String label) {
    final selected = _preset == preset;
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.s8),
      child: ElevatedButton(
        onPressed: _busy ? null : () => setState(() => _preset = preset),
        style: AppStyles.settingsToggleButton(selected),
        child: Text(
          label,
          style: TextStyle(
              fontWeight: selected ? FontWeight.bold : FontWeight.normal),
        ),
      ),
    );
  }
}
