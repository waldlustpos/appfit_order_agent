import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:appfit_order_agent/constants/app_styles.dart';
import 'package:appfit_order_agent/providers/providers.dart';
import 'package:appfit_order_agent/services/platform_service.dart';
import 'package:appfit_order_agent/i18n/strings.g.dart';

/// "내장 프린터 사용" 토글의 additionalContent.
///
/// 내장 프린터는 Sunmi 단말 + 내장 모듈 존재 시에만 의미가 있으므로 별도 연결 상태
/// 영역이나 재연결 버튼 없이 (1) 감지 결과 안내 텍스트 + (2) 테스트 출력 버튼만 제공.
class BuiltinPrinterSubSettings extends ConsumerStatefulWidget {
  const BuiltinPrinterSubSettings({
    super.key,
    required this.isUseBuiltinPrinter,
    required this.available,
    required this.printOrder,
    required this.printReceipt,
    required this.printCall,
    required this.onPrintOrderChanged,
    required this.onPrintReceiptChanged,
    required this.onPrintCallChanged,
  });

  /// 내장 프린터 토글 ON 여부 (PreferenceService 값과 동일).
  final bool isUseBuiltinPrinter;

  /// 내장 하드웨어 감지 결과. false 면 토글이 disable 되어 있고 테스트도 불가.
  final bool available;

  /// 매트릭스: 주문서 출력 여부.
  final bool printOrder;

  /// 매트릭스: 영수증 출력 여부.
  final bool printReceipt;

  /// 매트릭스: 기기 호출 알림 출력 여부.
  final bool printCall;

  final void Function(bool) onPrintOrderChanged;
  final void Function(bool) onPrintReceiptChanged;
  final void Function(bool) onPrintCallChanged;

  @override
  ConsumerState<BuiltinPrinterSubSettings> createState() =>
      _BuiltinPrinterSubSettingsState();
}

class _BuiltinPrinterSubSettingsState
    extends ConsumerState<BuiltinPrinterSubSettings> {
  bool _isTesting = false;
  String? _testResult;

  Future<void> _handleTestPrint() async {
    if (_isTesting) return;
    setState(() {
      _isTesting = true;
      _testResult = '출력 중...';
    });
    logToFile(
      tag: LogTag.UI_ACTION,
      message: '내장 프린터 테스트 출력 시도',
    );
    bool ok = false;
    try {
      ok = await ref
          .read(printServiceProvider)
          .printTestPage(targetBuiltinOnly: true);
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDetectionStatus(),
        if (widget.available) ...[
          const SizedBox(height: AppSpacing.s12),
          _buildMatrixRow(
            label: '주문서 출력',
            value: widget.printOrder,
            onChanged: (v) {
              ref
                  .read(printServiceProvider)
                  .updatePrinterSettings(builtinPrintOrder: v);
              widget.onPrintOrderChanged(v);
            },
          ),
          const SizedBox(height: AppSpacing.s8),
          _buildMatrixRow(
            label: '영수증 출력',
            value: widget.printReceipt,
            onChanged: (v) {
              ref
                  .read(printServiceProvider)
                  .updatePrinterSettings(builtinPrintReceipt: v);
              widget.onPrintReceiptChanged(v);
            },
          ),
          const SizedBox(height: AppSpacing.s8),
          _buildMatrixRow(
            label: '기기 호출 알림 출력',
            value: widget.printCall,
            onChanged: (v) {
              ref
                  .read(printServiceProvider)
                  .updatePrinterSettings(builtinPrintCall: v);
              widget.onPrintCallChanged(v);
            },
          ),
          const SizedBox(height: AppSpacing.s12),
          _buildTestPrintRow(),
        ],
      ],
    );
  }

  Widget _buildMatrixRow({
    required String label,
    required bool value,
    required void Function(bool) onChanged,
  }) {
    final enabled = widget.available && widget.isUseBuiltinPrinter;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: AppTextStyles.bodySm.copyWith(
              color: enabled ? AppStyles.gray9 : AppStyles.gray4,
            ),
          ),
        ),
        Switch(
          value: value,
          onChanged: enabled ? onChanged : null,
          activeColor: AppStyles.kMainColor,
        ),
      ],
    );
  }

  Widget _buildDetectionStatus() {
    final detected = widget.available;
    final color = detected ? AppStyles.green100 : AppStyles.gray6;
    final msg = detected
        ? t.settings.builtin_printer.detected
        : t.settings.builtin_printer.not_detected;
    return Row(
      children: [
        Icon(
          detected ? Icons.check_circle_outline : Icons.info_outline,
          size: 18,
          color: color,
        ),
        const SizedBox(width: AppSpacing.s8),
        Expanded(
          child: Text(
            msg,
            style: AppTextStyles.bodySm.copyWith(color: color),
          ),
        ),
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
    final canPress =
        widget.available && widget.isUseBuiltinPrinter && !_isTesting;
    return Row(
      children: [
        ElevatedButton.icon(
          onPressed: canPress ? _handleTestPrint : null,
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
