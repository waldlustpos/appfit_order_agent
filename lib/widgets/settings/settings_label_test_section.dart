import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../constants/app_styles.dart';
import '../../providers/providers.dart';
import '../../services/platform_service.dart';
import '../../services/print_service.dart';
import '../../utils/print/label_painter.dart';
import '../../widgets/custom_switch.dart';

/// 라벨 프린터 고급 설정 (개발자 옵션 내부).
///
/// 확장/축소 상태를 자체 관리하며, 설정 값은 부모로부터 전달받는다.
class SettingsLabelTestSection extends ConsumerStatefulWidget {
  const SettingsLabelTestSection({
    super.key,
    required this.labelAutoReplyMode,
    required this.labelUseFeedToTear,
    required this.labelUseBackToPrint,
    required this.labelUseStatusPolling,
    required this.labelUseCalibrate,
    required this.labelPrintDelay,
    required this.onAutoReplyModeChanged,
    required this.onFeedToTearChanged,
    required this.onBackToPrintChanged,
    required this.onStatusPollingChanged,
    required this.onCalibrateChanged,
    required this.onPrintDelayChanged,
  });

  final int labelAutoReplyMode;
  final bool labelUseFeedToTear;
  final bool labelUseBackToPrint;
  final bool labelUseStatusPolling;
  final bool labelUseCalibrate;
  final int labelPrintDelay;

  final void Function(int) onAutoReplyModeChanged;
  final void Function(bool) onFeedToTearChanged;
  final void Function(bool) onBackToPrintChanged;
  final void Function(bool) onStatusPollingChanged;
  final void Function(bool) onCalibrateChanged;
  final void Function(int) onPrintDelayChanged;

  @override
  ConsumerState<SettingsLabelTestSection> createState() =>
      _SettingsLabelTestSectionState();
}

