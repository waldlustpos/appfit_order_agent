// 라벨 출력에 필요한 모델-중립 DTO.
//
// OutputService.printOrderLabels 가 OrderModel 을 받아 fromOrder() 로 변환한 뒤
// LabelPainter 에 라벨 1장씩 전달한다.
//
// fromOrder() 가 단일 진입점:
// - 메뉴 카테고리 필터링 + 옵션 카테고리 분류(원두/온도/사이즈)는 브랜드별
//   LabelFilterStrategy 에 위임 (TPCP=TpcpLabelFilterStrategy, 그 외=NoOp).
//   products 카탈로그 필요.
// - 메뉴 qty 만큼 라벨 펼치기
// - QR 페이로드 생성 — 라벨마다 다름. 포맷:
//     "{OrderNo}-{ShopItemId}-{CupIdx}-{ShopCode}-{YYYYMMDD}-{DisplayNo}"
//     예: ORD-123456-M1-0-SHOP001-20260520-0795
//   * OrderNo   : 주문 식별자 (orderNo, '-' 포함 가능)
//   * ShopItemId: 상품(메뉴) 식별자
//   * CupIdx    : 같은 메뉴 내 0-based sequence (중복 스캔 방지)
//   * ShopCode  : 매장 코드 (storeId)
//   * YYYYMMDD  : 매장 영업일 (orderedAt 의 날짜 부분)
//   * DisplayNo : display no 4자리 (zero-padded)

import 'package:intl/intl.dart';

import 'package:appfit_order_agent/models/menu_option_model.dart';
import 'package:appfit_order_agent/models/order_model.dart';
import 'package:appfit_order_agent/models/product_model.dart';
import 'package:appfit_order_agent/services/label_printer/label_filter_strategy.dart';
import 'package:appfit_order_agent/utils/logger.dart';

/// 라벨에 동봉되는 주문 식별 정보. 같은 주문의 모든 라벨에서 동일.
class LabelOrderInfo {
  const LabelOrderInfo({
    required this.orderNo,
    required this.displayNum,
    required this.shopOrderNo,
    required this.storeId,
    required this.orderedAt,
    this.storeName,
    this.memo,
    this.orderType,
    this.userName,
    this.totalAmount,
    this.kioskId,
    this.source,
  });

  final String orderNo;
  final String displayNum;
  final String shopOrderNo;
  final String storeId;
  final DateTime orderedAt;
  final String? storeName;
  final String? memo;
  final String? orderType; // 'T'/'H'/'C'
  final String? userName;
  final double? totalAmount;
  final String? kioskId;
  final String? source;

  factory LabelOrderInfo.fromOrder(OrderModel order) {
    return LabelOrderInfo(
      orderNo: order.orderNo,
      displayNum: order.displayNum,
      shopOrderNo: order.shopOrderNo,
      storeId: order.storeId,
      orderedAt: order.orderedAt,
      storeName: order.storeName,
      memo: order.note,
      orderType: order.orderType.isNotEmpty ? order.orderType : null,
      userName: order.userName,
      totalAmount: order.totalAmount,
      kioskId: order.kioskId.isNotEmpty ? order.kioskId : null,
      source: order.source.isNotEmpty ? order.source : null,
    );
  }
}

/// 라벨에 인쇄되는 한 장의 메뉴 식별 정보 (라벨마다 다름).
class LabelMenuInfo {
  const LabelMenuInfo({
    required this.shopItemId,
    required this.itemName,
    required this.itemPrice,
    required this.qty,
    required this.labelSeq,
    required this.options,
  });

  final String shopItemId;
  final String itemName;
  final double itemPrice;

  /// 메뉴 전체 수량 (예: 아메리카노 3잔이면 3).
  final int qty;

  /// 이 메뉴 안에서 몇 번째 라벨인지 (1..qty).
  final int labelSeq;

  final List<LabelOptionInfo> options;
}

class LabelOptionInfo {
  const LabelOptionInfo({
    required this.shopOptionId,
    required this.optionName,
    required this.optionPrice,
    required this.qty,
  });

  final String shopOptionId;
  final String optionName;
  final double optionPrice;
  final int qty;

