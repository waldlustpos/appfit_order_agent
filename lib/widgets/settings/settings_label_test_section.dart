import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:appfit_order_agent/constants/app_styles.dart';
import 'package:appfit_order_agent/constants/order_constants.dart';
import 'package:appfit_order_agent/models/menu_option_model.dart';
import 'package:appfit_order_agent/models/order_menu_model.dart';
import 'package:appfit_order_agent/models/order_model.dart';
import 'package:appfit_order_agent/models/product_model.dart';
import 'package:appfit_order_agent/providers/product_provider.dart';
import 'package:appfit_order_agent/providers/providers.dart';
import 'package:appfit_order_agent/services/output_queue_service.dart';
import 'package:appfit_order_agent/services/platform_service.dart';
import 'package:appfit_order_agent/services/print_service.dart';
import 'package:appfit_order_agent/utils/label_painter.dart';
import 'package:appfit_order_agent/widgets/custom_switch.dart';

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
    required this.onAutoReplyModeChanged,
    required this.onFeedToTearChanged,
    required this.onBackToPrintChanged,
    required this.onCalibrateChanged,
  });

  final int labelAutoReplyMode;
  final bool labelUseFeedToTear;
  final bool labelUseBackToPrint;
  final bool labelUseCalibrate;

  final void Function(int) onAutoReplyModeChanged;
  final void Function(bool) onFeedToTearChanged;
  final void Function(bool) onBackToPrintChanged;
  final void Function(bool) onCalibrateChanged;

  @override
  ConsumerState<SettingsLabelTestSection> createState() =>
      _SettingsLabelTestSectionState();
}

