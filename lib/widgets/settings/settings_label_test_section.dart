import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../constants/app_styles.dart';
import '../../models/menu_option_model.dart';
import '../../models/order_menu_model.dart';
import '../../models/order_model.dart';
import '../../providers/providers.dart';
import '../../services/output_queue_service.dart';
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
    required this.labelUseCalibrate,
    required this.labelUseQrPrint,
    required this.onAutoReplyModeChanged,
    required this.onFeedToTearChanged,
    required this.onBackToPrintChanged,
    required this.onCalibrateChanged,
    required this.onUseQrPrintChanged,
  });

  final int labelAutoReplyMode;
  final bool labelUseFeedToTear;
  final bool labelUseBackToPrint;
  final bool labelUseCalibrate;
  final bool labelUseQrPrint;

  final void Function(int) onAutoReplyModeChanged;
  final void Function(bool) onFeedToTearChanged;
  final void Function(bool) onBackToPrintChanged;
  final void Function(bool) onCalibrateChanged;
  final void Function(bool) onUseQrPrintChanged;

  @override
  ConsumerState<SettingsLabelTestSection> createState() =>
      _SettingsLabelTestSectionState();
}

class _SettingsLabelTestSectionState
    extends ConsumerState<SettingsLabelTestSection> {
  bool _isExpanded = false;

  // 부하 테스트 진행 상태
  bool _isStressRunning = false;
  int _stressIteration = 0;
  int _stressTotal = 0;
  Timer? _stressTimer;

  @override
  void dispose() {
    _stressTimer?.cancel();
    super.dispose();
  }

  /// 사고 재현용 부하 테스트.
  /// `mock 2-라인 OrderModel` 을 [iterations] 회 출력. 각 회차당 라벨 2장.
  /// 운영 서버에 영향 없음 (자동접수 흐름을 우회하고 OutputService.printOrderLabels 직접 호출).
  Future<void> _runStressTest(
      {int iterations = 100, int gapSeconds = 8}) async {
    if (_isStressRunning) return;

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

    setState(() {
      _isStressRunning = true;
      _stressIteration = 0;
      _stressTotal = iterations;
    });

    final orderProviderRef = ref.read(orderProvider.notifier);
    final config = 'iter=$iterations gap=${gapSeconds}s'
        ' autoReply=${widget.labelAutoReplyMode}';

    logToFile(
        tag: LogTag.PLATFORM,
        message: '[StressTest] ====== 라벨 부하 테스트 시작 ======');
    logToFile(tag: LogTag.PLATFORM, message: '[StressTest] [CONFIG] $config');

    try {
      for (int i = 1; i <= iterations; i++) {
        if (!mounted || !_isStressRunning) break;
        setState(() => _stressIteration = i);

        final iterSw = Stopwatch()..start();
        final mockOrder = _buildMockOrder(i);

        logToFile(
            tag: LogTag.PLATFORM,
            message:
                '[StressTest] [$i/$iterations] 시작 displayNum=${mockOrder.shopOrderNo} 라인=2');

        // 라벨 2장 직접 출력 (자동접수/큐 우회 — 라벨 프린터 race 만 측정)
        await orderProviderRef.printOrderLabels(mockOrder);

        logToFile(
            tag: LogTag.PLATFORM,
            message:
                '[StressTest] [$i/$iterations] 완료 (${iterSw.elapsedMilliseconds}ms)');

        if (i < iterations) {
          await Future.delayed(Duration(seconds: gapSeconds));
        }
      }
      logToFile(
          tag: LogTag.PLATFORM,
          message:
              '[StressTest] ====== 라벨 부하 테스트 종료 (사용 안된 prinService=$printService) ======');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('부하 테스트 완료 ($iterations회)')),
        );
      }
    } catch (e, s) {
      logToFile(tag: LogTag.ERROR, message: '[StressTest] 실행 오류: $e\n$s');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('부하 테스트 오류: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isStressRunning = false);
      }
    }
  }

  void _stopStressTest() {
    if (!_isStressRunning) return;
    setState(() => _isStressRunning = false);
    logToFile(tag: LogTag.PLATFORM, message: '[StressTest] 사용자 중단 요청');
  }

  /// 2-line mock OrderModel (バニララテ + カフェラテ, qty=1+1) — #958 사고 패턴 재현.
  OrderModel _buildMockOrder(int seq) {
    final now = DateTime.now();
    final orderNo = 'STRESS_${now.millisecondsSinceEpoch}_$seq';
    final displayNo = '9${seq.toString().padLeft(3, '0')}';

    return OrderModel(
      orderNo: orderNo,
      shopOrderNo: displayNo,
      displayOrderNo: displayNo,
      orderStatus: '',
      orderedAt: now,
      totalAmount: 0,
      status: OrderStatus.PREPARING,
      storeId: 'STRESS',
      userId: 'STRESS',
      ordererName: 'STRESS',
      orderCount: '2',
      paymentAmount: 0,
      discountAmount: 0,
      paymentType: 'CARD',
      paymentCode: '',
      menus: [
        OrderMenuModel(
          orderNo: orderNo,
          shopItemId: 'STRESS_A',
          qty: 1,
          itemName: 'バニララテ',
          itemPrice: 0,
          totalAmount: 0,
          discPrc: 0,
          vatPrc: 0,
          options: const <MenuOptionModel>[],
        ),
        OrderMenuModel(
          orderNo: orderNo,
          shopItemId: 'STRESS_B',
          qty: 1,
          itemName: 'カフェラテ',
          itemPrice: 0,
          totalAmount: 0,
          discPrc: 0,
          vatPrc: 0,
          options: const <MenuOptionModel>[],
        ),
      ],
      orderType: 'T',
      kdsOrderType: 1,
      kioskId: '',
      isDetailLoaded: true,
    );
  }

  /// 라벨 재출력 큐 시뮬레이션. 3-라벨 mock 주문 (qty 3) 을 [outputQueueService.addReprint]
  /// 에 그대로 투입 → 실제 주문 상세 팝업의 [라벨 재출력] 버튼과 동일 경로로 흐름.
  Future<void> _simulateLabelReprint() async {
    final messenger = ScaffoldMessenger.of(context);
    final status = ref.read(printerStatusProvider);
    if (!status.isLabelConnected) {
      messenger.showSnackBar(
        const SnackBar(content: Text('라벨 프린터가 연결되어 있지 않습니다.')),
      );
      return;
    }

    final mockOrder = _build3LabelMockOrder();
    logToFile(
        tag: LogTag.UI_ACTION,
        message:
            '[ReprintSim] mock 재출력 큐 투입 displayNum=${mockOrder.shopOrderNo} qty=3');
    ref.read(outputQueueServiceProvider).addReprint(mockOrder);
    messenger.showSnackBar(
      const SnackBar(content: Text('재출력 시뮬 (3장) 큐 투입')),
    );
  }

  /// 단일 메뉴 qty=3 mock 주문. 재출력 시뮬레이션 전용.
  OrderModel _build3LabelMockOrder() {
    final now = DateTime.now();
    final orderNo = 'REPRINT_SIM_${now.millisecondsSinceEpoch}';
    final displayNo =
        '8${(now.millisecondsSinceEpoch % 1000).toString().padLeft(3, '0')}';

    return OrderModel(
      orderNo: orderNo,
      shopOrderNo: displayNo,
      displayOrderNo: displayNo,
      orderStatus: '',
      orderedAt: now,
      totalAmount: 0,
      status: OrderStatus.PREPARING,
      storeId: 'REPRINT_SIM',
      userId: 'REPRINT_SIM',
      ordererName: 'REPRINT_SIM',
      orderCount: '3',
      paymentAmount: 0,
      discountAmount: 0,
      paymentType: 'CARD',
      paymentCode: '',
      menus: [
        OrderMenuModel(
          orderNo: orderNo,
          shopItemId: 'REPRINT_SIM_A',
          qty: 3,
          itemName: '재출력 테스트',
          itemPrice: 0,
          totalAmount: 0,
          discPrc: 0,
          vatPrc: 0,
          options: const <MenuOptionModel>[],
        ),
      ],
      orderType: 'T',
      kdsOrderType: 1,
      kioskId: '',
      isDetailLoaded: true,
    );
  }

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
        ' calibrate=${widget.labelUseCalibrate}';

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
                    description: '양방향 통신 (1=ACK 기반, 권장 기본값)',
                    child: DropdownButton<int>(
                      value: widget.labelAutoReplyMode,
                      items: const [
                        DropdownMenuItem(value: 0, child: Text('0 (비활성)')),
                        DropdownMenuItem(value: 1, child: Text('1 (ACK 기반)')),
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
                    label: '캘리브레이션',
                    description: '연결 시 갭 센서 보정',
                    child: _switch(
                      widget.labelUseCalibrate,
                      widget.onCalibrateChanged,
                    ),
                  ),
                  const Divider(height: 1),
                  _buildRow(
                    label: 'QR 코드 출력',
                    description: 'QR 페이로드 완성 전까지 기본 OFF',
                    child: _switch(
                      widget.labelUseQrPrint,
                      widget.onUseQrPrintChanged,
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
                  const SizedBox(height: AppSpacing.s12),
                  Center(
                    child: ElevatedButton.icon(
                      onPressed: _isStressRunning
                          ? _stopStressTest
                          : () => _runStressTest(),
                      icon: Icon(_isStressRunning ? Icons.stop : Icons.repeat,
                          size: 18),
                      label: Text(_isStressRunning
                          ? '중단 ($_stressIteration/$_stressTotal)'
                          : '부하 테스트 (100회 × 2장)'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            _isStressRunning ? Colors.redAccent : Colors.indigo,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.s24,
                          vertical: AppSpacing.s12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s12),
                  Center(
                    child: ElevatedButton.icon(
                      onPressed: _simulateLabelReprint,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('재출력 시뮬레이션 (qty=3 mock — 큐 경유)'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueGrey.shade700,
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