  factory LabelOptionInfo.fromModel(MenuOptionModel opt) {
    return LabelOptionInfo(
      shopOptionId: opt.shopOptionId,
      optionName: opt.optionName,
      optionPrice: opt.optionPrice,
      qty: opt.qty,
    );
  }
}

class LabelPrintData {
  const LabelPrintData({
    required this.menuName,
    required this.options,
    required this.orderIndex,
    required this.orderTotal,
    this.shopOrderNo,
    this.orderTime,
    this.beanType,
    this.temperature,
    this.sizeOption,
    this.memo,
    this.qrData,
    this.orderInfo,
    this.menuInfo,
  });

  final String menuName;
  final List<String> options;

  /// 주문번호 (예: "0795"). 라벨에 큼지막하게 출력.
  final String? shopOrderNo;

  /// "MM/dd\nHH:mm:ss" 포맷 권장.
  final String? orderTime;

  /// sub-info 영역 (원두/온도/사이즈). kokonut 은 분류 룰이 없어 항상 null.
  final String? beanType;
  final String? temperature;
  final String? sizeOption;

  final String? memo;

  /// QR 페이로드 (Body 영역 좌측에 그려짐). fromOrder() 가 자동으로 채움.
  /// 포맷: "{OrderNo}-{ShopItemId}-{CupIdx}-{ShopCode}-{YYYYMMDD}-{DisplayNo}".
  final String? qrData;

  /// 한 주문 묶음 안에서 1부터 시작하는 누적 인덱스 (예: 1, 2, 3, 4 ...).
  final int orderIndex;

  /// 같은 묶음의 전체 라벨 매수.
  final int orderTotal;

  /// 주문 식별 정보 (모든 라벨이 공유). QR 페이로드의 store/order 영역에 들어간다.
  final LabelOrderInfo? orderInfo;

  /// 메뉴 식별 정보 (라벨마다 다름). QR 페이로드의 menu 영역에 들어간다.
  final LabelMenuInfo? menuInfo;

  /// appfit [OrderModel] 을 라벨 묶음(메뉴 1개당 qty 장 반복) 으로 변환.
  ///
  /// [products]: 옵션 카테고리 분류용 카탈로그.
  /// [filterMode]: 0=전체, 1=와플만, 2=와플제외 (필터를 쓰는 브랜드에서만 의미).
  /// [strategy]: 브랜드별 메뉴 필터/옵션 분류 동작. 기본 [NoOpLabelFilterStrategy]
  ///             는 필터 없이 단순 평면화 (기존 kokonut 등 동작 유지).
  /// [isReprint]: true 면 카테고리 필터링 우회 (재출력은 전체 라벨 인쇄).
  static List<LabelPrintData> fromOrder(
    OrderModel order, {
    List<ProductModel> products = const [],
    int filterMode = 0,
    LabelFilterStrategy strategy = const NoOpLabelFilterStrategy(),
    bool isReprint = false,
  }) {
    // 1) 메뉴 카테고리 필터링 — 브랜드 전략에 위임 (기본 NoOp = 전체).
    final menusToPrint = strategy.selectMenus(
      order,
      products: products,
      filterMode: filterMode,
      isReprint: isReprint,
    );

    if (menusToPrint.isEmpty) return const [];

    // 2) 전체 라벨 수는 필터 무관 전체 메뉴 수량 합산 (기존 동작 보존)
    final totalLabels = order.menus.fold<int>(0, (sum, m) => sum + m.qty);
    if (totalLabels == 0) return const [];

    // 3) 메뉴별 시작 인덱스 미리 계산 (전체 메뉴 기준)
    final menuStartIndex = <int, int>{};
    var runningIndex = 0;
    for (final menu in order.menus) {
      menuStartIndex[identityHashCode(menu)] = runningIndex;
      runningIndex += menu.qty;
    }

    final timeStr = DateFormat('MM/dd\nHH:mm:ss').format(order.orderedAt);
    final shopOrderNo =
        order.displayNum.isNotEmpty ? order.displayNum : order.shopOrderNo;
    final orderInfo = LabelOrderInfo.fromOrder(order);

    final result = <LabelPrintData>[];

    for (final menu in menusToPrint) {
      // 옵션 카테고리 분류 — 브랜드 전략에 위임 (기본 NoOp = 분류 없음).
      final cats = strategy.classifyOptions(menu, products: products);
      final String? beanType = cats.beanType;
      final String? temperature = cats.temperature;
      final String? sizeOption = cats.sizeOption;

      // 서브정보로 표시되는 옵션은 하단 옵션 리스트에서 제외
      final remainingOptions = menu.options.where((opt) =>
          opt.optionName != beanType &&
          opt.optionName != temperature &&
          opt.optionName != sizeOption);

      final flatOptions = remainingOptions
          .map((opt) =>
              opt.qty > 1 ? '${opt.qty} ${opt.optionName}' : opt.optionName)
          .where((name) => name.isNotEmpty)
          .toList();

      // QR menuInfo 의 options 는 분류 안 한 전체 옵션을 보존 (식별 목적)
      final qrOptions =
          menu.options.map((o) => LabelOptionInfo.fromModel(o)).toList();

      for (var i = 0; i < menu.qty; i++) {
        final labelIndex = menuStartIndex[identityHashCode(menu)]! + i + 1;
        final menuInfo = LabelMenuInfo(
          shopItemId: menu.shopItemId,
          itemName: menu.itemName,
          itemPrice: menu.itemPrice,
          qty: menu.qty,
          labelSeq: i + 1,
          options: qrOptions,
        );

        result.add(LabelPrintData(
          menuName: menu.itemName,
          options: flatOptions,
          shopOrderNo: shopOrderNo.isNotEmpty ? shopOrderNo : null,
          orderTime: timeStr,
          beanType: beanType,
          temperature: temperature,
          sizeOption: sizeOption,
          memo: order.note,
          orderIndex: labelIndex,
          orderTotal: totalLabels,
          orderInfo: orderInfo,
          menuInfo: menuInfo,
          qrData: _buildQrPayload(orderInfo, menuInfo, labelIndex, totalLabels),
        ));
      }
    }
    return result;
  }

