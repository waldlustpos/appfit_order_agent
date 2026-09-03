// 라벨 출력에 필요한 모델-중립 DTO.
//
// OutputService.printOrderLabels 가 OrderModel 을 받아 fromOrder() 로 변환한 뒤
// LabelPainter 에 라벨 1장씩 전달한다.
//
// fromOrder() 가 단일 진입점:
// - 메뉴 카테고리 필터링은 매장이 설정 화면에서 고른 LabelOutputPolicy 가,
//   옵션 카테고리 분류(원두/온도/사이즈)는 브랜드별 LabelSubInfoStrategy 가
//   결정한다(TPCP=Tpcp…, 그 외=NoOp). 둘 다 products 카탈로그 필요 — 주문 응답에
//   카테고리가 없어 조인해야 한다.
// - 메뉴 qty 만큼 라벨 펼치기
// - QR 페이로드 생성 — 라벨마다 다름. QrPayloadStrategy 에 위임
//   (고정 DisplayNumIndexQrPayloadStrategy = "{DisplayNum}-{CupIdx}").
//   상세 포맷은 qr_payload_strategy.dart 참고.

import 'package:intl/intl.dart';

import 'package:appfit_order_agent/models/menu_option_model.dart';
import 'package:appfit_order_agent/models/order_model.dart';
import 'package:appfit_order_agent/models/product_model.dart';
import 'package:appfit_order_agent/services/label_printer/label_output_policy.dart';
import 'package:appfit_order_agent/services/label_printer/label_subinfo_strategy.dart';
import 'package:appfit_order_agent/services/label_printer/qr_payload_strategy.dart';
import 'package:appfit_order_agent/utils/common_util.dart';

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

  /// sub-info 영역 (원두/온도/사이즈). 분류 룰이 없는 브랜드는 항상 null.
  final String? beanType;
  final String? temperature;
  final String? sizeOption;

  final String? memo;

  /// QR 페이로드 (Body 영역 좌측에 그려짐). fromOrder() 가 [QrPayloadStrategy] 로 채움.
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
  /// [products]: 카테고리/옵션그룹 조인용 카탈로그. 주문 응답에는 카테고리가 없다.
  /// [policy]: 매장이 설정 화면에서 고른 출력 카테고리. 기본
  ///           [LabelOutputPolicy.disabled] 는 전량 인쇄.
  /// [subInfoStrategy]: 브랜드별 sub-info 옵션 분류. 기본
  ///           [NoOpLabelSubInfoStrategy] 는 분류 없음(sub-info 영역이 빈다).
  /// [qrStrategy]: QR 페이로드 포맷. 기본 [DisplayNumIndexQrPayloadStrategy]
  ///              는 "{DisplayNum}-{CupIdx}".
  /// [isReprint]: true 면 카테고리 필터링 우회 (재출력은 전체 라벨 인쇄).
  static List<LabelPrintData> fromOrder(
    OrderModel order, {
    List<ProductModel> products = const [],
    LabelOutputPolicy policy = LabelOutputPolicy.disabled,
    LabelSubInfoStrategy subInfoStrategy = const NoOpLabelSubInfoStrategy(),
    QrPayloadStrategy qrStrategy = const DisplayNumIndexQrPayloadStrategy(),
    bool isReprint = false,
  }) {
    // 카탈로그 조회 인덱스 — 주문당 1회만 만들어 메뉴/옵션 조인에 재사용.
    final index = LabelProductIndex.build(products);

    // 1) 메뉴 카테고리 필터링. 재출력은 필터를 우회해 전체를 인쇄한다 — 점주가
    //    라벨을 다시 뽑는 시점의 의도는 "그 주문 전부"이기 때문.
    final menusToPrint = isReprint
        ? order.menus
        : order.menus.where((m) => policy.shouldPrintMenu(m, index)).toList();

    if (menusToPrint.isEmpty) return const [];

    // 2) 전체 라벨 수는 **필터 무관 전체 메뉴 수량 합산**이다.
    //    orderIndex/orderTotal 은 인쇄 매수 카운터가 아니라 **컵 식별자**이고,
    //    QR 페이로드({DisplayNum}-{CupIdx})와 QR ON 시 주문번호 접미사의 정본이다.
    //    필터로 일부가 빠지면 라벨에 "2/5", "4/5" 처럼 건너뛴 번호가 찍히는 것이
    //    정상 동작 — 남은 것만으로 다시 채번하면 같은 컵이 설정에 따라 다른 번호를
    //    갖게 돼 주문↔컵 대조가 깨진다.
    final totalLabels = order.menus.fold<int>(0, (sum, m) => sum + m.qty);
    if (totalLabels == 0) return const [];

    // 3) 메뉴별 시작 인덱스 미리 계산 (전체 메뉴 기준)
    final menuStartIndex = <int, int>{};
    var runningIndex = 0;
    for (final menu in order.menus) {
      menuStartIndex[identityHashCode(menu)] = runningIndex;
      runningIndex += menu.qty;
    }

    // 의도적 개행(라벨 헤더 2줄). CommonUtil.normalizeInlineText 적용 금지 —
    // LabelPainter._drawHeader 가 maxLines:2 / maxWidth:120 으로 받는다.
    final timeStr = DateFormat('MM/dd\nHH:mm:ss').format(order.orderedAt);
    final shopOrderNo =
        order.displayNum.isNotEmpty ? order.displayNum : order.shopOrderNo;
    final orderInfo = LabelOrderInfo.fromOrder(order);

    final result = <LabelPrintData>[];

    for (final menu in menusToPrint) {
      // 옵션 카테고리 분류 — 브랜드 전략에 위임 (기본 NoOp = 분류 없음).
      final cats = subInfoStrategy.classifyOptions(menu, products: products);
      final String? beanType = cats.beanType;
      final String? temperature = cats.temperature;
      final String? sizeOption = cats.sizeOption;

      // 서브정보로 표시되는 옵션은 하단 옵션 리스트에서 제외.
      // 이름 비교가 아니라 분류에 실제 소비된 옵션 집합으로 걸러야 동명 옵션이
      // 함께 빠지는 오제외가 생기지 않는다.
      final remainingOptions =
          menu.options.where((opt) => !cats.classified.contains(opt));

      // 표시용 정규화(개행→공백)는 여기서만. QR/menuInfo 는 아래에서 원문을
      // 보존하므로 서버값 대조가 계속 가능하다.
      final flatOptions = remainingOptions
          .map((opt) {
            final name = CommonUtil.normalizeInlineText(opt.optionName);
            return opt.qty > 1 ? '${opt.qty} $name' : name;
          })
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
          menuName: CommonUtil.normalizeInlineText(menu.itemName),
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
          qrData: qrStrategy.buildPayload(
              orderInfo, menuInfo, labelIndex, totalLabels),
        ));
      }
    }
    return result;
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
