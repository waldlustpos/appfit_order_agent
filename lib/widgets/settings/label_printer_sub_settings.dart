import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:appfit_order_agent/constants/app_styles.dart';
import 'package:appfit_order_agent/i18n/strings.g.dart';
import 'package:appfit_order_agent/providers/providers.dart';
import 'package:appfit_order_agent/services/platform_service.dart';
import 'package:appfit_order_agent/services/print_service.dart';
import 'package:appfit_order_agent/widgets/settings/settings_connection_status.dart';

/// "라벨 프린터 사용" 토글의 additionalContent.
///
/// 외부 영수증 프린터와 동일한 패턴: 연결상태 + 재연결 버튼 + 테스트 출력 버튼.
/// 재연결 버튼은 [PrintService.checkConnection] 을 `label: true, external: false`
/// 로 호출하여 외부 프린터 status 와 동시에 토글되는 sync 이슈를 회피.
class LabelPrinterSubSettings extends ConsumerStatefulWidget {
  const LabelPrinterSubSettings({
    super.key,
    required this.isUseLabelPrinter,
    required this.labelPaperSizeMm,
    required this.onLabelPaperSizeChanged,
  });

  final bool isUseLabelPrinter;

  /// 장착한 라벨 용지 폭(mm). 40 | 58.
  final int labelPaperSizeMm;
  final void Function(int) onLabelPaperSizeChanged;

  @override
  ConsumerState<LabelPrinterSubSettings> createState() =>
      _LabelPrinterSubSettingsState();
}

class _LabelPrinterSubSettingsState
    extends ConsumerState<LabelPrinterSubSettings> {
  bool _isTesting = false;
  String? _testResult;

  Future<void> _handleTestPrint() async {
    if (_isTesting) return;
    setState(() {
      _isTesting = true;
      _testResult = '출력 중...';
    });
    logToFile(tag: LogTag.UI_ACTION, message: '라벨 테스트 출력 시도');
    bool ok = false;
    try {
      ok = await ref.read(printServiceProvider).printLabelTestPage();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isTesting = false;
        _testResult = '테스트 출력 실패: $e';
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _isTesting = false;
      _testResult = ok ? '테스트 출력 성공' : '테스트 출력 실패';
    });
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(printerStatusProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsConnectionStatus(
          isConnected: status.isLabelConnected,
          detail: status.labelPrinterModel,
          onReconnect: () => ref
              .read(printServiceProvider)
              .checkConnection(external: false, label: true),
        ),
        if (widget.isUseLabelPrinter) ...[
          const SizedBox(height: AppSpacing.s12),
          _buildTestPrintRow(),
        ],
        // 용지 사이즈 선택은 G30 에서만 의미가 있다 — 다른 기종은 전부 고정 크기
        // 갭 라벨이라 선택지를 보여주면 오히려 오설정을 유도한다.
        if (widget.isUseLabelPrinter &&
            status.labelPrinterModel == kBixolonG30ModelName) ...[
          const SizedBox(height: AppSpacing.s16),
          _buildPaperSizeRow(),
        ],
      ],
    );
  }

  /// 40mm/58mm 선택. G30 은 한 대가 가이드 부품 교체만으로 겸용인데 SDK 가 로드된
  /// 용지 폭을 보고하지 않아 자동 감지가 불가능하다 — 매장이 고른 값이 유일한 근거다.
  Widget _buildPaperSizeRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t.settings.label_paper.title,
          style: AppTextStyles.bodySm.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: AppSpacing.s4),
        Text(
          widget.labelPaperSizeMm == 58
              ? t.settings.label_paper.desc_58
              : t.settings.label_paper.desc_40,
          style: AppTextStyles.bodySm.copyWith(color: AppStyles.gray6),
        ),
        const SizedBox(height: AppSpacing.s8),
        Row(
          children: [
            _buildPaperSizeButton(t.settings.label_paper.btn_40, 40),
            const SizedBox(width: AppSpacing.s8),
            _buildPaperSizeButton(t.settings.label_paper.btn_58, 58),
          ],
        ),
      ],
    );
  }

  Widget _buildPaperSizeButton(String label, int mm) {
    final isSelected = widget.labelPaperSizeMm == mm;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          widget.onLabelPaperSizeChanged(mm);
          logToFile(tag: LogTag.UI_ACTION, message: '라벨 용지 사이즈 변경 -> ${mm}mm');
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

  Widget _buildTestPrintRow() {
    final result = _testResult;
    Color resultColor = AppStyles.gray6;
    if (result != null) {
      if (result.contains('성공')) {
        resultColor = AppStyles.green100;
      } else if (result == '출력 중...') {
        resultColor = AppStyles.gray6;
      } else {
        resultColor = AppStyles.kRed;
      }
    }
    return Row(
      children: [
        ElevatedButton.icon(
          onPressed: _isTesting ? null : _handleTestPrint,
          icon: const Icon(Icons.print, size: 18),
          label: const Text('테스트 출력'),
        ),
        const SizedBox(width: AppSpacing.s12),
        if (result != null)
          Expanded(
            child: Text(
              result,
              style: AppTextStyles.bodySm.copyWith(color: resultColor),
            ),
          ),
      ],
    );
  }
}