  /// 라벨 1장의 QR 페이로드.
  ///
  /// 포맷: "{OrderNo}-{ShopItemId}-{CupIdx}-{ShopCode}-{YYYYMMDD}-{DisplayNo}".
  /// 예: ORD-123456-M1-0-SHOP001-20260520-0795
  ///
  /// - OrderNo   : 주문 식별자
  /// - ShopItemId: 메뉴 식별자
  /// - CupIdx    : 같은 메뉴 안에서 0-based 라벨 sequence (중복 스캔 방지)
  /// - ShopCode  : storeId
  /// - YYYYMMDD  : orderedAt 의 날짜 (별도 영업일 필드가 없어 주문 시각 기준)
  /// - DisplayNo : display no 4자리 (LabelOrderInfo.displayNum)
  static String _buildQrPayload(
    LabelOrderInfo orderInfo,
    LabelMenuInfo menuInfo,
    int labelIndex,
    int labelTotal,
  ) {
    final dateStr = DateFormat('yyyyMMdd').format(orderInfo.orderedAt);
    final cupIdx = menuInfo.labelSeq - 1; // 1-based labelSeq → 0-based cupIdx
    final payload = '${orderInfo.orderNo}-${menuInfo.shopItemId}-$cupIdx';
    //'-${orderInfo.storeId}-$dateStr-${orderInfo.displayNum}';
    logger.d('[Label][QR] $labelIndex/$labelTotal'
        ' ${menuInfo.itemName} (${menuInfo.labelSeq}/${menuInfo.qty})'
        ' → $payload');
    return payload;
  }

  /// 테스트 인쇄용 더미 데이터.
  static LabelPrintData testSample() {
    return LabelPrintData(
      menuName: '테스트 메뉴',
      options: const ['옵션 A', '옵션 B'],
      shopOrderNo: '0001',
      orderTime: DateFormat('MM/dd\nHH:mm:ss').format(DateTime.now()),
      memo: '라벨 프린터 테스트 인쇄',
      orderIndex: 1,
      orderTotal: 1,
    );
  }
}
