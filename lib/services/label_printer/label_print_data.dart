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
// - QR 페이로드 생성 — 라벨마다 다름. 포맷은 브랜드별 QrPayloadStrategy 에 위임
//   (기본 DefaultQrPayloadStrategy = "{OrderNo}-{ShopItemId}-{CupIdx}").
//   상세 포맷은 qr_payload_strategy.dart 참고.

import 'package:intl/intl.dart';

import 'package:appfit_order_agent/models/menu_option_model.dart';
import 'package:appfit_order_agent/models/order_model.dart';
import 'package:appfit_order_agent/models/product_model.dart';
import 'package:appfit_order_agent/services/label_printer/fast_menu_policy.dart';
import 'package:appfit_order_agent/services/label_printer/label_filter_strategy.dart';
import 'package:appfit_order_agent/services/label_printer/label_target.dart';
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
    this.isFastMenu = false,
    this.target = LabelTarget.primary,
  });

  final String menuName;
  final List<String> options;

  /// 빠른 제조 메뉴로 지정된 상품인지. 라벨 마커 표시 여부를 [LabelPainter] 에
  /// 넘길 때만 쓰인다 — 인쇄 순서는 이미 [fromOrder] 에서 결정된 뒤다.
  final bool isFastMenu;

  /// 주문번호 (예: "0795"). 라벨에 큼지막하게 출력.
  final String? shopOrderNo;

  /// "MM/dd\nHH:mm:ss" 포맷 권장.
  final String? orderTime;

  /// sub-info 영역 (원두/온도/사이즈). kokonut 은 분류 룰이 없어 항상 null.
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

  /// 이 라벨이 향할 프린터(= 제조 구역). 미설정 매장은 항상 [LabelTarget.primary].
  ///
  /// 담당하지 않는 타깃의 라벨을 걸러내는 것은 소비자([OutputService.printOrderLabels])
  /// 의 몫이다 — 여기서 빼버리면 `orderTotal` 채번이 흔들린다.
  final LabelTarget target;

  /// appfit [OrderModel] 을 라벨 묶음(메뉴 1개당 qty 장 반복) 으로 변환.
  ///
  /// [products]: 옵션 카테고리 분류용 카탈로그.
  /// [filterMode]: 0=전체, 1=와플만, 2=와플제외 (필터를 쓰는 브랜드에서만 의미).
  /// [strategy]: 브랜드별 메뉴 필터/옵션 분류 동작. 기본 [NoOpLabelFilterStrategy]
  ///             는 필터 없이 단순 평면화 (기존 kokonut 등 동작 유지).
  /// [qrStrategy]: 브랜드별 QR 페이로드 포맷. 기본 [DefaultQrPayloadStrategy]
  ///              는 "{OrderNo}-{ShopItemId}-{CupIdx}" (현재 코드 포맷).
  /// [isReprint]: true 면 카테고리 필터링 우회 (재출력은 전체 라벨 인쇄).
  /// [fastMenuPolicy]: 빠른 제조 메뉴 우선 정렬. 기본 [FastMenuPolicy.disabled]
  ///              는 아무 것도 하지 않아 종전 동작과 동일하다.
  static List<LabelPrintData> fromOrder(
    OrderModel order, {
    List<ProductModel> products = const [],
    int filterMode = 0,
    LabelFilterStrategy strategy = const NoOpLabelFilterStrategy(),
    QrPayloadStrategy qrStrategy = const DefaultQrPayloadStrategy(),
    bool isReprint = false,
    FastMenuPolicy fastMenuPolicy = FastMenuPolicy.disabled,
    LabelTargetPolicy targetPolicy = LabelTargetPolicy.disabled,
  }) {
    // 1) 메뉴 카테고리 필터링 — 브랜드 전략에 위임 (기본 NoOp = 전체).
    //    그 결과에 빠른 메뉴 우선 정렬을 얹는다. 필터 → 정렬 순서가 중요하다:
    //    반대로 하면 필터가 정렬을 되돌린다.
    //    이 정렬은 **순회(=인쇄) 순서만** 바꾼다. 라벨 순번 채번은 아래 3)에서
    //    원본 순서 기준으로 따로 수행하므로 cupIdx/QR 은 정렬과 무관하다.
    final menusToPrint = fastMenuPolicy.sortFastFirst(strategy.selectMenus(
      order,
      products: products,
      filterMode: filterMode,
      isReprint: isReprint,
    ));

    if (menusToPrint.isEmpty) return const [];

    // 2) 전체 라벨 수는 필터 무관 전체 메뉴 수량 합산 (기존 동작 보존)
    final totalLabels = order.menus.fold<int>(0, (sum, m) => sum + m.qty);
    if (totalLabels == 0) return const [];

    // 3) 메뉴별 시작 인덱스 미리 계산 — 반드시 **원본 메뉴 순서** 기준.
    //
    //    여기서 나오는 orderIndex 는 인쇄 카운터가 아니라 **컵의 고유 식별자
    //    (cup index)** 다. QR 로 스캔해 서버 데이터와 대조하는 용도이므로,
    //    빠른 메뉴 정렬 같은 출력 편의 때문에 값이 흔들리면 안 된다.
    //    운영 기본 QR 포맷(`DisplayNumIndexQrPayloadStrategy`,
    //    `getLabelQrPayloadFormat()` 기본값 1)이 `cupIdx = labelIndex - 1` 로
    //    이 값을 직접 쓴다 — 정렬된 순서로 채번하면 페이로드가 바뀐다.
    //
    //    그 대가로 **인쇄되는 순번은 단조 증가하지 않는다**(예: 2/3 → 3/3 → 1/3).
    //    의도된 동작이다: 순번은 컵의 이름이지 인쇄 차례가 아니다.
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
      // 마커 표시용 플래그. 순수 멤버십이라 mode 와 독립 — 매장이 순서는 그대로
      // 두고 표시만 켜는 운용이 가능하다.
      final isFastMenu = fastMenuPolicy.isFast(menu);

      // 행선지 배정 — 메뉴 단위로 한 번만. 같은 메뉴의 qty 장은 전부 같은 프린터로
      // 간다(같은 음료 3잔이 두 구역에 흩어지면 제조가 안 된다).
      final target =
          strategy.assignTarget(menu, products: products, policy: targetPolicy);

      // 옵션 카테고리 분류 — 브랜드 전략에 위임 (기본 NoOp = 분류 없음).
      final cats = strategy.classifyOptions(menu, products: products);
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
          isFastMenu: isFastMenu,
          target: target,
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
