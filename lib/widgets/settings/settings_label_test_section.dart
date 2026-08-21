import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:qr/qr.dart';
import 'package:appfit_order_agent/constants/app_styles.dart';
import 'package:appfit_order_agent/models/menu_option_model.dart';
import 'package:appfit_order_agent/models/order_menu_model.dart';
import 'package:appfit_order_agent/models/order_model.dart';
import 'package:appfit_order_agent/models/product_model.dart';
import 'package:appfit_order_agent/providers/product_provider.dart';
import 'package:appfit_order_agent/providers/providers.dart';
import 'package:appfit_order_agent/services/label_printer/label_print_data.dart';
import 'package:appfit_order_agent/services/label_printer/qr_payload_strategy.dart';
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

  /// 한 주문이 20잔(-1~-20)이라는 전제는 유지하되, 종이 절약을 위해 실제 출력은
  /// 아래 접미사들만 5장 뽑는다. 두 자리 접미사 렌더링 케이스 확인용으로 -20 은 반드시 포함.
  static const int _orderNoTestVersions = 20;

  /// 실제로 출력할 접미사 목록 (총 5장). -20 두 자리 케이스 포함.
  static const List<int> _orderNoTestPrintVersions = [1, 5, 10, 15, 20];

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

  /// 라벨 sub-info(원두/온도/사이즈) 미리보기용 고정 샘플.
  ///
  /// 실제 라벨은 주문 응답의 `optionGroupPosId` 로 분류하지만(v1), 이 테스트는
  /// 주문이 아닌 상품 카탈로그 기반이라 같은 소스를 쓸 수 없다. 레이아웃·정렬
  /// 검증이 목적이므로 서버 응답과 무관하게 항상 채워지는 고정값을 쓴다.
  static const List<String> _orderNoTestSampleBeans = ['다크', '산미'];
  static const List<String> _orderNoTestSampleTemps = ['HOT', 'ICED'];
  static const List<String> _orderNoTestSampleSizes = ['R', 'L'];

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
      const int layoutVersion = 1; // 라벨 레이아웃 V2 고정 (선택 설정 폐지)
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
          layoutVersion: layoutVersion,
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

  /// 지정 주문번호 1개를 실제 보유 상품명 + 임의 옵션/메모로 -1~-20 숫자 접미사로 20장 출력.
  /// 20장은 내용은 동일하고 주문번호 뒤에 -1, -2, ... -20 숫자 접미사만 달라진다
  /// (예: 1023-1, 1023-2, ... 1023-20 — '#' 없음).
  ///
  /// 자동출력 경로([OutputService.printOrderLabels])와 달리
  /// [LabelPrintData.fromOrder] / 브랜드 필터 전략을 거치지 않고
  /// [LabelPainter.generateLabelImage] 를 직접 호출한다 → 임의 옵션/메모가
  /// 그대로 인쇄된다. QR 토글(getLabelUseQrPrint)을 반영해 ON 이면 QR 도 함께 출력하며,
  /// QR 페이로드는 운영과 동일한 [DisplayNumIndexQrPayloadStrategy] 포맷을
  /// 담는다 → 실제 스캔/레이아웃을 동일하게 검증.
  Future<void> _printOrderNoTest() async {
    final printService = ref.read(printServiceProvider);
    final status = ref.read(printerStatusProvider);
    // QR 토글 반영 — ON 이면 각 라벨에 운영과 동일 포맷의 QR 페이로드를 넘긴다.
    final useQr = ref.read(preferenceServiceProvider).getLabelUseQrPrint();
    const int layoutVersion = 1; // 라벨 레이아웃 V2 고정 (선택 설정 폐지)
    const qrStrategy = DisplayNumIndexQrPayloadStrategy();

    if (!status.isLabelConnected) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('라벨 프린터가 연결되어 있지 않습니다.')),
        );
      }
      return;
    }

    // 실제 보유 상품에서 메뉴명 + option 섹션을 채운다.
    // 메뉴명은 type==item 상품명을 그대로 사용(번역 안 함).
    //
    // subinfo(원두/온도/사이즈)는 **고정 샘플**을 쓴다. 실제 라벨에서는 주문 응답의
    // optionGroupPosId 로 분류하는데(TpcpLabelFilterStrategy), 이 테스트는 주문이
    // 아닌 상품 카탈로그 기반이라 대체 소스가 없다. 이 화면의 목적은 라벨 레이아웃·
    // 정렬 검증이므로 서버 응답과 무관하게 항상 채워지는 편이 낫다.
    List<String> menuNames = const [];
    List<String> menuIds =
        const []; // 메뉴별 shopItemId(internalId) — QR 페이로드용 (menuNames 와 동일 순서)
    const beanNames = _orderNoTestSampleBeans;
    const tempNames = _orderNoTestSampleTemps;
    const sizeNames = _orderNoTestSampleSizes;
    List<String> etcOptionNames = const [];
    try {
      final products = await ref.read(productProvider.future);
      final itemProducts = products
          .where((p) => p.type == ProductType.item && p.productName.isNotEmpty)
          .toList();
      menuNames = itemProducts.map((p) => p.productName).toList();
      menuIds = itemProducts.map((p) => p.internalId).toList();

      // option 섹션: 실제 보유 옵션 상품명 (subinfo 는 위 고정 샘플이라 제외 불필요).
      etcOptionNames = products
          .where((p) => p.type == ProductType.option)
          .map((p) => p.productName)
          .where((n) => n.isNotEmpty)
          .toList();
    } catch (e) {
      logToFile(
          tag: LogTag.WARNING,
          message: '[OrderNoTest] 상품 조회 실패 — fallback 사용: $e');
    }
    if (menuNames.isEmpty) {
      menuNames = _orderNoTestFallbackMenus;
      menuIds = const ['ITEM1', 'ITEM2', 'ITEM3'];
    }

    logToFile(
        tag: LogTag.PLATFORM,
        message: '[OrderNoTest] 후보 bean=${beanNames.length}'
            ' temp=${tempNames.length} size=${sizeNames.length}'
            ' option=${etcOptionNames.length}');

    const numbers = _orderNoTestNumbers;
    final total = numbers.length * _orderNoTestPrintVersions.length; // 번호 × 5장
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
        final shopItemId =
            menuIds.isEmpty ? 'ITEM' : menuIds[i % menuIds.length];
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

        // 같은 주문번호로 5장 — 내용 동일, 주문번호 뒤 숫자 접미사(-1,-5,-10,-15,-20)만 다름.
        for (final v in _orderNoTestPrintVersions) {
          printed++;
          // 주문번호 접미사: -1, -2, ... -20.
          final labelOrderNo = '$shopOrderNo-$v'; // 예: 1023-1
          // QR 페이로드: 운영과 동일 전략 → {OrderNo}-{ShopItemId}-{CupIdx}.
          // cupIdx = labelSeq-1 이므로 labelSeq=v → '$shopOrderNo-$shopItemId-${v-1}'.
          final qrPayload = qrStrategy.buildPayload(
            LabelOrderInfo(
              orderNo: shopOrderNo,
              displayNum: labelOrderNo,
              shopOrderNo: shopOrderNo,
              storeId: 'ORDERNO_TEST',
              orderedAt: DateTime.now(),
            ),
            LabelMenuInfo(
              shopItemId: shopItemId,
              itemName: menuName,
              itemPrice: 0,
              qty: _orderNoTestVersions,
              labelSeq: v,
              options: const [],
            ),
            printed,
            total,
          );
          final imageBytes = await LabelPainter.generateLabelImage(
            menuName: menuName,
            options: options,
            shopOrderNo: labelOrderNo,
            orderTime: orderTime,
            beanType: bean,
            temperature: temp,
            sizeOption: size,
            // QR 토글 ON 이면 운영과 동일 포맷의 QR 동반 출력.
            qrData: useQr ? qrPayload : null,
            memo: memo,
            // 헤더 식별번호: (1/20), (2/20) ... (20/20) — 현재 장수/전체 장수.
            orderIndex: v,
            orderTotal: _orderNoTestVersions,
            layoutVersion: layoutVersion,
            // V1/V2 실주문과 동일한 QR 크기·오류정정 정책을 그대로 적용.
            qrSize: LabelPainter.qrSizeForLayout(layoutVersion),
            qrErrorCorrectLevel:
                LabelPainter.qrErrorCorrectLevelForLayout(layoutVersion),
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

  /// QR 오류 정정 레벨 4종 (qr 패키지 상수 + 복원율 라벨). 셀렉터 + 라벨 표기 공용.
  static const List<({int level, String name, String recover})> _qrLevels = [
    (level: QrErrorCorrectLevel.L, name: 'L', recover: '7%'),
    (level: QrErrorCorrectLevel.M, name: 'M', recover: '15%'),
    (level: QrErrorCorrectLevel.Q, name: 'Q', recover: '25%'),
    (level: QrErrorCorrectLevel.H, name: 'H', recover: '30%'),
  ];

  /// 페이로드 후보 (id=ShopItemId, payload=운영 포맷 {OrderNo}-{ShopItemId}-{CupIdx}).
  static const List<({String id, String payload})> _qrPayloads = [
    (id: '0qgjxz2beb08w', payload: '857511257333139-0qgjxz2beb08w-0'),
    (id: 'TKP0021', payload: '857511257333139-TKP0021-0'),
    (id: '숫자만', payload: '857511257333139'),
  ];

  /// QR 크기 단계: 현재(qrSizeDefault) 기준 0% / +20% / +50%, 총 3단계.
  /// V2 헤더 축소와 함께 큰 QR(최대 +50%) 수용 가능 여부를 검증한다.
  static const List<double> _qrSizeSteps = [0.0, 0.20, 0.50];

  // ── QR 테스트 선택 상태 ─────────────────────────────────────────────
  String _qrTestPayload = _qrPayloads.first.payload;
  int _qrTestLevel = QrErrorCorrectLevel.M;
  int _qrTestSizeStep = 0; // _qrSizeSteps 인덱스

  double get _qrTestSize =>
      LabelPainter.qrSizeDefault * (1 + _qrSizeSteps[_qrTestSizeStep]);

  String get _qrTestLevelName =>
      _qrLevels.firstWhere((l) => l.level == _qrTestLevel).name;

  /// 선택한 페이로드/레벨/크기 조합으로 라벨 1장 출력.
  /// detail(memo)·헤더에 조합을 박아 인쇄물에서 어떤 설정인지 육안 식별 가능하게 한다.
  Future<void> _printQrSelectedTest() async {
    final printService = ref.read(printServiceProvider);
    final status = ref.read(printerStatusProvider);
    const int layoutVersion = 1; // 라벨 레이아웃 V2 고정 (선택 설정 폐지)

    if (!status.isLabelConnected) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('라벨 프린터가 연결되어 있지 않습니다.')),
        );
      }
      return;
    }

    // 실제 데이터처럼 — 보유 상품에서 메뉴명을 뽑아 표시한다. 조회 실패 시 fallback.
    String menuName = _orderNoTestFallbackMenus.first;
    try {
      final products = await ref.read(productProvider.future);
      final item = products.firstWhere(
        (p) => p.type == ProductType.item && p.productName.isNotEmpty,
        orElse: () => throw StateError('no item'),
      );
      menuName = item.productName;
    } catch (e) {
      logToFile(
          tag: LogTag.WARNING,
          message: '[QrSelTest] 상품 조회 실패 — fallback 사용: $e');
    }

    const shopOrderNo = '1023';
    final orderTime = DateFormat('MM/dd\nHH:mm:ss').format(DateTime.now());

    final qrPayload = _qrTestPayload;
    final levelName = _qrTestLevelName;
    final qrSize = _qrTestSize;
    final sizePct = (_qrSizeSteps[_qrTestSizeStep] * 100).round();
    final config = 'level=$levelName size=${qrSize.toStringAsFixed(0)}'
        '(+$sizePct%) payload="$qrPayload"';

    logToFile(
        tag: LogTag.PLATFORM,
        message: '[QrSelTest] ====== QR 선택 테스트 출력 (1장) ====== $config');

    try {
      final imageBytes = await LabelPainter.generateLabelImage(
        menuName: menuName,
        options: const [],
        shopOrderNo: shopOrderNo,
        orderTime: orderTime,
        qrData: qrPayload,
        memo: 'QR $levelName / ${qrSize.toStringAsFixed(0)}px (+$sizePct%)',
        layoutVersion: layoutVersion,
        qrErrorCorrectLevel: _qrTestLevel,
        qrSize: qrSize,
        optionTitleOverride: 'option',
        detailTitleOverride: 'detail',
      );
      final result = await printService.printLabel(
        imageBytes,
        orderNo: '$shopOrderNo-$levelName',
        labelIndex: 1,
        totalLabels: 1,
      );
      logToFile(
          tag: result ? LogTag.PLATFORM : LogTag.WARNING,
          message: '[QrSelTest] ${result ? "출력끝" : "실패"} $config');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(result
                  ? 'QR 테스트 출력 ($levelName / +$sizePct%)'
                  : 'QR 테스트 출력 실패')),
        );
      }
    } catch (e) {
      logToFile(tag: LogTag.ERROR, message: '[QrSelTest] 출력 실패: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('QR 테스트 출력 실패: $e')),
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
                          '주문번호 테스트 (1번호 × -1·-5·-10·-15·-20 = 5장 / 실상품·옵션·메모 / QR 토글 반영)'),
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
                  const SizedBox(height: AppSpacing.s16),
                  const Divider(height: 1),
                  const SizedBox(height: AppSpacing.s8),
                  Text(
                    'QR 테스트 (페이로드 / 레벨 / 크기 선택)',
                    style: AppTextStyles.bodySm.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.deepPurple,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  _buildQrSelectorRow(
                    label: '상품 페이로드',
                    child: Wrap(
                      spacing: AppSpacing.s8,
                      children: [
                        for (final p in _qrPayloads)
                          ChoiceChip(
                            label: Text(p.id),
                            selected: _qrTestPayload == p.payload,
                            onSelected: (_) =>
                                setState(() => _qrTestPayload = p.payload),
                          ),
                      ],
                    ),
                  ),
                  _buildQrSelectorRow(
                    label: 'QR 레벨',
                    child: Wrap(
                      spacing: AppSpacing.s8,
                      children: [
                        for (final lv in _qrLevels)
                          ChoiceChip(
                            label: Text('${lv.name} (${lv.recover})'),
                            selected: _qrTestLevel == lv.level,
                            onSelected: (_) =>
                                setState(() => _qrTestLevel = lv.level),
                          ),
                      ],
                    ),
                  ),
                  _buildQrSelectorRow(
                    label: 'QR 크기',
                    child: Wrap(
                      spacing: AppSpacing.s8,
                      children: [
                        for (int i = 0; i < _qrSizeSteps.length; i++)
                          ChoiceChip(
                            label: Text(i == 0
                                ? '현재 (${LabelPainter.qrSizeDefault.toStringAsFixed(0)}px)'
                                : '+${(_qrSizeSteps[i] * 100).round()}%'
                                    ' (${(LabelPainter.qrSizeDefault * (1 + _qrSizeSteps[i])).toStringAsFixed(0)}px)'),
                            selected: _qrTestSizeStep == i,
                            onSelected: (_) =>
                                setState(() => _qrTestSizeStep = i),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  Center(
                    child: ElevatedButton.icon(
                      onPressed: _printQrSelectedTest,
                      icon: const Icon(Icons.qr_code_2, size: 18),
                      label: const Text('선택 조건으로 출력 (1장)'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
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

  /// QR 테스트 셀렉터 한 줄 (라벨 + 칩 묶음). 좁은 폭이면 칩이 다음 줄로 흐른다.
  Widget _buildQrSelectorRow({required String label, required Widget child}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s8),
              child: Text(
                label,
                style: AppTextStyles.bodySm.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppStyles.gray9,
                ),
              ),
            ),
          ),
          Expanded(child: child),
        ],
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
