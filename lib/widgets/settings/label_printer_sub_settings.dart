import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../constants/app_styles.dart';
import '../../providers/providers.dart';
import '../../services/platform_service.dart';
import '../../services/print_service.dart';
import 'settings_connection_status.dart';

/// "라벨 프린터 사용" 토글의 additionalContent.
///
/// 외부 영수증 프린터와 동일한 패턴: 연결상태 + 재연결 버튼 + 테스트 출력 버튼.
/// 재연결 버튼은 [PrintService.checkConnection] 을 `label: true, external: false`
/// 로 호출하여 외부 프린터 status 와 동시에 토글되는 sync 이슈를 회피.
class LabelPrinterSubSettings extends ConsumerStatefulWidget {
  const LabelPrinterSubSettings({
    super.key,
    required this.isUseLabelPrinter,
  });

  final bool isUseLabelPrinter;

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
          onReconnect: () => ref
              .read(printServiceProvider)
              .checkConnection(external: false, label: true),
        ),
        if (widget.isUseLabelPrinter) ...[
          const SizedBox(height: AppSpacing.s12),
          _buildTestPrintRow(),
        ],
      ],
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