class _SettingsLabelTestSectionState
    extends ConsumerState<SettingsLabelTestSection> {
  bool _isExpanded = false;

  // ── 주문번호 라벨 테스트 데이터 ──────────────────────────────────────
  /// QA 용 고정 주문번호 1개. 뒤에 -1~-20 숫자 접미사를 붙여 20장 출력(QR 없음).
  static const List<String> _orderNoTestNumbers = [
    '1023',
  ];

  /// 주문번호당 출력 매수. 주문번호 뒤에 -1, -2 ... -20 숫자 접미사를 붙여 20장 출력.
  static const int _orderNoTestVersions = 20;

  /// 임의 메모 풀 (라벨마다 순환). "detail 부분 임의로 작성" — 일본어, null 은 메모 없는 케이스.
  static const List<String?> _orderNoTestMemoPool = [
    '早めにお願いします',
    'カップホルダーは不要です',
    '氷少なめ',
    null,
    '熱めでお願いします',
  ];

  /// 보유 상품이 하나도 없을 때만 쓰는 fallback 메뉴명. 실제 상품명은 번역하지 않고
  /// productProvider 값을 그대로 쓰며, fallback 도 임의 번역 없이 영문 그대로 둔다.
  static const List<String> _orderNoTestFallbackMenus = [
    'Americano',
    'Caffe Latte',
    'Cappuccino',
  ];

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

  /// 지정 주문번호 1개를 실제 보유 상품명 + 임의 옵션/메모로 -1~-20 숫자 접미사로 20장 출력 (QR 없음).
  /// 20장은 내용은 동일하고 주문번호 뒤에 -1, -2, ... -20 숫자 접미사만 달라진다
  /// (예: #1023-1, #1023-2, ... #1023-20).
  ///
  /// 자동출력 경로([OutputService.printOrderLabels])와 달리
  /// [LabelPrintData.fromOrder] / 브랜드 필터 전략을 거치지 않고
  /// [LabelPainter.generateLabelImage] 를 직접 호출한다 → 임의 옵션/메모가
  /// 그대로 인쇄되고, qrData 를 넘기지 않으므로 QR 토글과 무관하게 QR 미인쇄.
  Future<void> _printOrderNoTest() async {
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

    // 실제 보유 상품에서 메뉴명 + subinfo(원두/온도/사이즈) 추출.
    // 메뉴명은 type==item 상품명을 그대로 사용(번역 안 함). subinfo 는 옵션(type==option)을
    // TpcpLabelFilterStrategy 와 동일하게 categoryCode 로 분류해서 채운다.
    List<String> menuNames = const [];
    List<String> beanNames = const [];
    List<String> tempNames = const [];
    List<String> sizeNames = const [];
    List<String> etcOptionNames = const [];
    try {
      final products = await ref.read(productProvider.future);
      menuNames = products
          .where((p) => p.type == ProductType.item)
          .map((p) => p.productName)
          .where((n) => n.isNotEmpty)
          .toList();

      final optionProducts =
          products.where((p) => p.type == ProductType.option).toList();
      List<String> byCodes(Set<String> codes) => optionProducts
          .where((p) => codes.contains(p.categoryCode))
          .map((p) => p.productName)
          .where((n) => n.isNotEmpty)
          .toList();
      // subinfo: 원두/온도/사이즈 카테고리 옵션 (TpcpLabelFilterStrategy 동일 기준).
      beanNames = byCodes(OrderCategoryCodes.beanTypeCodes);
      tempNames = byCodes(OrderCategoryCodes.temperatureCodes);
      sizeNames = byCodes(OrderCategoryCodes.sizeOptionCodes);

      // option 섹션: subinfo 로 분류되지 않은 나머지 옵션
      // (실제 라벨의 remainingOptions 와 동일하게 원두/온도/사이즈는 제외).
      final subinfoCodes = <String>{
        ...OrderCategoryCodes.beanTypeCodes,
        ...OrderCategoryCodes.temperatureCodes,
        ...OrderCategoryCodes.sizeOptionCodes,
      };
      etcOptionNames = optionProducts
          .where((p) => !subinfoCodes.contains(p.categoryCode))
          .map((p) => p.productName)
          .where((n) => n.isNotEmpty)
          .toList();
    } catch (e) {
      logToFile(
          tag: LogTag.WARNING,
          message: '[OrderNoTest] 상품 조회 실패 — fallback 사용: $e');
    }
    if (menuNames.isEmpty) menuNames = _orderNoTestFallbackMenus;

    logToFile(
        tag: LogTag.PLATFORM,
        message: '[OrderNoTest] 후보 bean=${beanNames.length}'
            ' temp=${tempNames.length} size=${sizeNames.length}'
            ' option=${etcOptionNames.length}');

    const numbers = _orderNoTestNumbers;
    final total = numbers.length * _orderNoTestVersions; // 번호 × 20(-1~-20)
    final orderTime = DateFormat('MM/dd\nHH:mm:ss').format(DateTime.now());

    logToFile(
        tag: LogTag.PLATFORM,
        message: '[OrderNoTest] ====== 주문번호 테스트 출력 시작 ($total장) ======');

    int ok = 0;
    int printed = 0;
    try {
      for (int i = 0; i < numbers.length; i++) {
        final shopOrderNo = numbers[i];
        final menuName = menuNames[i % menuNames.length];
        // option 섹션: 실제 옵션(원두/온도/사이즈 제외)에서 번호마다 1~3개 순환.
        final optMax = etcOptionNames.length < 3 ? etcOptionNames.length : 3;
        final optCount = optMax == 0 ? 0 : (i % optMax) + 1;
        final options = [
          for (var k = 0; k < optCount; k++)
            etcOptionNames[(i + k) % etcOptionNames.length]
        ];
        final memo = _orderNoTestMemoPool[i % _orderNoTestMemoPool.length];
        // subinfo 는 실제 옵션에서 분류한 후보를 순환 사용 (없으면 null → 영역 비움).
        final bean = beanNames.isEmpty ? null : beanNames[i % beanNames.length];
        final temp = tempNames.isEmpty ? null : tempNames[i % tempNames.length];
        final size = sizeNames.isEmpty ? null : sizeNames[i % sizeNames.length];

        // 같은 주문번호로 20장 — 내용 동일, 주문번호 뒤 숫자 접미사(-1~-20)만 다름.
        for (int v = 1; v <= _orderNoTestVersions; v++) {
          printed++;
          // 주문번호 접미사: -1, -2, ... -20.
          final labelOrderNo = '$shopOrderNo-$v'; // 예: 1023-1
          final imageBytes = await LabelPainter.generateLabelImage(
            menuName: menuName,
            options: options,
            shopOrderNo: labelOrderNo,
            orderTime: orderTime,
            beanType: bean,
            temperature: temp,
            sizeOption: size,
            memo: memo,
            // 헤더 식별번호: (1/20), (2/20) ... (20/20) — 현재 장수/전체 장수.
            orderIndex: v,
            orderTotal: _orderNoTestVersions,
            // 이 테스트는 로캘과 무관하게 섹션 타이틀을 영문 고정.
            optionTitleOverride: 'option',
            detailTitleOverride: 'detail',
          );
          final result = await printService.printLabel(
            imageBytes,
            orderNo: labelOrderNo,
            labelIndex: printed,
            totalLabels: total,
          );
          if (result) ok++;
          logToFile(
              tag: result ? LogTag.PLATFORM : LogTag.WARNING,
              message: '[OrderNoTest] $printed/$total no=$labelOrderNo'
                  ' menu="$menuName" ${result ? "출력끝" : "실패"}');
        }
      }
      logToFile(
          tag: LogTag.PLATFORM,
          message: '[OrderNoTest] ====== 주문번호 테스트 출력 종료 ($ok/$total) ======');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('주문번호 테스트 $ok/$total 출력')),
        );
      }
    } catch (e) {
      logToFile(tag: LogTag.ERROR, message: '[OrderNoTest] 출력 실패: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('주문번호 테스트 출력 실패: $e')),
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
                  const SizedBox(height: AppSpacing.s12),
                  Center(
                    child: ElevatedButton.icon(
                      onPressed: _printOrderNoTest,
                      icon: const Icon(Icons.confirmation_number, size: 18),
                      label: const Text(
                          '주문번호 테스트 (1번호 × -1~-20 = 20장 / 실상품·옵션·메모)'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
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