class _SettingsLabelTestSectionState
    extends ConsumerState<SettingsLabelTestSection> {
  bool _isExpanded = false;

  Future<void> _printLabelTest() async {
    final printService = ref.read(printServiceProvider);
    final status = ref.read(printerStatusProvider);

    if (!status.isLabelConnected) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('라벨 프린터가 연결되어 있지 않습니다.')),
        );
      }
      return;
    }

    final config = 'autoReply=${widget.labelAutoReplyMode}'
        ' feedToTear=${widget.labelUseFeedToTear}'
        ' backToPrint=${widget.labelUseBackToPrint}'
        ' polling=${widget.labelUseStatusPolling}'
        ' calibrate=${widget.labelUseCalibrate}'
        ' delay=${widget.labelPrintDelay}ms';

    logToFile(
        tag: LogTag.PLATFORM,
        message: '[LabelTest] ====== 테스트 출력 시작 (3장) ======');
    logToFile(tag: LogTag.PLATFORM, message: '[LabelTest] [CONFIG] $config');

    try {
      final sw = Stopwatch()..start();
      for (int i = 1; i <= 3; i++) {
        final labelSw = Stopwatch()..start();
        final imageBytes = await LabelPainter.generateLabelImage(
          menuName: '테스트 상품 $i',
          options: ['옵션A', '옵션B'],
          shopOrderNo: '0000',
          orderTime: '03/26\n12:00:00',
          orderIndex: i,
          orderTotal: 3,
        );
        logToFile(
            tag: LogTag.PLATFORM,
            message:
                '[LabelTest] [$i/3] printLabel 호출 (${imageBytes.length} bytes)...');
        await printService.printLabel(imageBytes);
        logToFile(
            tag: LogTag.PLATFORM,
            message:
                '[LabelTest] [$i/3] printLabel 완료 (${labelSw.elapsedMilliseconds}ms)');
        if (i < 3) {
          logToFile(
              tag: LogTag.PLATFORM,
              message:
                  '[LabelTest] [$i/3] 다음 장 대기 ${widget.labelPrintDelay}ms...');
          await Future.delayed(Duration(milliseconds: widget.labelPrintDelay));
        }
      }
      sw.stop();
      logToFile(
          tag: LogTag.PLATFORM,
          message:
              '[LabelTest] ====== 테스트 출력 완료 (총 ${sw.elapsedMilliseconds}ms) ======');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('테스트 라벨 3장 출력 완료 (${sw.elapsedMilliseconds}ms)')),
        );
      }
    } catch (e) {
      logToFile(tag: LogTag.ERROR, message: '[LabelTest] 테스트 라벨 출력 실패: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('테스트 출력 실패: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s8),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: _isExpanded,
          onExpansionChanged: (v) => setState(() => _isExpanded = v),
          tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.s8),
          title: Text(
            '라벨프린터 고급 설정 (테스트)',
            style: AppTextStyles.bodySm.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.deepOrange,
            ),
          ),
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s16,
                vertical: AppSpacing.s8,
              ),
              decoration: const BoxDecoration(
                color: AppStyles.gray1,
                borderRadius: AppRadius.bSm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildRow(
                    label: 'AutoReply 모드',
                    description: '양방향 통신 (0=비활성, 1=활성)',
                    child: DropdownButton<int>(
                      value: widget.labelAutoReplyMode,
                      items: const [
                        DropdownMenuItem(value: 0, child: Text('0 (비활성)')),
                        DropdownMenuItem(value: 1, child: Text('1 (활성)')),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        widget.onAutoReplyModeChanged(v);
                      },
                    ),
                  ),
                  const Divider(height: 1),
                  _buildRow(
                    label: '뜯기 위치 이동',
                    description: 'FeedPaperToTearPosition',
                    child: _switch(
                      widget.labelUseFeedToTear,
                      widget.onFeedToTearChanged,
                    ),
                  ),
                  const Divider(height: 1),
                  _buildRow(
                    label: '인쇄 위치 복귀',
                    description: 'BackPaperToPrintPosition',
                    child: _switch(
                      widget.labelUseBackToPrint,
                      widget.onBackToPrintChanged,
                    ),
                  ),
                  const Divider(height: 1),
                  _buildRow(
                    label: '상태 폴링',
                    description: '인쇄 완료 확인 후 다음 장',
                    child: _switch(
                      widget.labelUseStatusPolling,
                      widget.onStatusPollingChanged,
                    ),
                  ),
                  const Divider(height: 1),
                  _buildRow(
                    label: '캘리브레이션',
                    description: '연결 시 갭 센서 보정',
                    child: _switch(
                      widget.labelUseCalibrate,
                      widget.onCalibrateChanged,
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: AppSpacing.s8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '출력 간 딜레이',
                                    style: AppTextStyles.bodySm.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: AppStyles.gray9,
                                    ),
                                  ),
                                  Text(
                                    '라벨 간 대기 시간 (ms)',
                                    style: AppTextStyles.caption.copyWith(
                                      color: AppStyles.gray6,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '${widget.labelPrintDelay}ms',
                              style: AppTextStyles.body.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Colors.deepOrange,
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: widget.labelPrintDelay.toDouble(),
                          min: 300,
                          max: 10000,
                          divisions: 97,
                          activeColor: Colors.deepOrange,
                          label: '${widget.labelPrintDelay}ms',
                          onChanged: (v) =>
                              widget.onPrintDelayChanged(v.round()),
                          onChangeEnd: (_) {},
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s12),
                  Center(
                    child: ElevatedButton.icon(
                      onPressed: _printLabelTest,
                      icon: const Icon(Icons.print, size: 18),
                      label: const Text('테스트 출력 (3장)'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepOrange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.s24,
                          vertical: AppSpacing.s12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow({
    required String label,
    required String description,
    required Widget child,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTextStyles.bodySm.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppStyles.gray9,
                  ),
                ),
                Text(
                  description,
                  style: AppTextStyles.caption.copyWith(
                    color: AppStyles.gray6,
                  ),
                ),
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }

  Widget _switch(bool value, void Function(bool) onChanged) => CustomSwitch(
        value: value,
        activeColor: AppStyles.kMainColor,
        inactiveColor: AppStyles.gray4,
        activeText: 'ON',
        inactiveText: 'OFF',
        onChanged: onChanged,
      );
}
