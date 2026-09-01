import 'package:flutter/foundation.dart' show listEquals;
import 'package:intl/intl.dart';
import 'package:appfit_order_agent/utils/logger.dart';
import 'package:appfit_order_agent/utils/kds_utils.dart' as kds_utils;
import 'package:appfit_order_agent/models/enums/order_status.dart';
import 'package:appfit_order_agent/models/order_discount_model.dart';
import 'package:appfit_order_agent/models/order_menu_model.dart';
import 'package:appfit_order_agent/models/order_payment_model.dart';

export 'package:appfit_order_agent/models/enums/order_status.dart';
export 'package:appfit_order_agent/models/order_discount_model.dart';
export 'package:appfit_order_agent/models/order_payment_model.dart';

class OrderModel {
  final String orderNo; // ordrId -> orderNo
  final String shopOrderNo; // ordrSimpleId -> shopOrderNo
  final String displayOrderNo; // displayOrderNo from API (user-facing)
  final String orderStatus; // orderStusCd -> orderStatus
  final DateTime orderedAt; // orderTime -> orderedAt
  final double totalAmount; // ordrPrc (keep)
  final OrderStatus status; // keep enum
  final String storeId; // keep
  final String? customerName; // name (keep or ordererName?)
  final String? tel; // ordrCnct -> tel
  final String? note; // ordrMemo -> note (renamed)
  final String userId; // mbrId -> userId
  String? userName; // 사용자 이름 (응답에 포함됨)
  String? storeName; // 매장명

  // 추가 필드
  final String ordererName; // 주문자 대표 상품명 (ordererNm -> ordererName)
  final String orderCount; // 주문 상품 개수 (ordrCnt)
  final double paymentAmount; // 실제 결제 금액 (payPrc -> paymentAmount)
  final double discountAmount; // 할인 금액 (discPrc -> discountAmount)
  final String paymentType; // 결제 방법 (SERVICE, CARD 등) (payMthd -> paymentType)
  final String paymentCode; // 결제 방법 코드 (payMthdCd -> paymentCode)
  final DateTime? paidAt; // 결제 시간 (payDtm -> paidAt)
  final List<OrderMenuModel> menus; // 주문 메뉴 목록 (orderMenuList -> menus)
  final DateTime updateTime; // 주문 정보 업데이트 시간
  final double exceptTaxPrice; // 세금 제외 금액
  final double taxPrice; // 세금 금액
  final String kioskId; // 키오스크 ID
  final String source; // 주문 소스 (WALD_KIOSK 등)
  final String orderType; // 키오스크 주문 타입 (T, H, C)
  final int kdsOrderType; // KDS에서 사용하는 주문 타입 (1: 간단, 2: 복잡)
  final bool isDetailLoaded; // 상세 정보 로딩 여부

  // ── 상세 조회(`/v1/orders/{orderNo}`) 에서만 채워지는 필드 ──────────────
  // 목록/소켓 응답에는 없다. 이 필드들을 늘릴 때는 반드시 [withDetailsFrom] 에도
  // 추가해야 상태 변경 이벤트가 도착해도 유실되지 않는다.

  /// 결제수단별 사용 내역. 복합결제면 여러 건. 상위 [paymentType] 은 이때 `MULTI`.
  final List<OrderPaymentModel> payments;

  /// 할인 종류별 내역(금액·쿠폰명 포함).
  final List<OrderDiscountModel> discounts;

  /// 회원 바코드(`data.user.barcode`). 주문 채널에 따라 없을 수 있다(비회원·키오스크).
  ///
  /// 화면에는 쓰지 않는다 — **로그 전용 식별 키**다. 주문 상세 로그에서 고객을
  /// 지목해야 할 때 실명/닉네임(`userName`)·연락처(`tel`) 대신 이걸 남긴다.
  /// 바코드는 회원 DB 를 거쳐야만 사람으로 환원되는 가명 식별자라, 로그 파일이
  /// 기기 밖(Slack 업로드·로컬 로그서버)으로 나가도 그 자체로는 개인을 식별하지 않는다.
  final String? userBarcode;

  OrderModel({
    required this.orderNo,
    required this.shopOrderNo,
    String displayOrderNo = '',
    required this.orderStatus,
    required this.orderedAt,
    required this.totalAmount,
    required this.status,
    required this.storeId,
    required this.userId,
    this.customerName,
    this.tel,
    this.note,
    this.userName,
    this.storeName,
    required this.ordererName,
    required this.orderCount,
    required this.paymentAmount,
    required this.discountAmount,
    required this.paymentType,
    required this.paymentCode,
    this.paidAt,
    required this.menus,
    required this.orderType,
    required this.kdsOrderType,
    DateTime? updateTime,
    required this.kioskId,
    String source = '',
    bool? isDetailLoaded,
    this.payments = const [],
    this.discounts = const [],
    this.userBarcode,
  })  : source = source,
        displayOrderNo = displayOrderNo,
        updateTime = updateTime ?? DateTime.now(),
        // 메뉴가 있으면 기본적으로 로딩된 것으로 간주, 명시적 값 있으면 그것 사용
        isDetailLoaded = isDetailLoaded ?? (menus.isNotEmpty),
        exceptTaxPrice = _calculateExceptTaxPrice(paymentAmount),
        taxPrice = _calculateTaxPrice(paymentAmount);

  // Getter for displayNum compatibility/logic
  String get displayNum {
    final raw = displayOrderNo.isNotEmpty ? displayOrderNo : shopOrderNo;
    final num = int.tryParse(raw);
    return num != null ? num.toString().padLeft(4, '0') : raw;
  }

  String get orderId => orderNo;
  List<OrderMenuModel> get orderMenuList => menus;

  /// [discounts] 의 discountType distinct 목록. 과거에는 독립 필드였으나
  /// 금액까지 담는 [discounts] 가 생기면서 파생값으로 강등했다(이중 진실 방지).
  List<String> get discountTypes => discounts
      .map((d) => d.discountType)
      .where((t) => t.isNotEmpty)
      .toSet()
      .toList();

  /// 목록/소켓이 준 주문(this)에 [detail] 의 **상세 전용 필드만** 이식한다.
  /// 상태(status/orderStatus/updateTime)는 this 를 유지한다 — 소켓 쪽이 최신이라서다.
  ///
  /// 상세 전용 필드를 새로 추가할 때는 **여기 한 곳만** 고치면 된다. 과거에는
  /// `order_provider` 4곳에 `copyWith(menus:…, isDetailLoaded: true, …)` 가 흩어져
  /// 있어서, 상태 변경 이벤트가 한 번만 도착해도 상세 전용 필드가 기본값으로
  /// 리셋되면서 `isDetailLoaded` 만 true 로 남았다(→ 재조회도 안 되고 값도 없음).
  OrderModel withDetailsFrom(OrderModel detail) => copyWith(
        menus: detail.menus,
        isDetailLoaded: true,
        kdsOrderType: detail.kdsOrderType,
        payments: detail.payments,
        discounts: detail.discounts,
        userBarcode: detail.userBarcode,
      );
  // Getter for backward compatibility alias if needed, though we should change all usages
  // String? get memo => note; // Let's try to remove this alias and fix usages

  // 세금 제외 금액 계산
  static double _calculateExceptTaxPrice(double price) {
    return (price * 100 / 110.0).roundToDouble();
  }

  // 세금 금액 계산
  static double _calculateTaxPrice(double price) {
    return (price * 10 / 110.0).roundToDouble();
  }

  factory OrderModel.fromJson(Map<String, dynamic> json) {
    // 주문 상태 문자열을 OrderStatus enum으로 변환.
    // 매핑은 kServerOrderStatus(앱 전역 단일 표)에 위임한다 — 프로덕션 파서
    // ApiService._mapAppFitOrderStatus 와 같은 표를 봐야 한쪽만 갱신되는
    // 사고를 막을 수 있다. 구 시스템(kokonut) 숫자 코드는 제거됨.
    OrderStatus parseStatus(String statusCode) {
      final mapped = kServerOrderStatus[statusCode.toUpperCase()];
      if (mapped != null) return mapped;
      logger.w(
          'Unknown order status code found: $statusCode, mapping to CANCELLED.');
      return OrderStatus.CANCELLED;
    }

    // 주문 메뉴 목록 파싱 (항목별 격리: 1건 손상 시 해당 항목만 스킵, 정상 항목 유지)
    // Handle both 'menus' (AppFit) and 'ordrPrdList' (Internal/Legacy) keys
    final List<OrderMenuModel> menus = [];
    final menuListRaw = json['menus'];
    if (menuListRaw is List) {
      for (final item in menuListRaw) {
        try {
          menus.add(OrderMenuModel.fromJson(item));
        } catch (e, s) {
          logger.e('Error parsing menu item (skipped): $item',
              error: e, stackTrace: s);
        }
      }
    } else if (menuListRaw != null) {
      logger.e('Error parsing menu list: menus is not a List ($menuListRaw)');
    }

    // Mapping fields
    String _orderNo = (json['orderNo'])?.toString() ?? '';
    String _shopOrderNo = (json['shopOrderNo'])?.toString() ?? '';
    String _displayOrderNum =
        (json['displayOrderNum'])?.toString() ?? _shopOrderNo;
    String _displayOrderNo = (json['displayOrderNo'])?.toString() ?? '';
    String _orderStatus = (json['orderStatus'])?.toString() ?? '';
    DateTime _orderedAt =
        DateTime.tryParse(json['orderedAt']?.toString() ?? '') ??
            DateTime.now();
    double _totalAmount =
        double.tryParse(json['totalAmount']?.toString() ?? '0') ?? 0.0;
    String _userId = (json['userId'])?.toString() ?? '';
    String? _tel = (json['tel'])?.toString();
    String _ordererName = (json['ordererName'])?.toString() ?? '';
    double _paymentAmount =
        double.tryParse(json['paymentAmount']?.toString() ?? '0') ?? 0.0;
    double _discountAmount =
        double.tryParse(json['discountAmount']?.toString() ?? '0') ?? 0.0;
    String _paymentType = (json['paymentType'])?.toString() ?? '';
    String _paymentCode = (json['paymentCode'])?.toString() ?? '';
    DateTime? _paidAt = DateTime.tryParse(json['paidAt']?.toString() ?? '');

    final tempOrder = OrderModel(
      orderNo: _orderNo,
      shopOrderNo: _shopOrderNo.isNotEmpty
          ? _shopOrderNo
          : _displayOrderNum, // Use display num if shopOrderNo is empty
      displayOrderNo: _displayOrderNo,
      orderStatus: _orderStatus,
      orderedAt: _orderedAt,
      totalAmount: _totalAmount,
      status: parseStatus(_orderStatus),
      storeId: json['storeId']?.toString() ?? '',
      userId: _userId,
      customerName: (json['customerName'])?.toString(),
      tel: _tel,
      note: (json['note'] ?? json['memo'])
          ?.toString(), // map both note and legacy memo
      userName: json['userName']?.toString() ??
          json['userNickname']?.toString(), // map userNickname as well
      storeName: json['storeName']?.toString(),
      ordererName: _ordererName,
      orderCount: (json['orderCount'])?.toString() ?? '0',
      paymentAmount: _paymentAmount,
      discountAmount: _discountAmount,
      paymentType: _paymentType,
      paymentCode: _paymentCode,
      paidAt: _paidAt,
      menus: menus,
      orderType: (json['orderType'] ?? json['order_type'])?.toString() ?? '',
      kdsOrderType: 0, // 임시값
      updateTime: DateTime.tryParse(json['updateTime'] ?? '') ?? DateTime.now(),
      kioskId: (json['kioskId'])?.toString() ?? '',
      source: (json['orderSource'] ?? json['source'])?.toString() ?? '',
      // JSON에 없으면 메뉴 유무로 판단, 있으면 비-bool 입력도 == true 비교로 무해화
      isDetailLoaded: json['isDetailLoaded'] != null
          ? json['isDetailLoaded'] == true
          : (menus.isNotEmpty),
      payments: _mapJsonList(json['payments'], OrderPaymentModel.fromJson),
      discounts: _mapJsonList(json['discounts'], OrderDiscountModel.fromJson),
      // 캐시 왕복용. 서버 원본(중첩 user.barcode)은 api_service 가 평탄화해서 넣는다.
      userBarcode: _emptyToNull(json['userBarcode']?.toString()),
    );

    // KDS 주문 타입 계산
    final kdsOrderType = tempOrder.menus.isNotEmpty
        ? kds_utils.determineOrderType(tempOrder, {})
        : 0;

    return tempOrder.copyWith(kdsOrderType: kdsOrderType);
  }

  // 상세 정보가 포함된 API 응답으로부터 모델 생성
  factory OrderModel.fromDetailJson(Map<String, dynamic> json) {
    final data = json['data'];
    if (data == null) {
      logger.e('Order detail data is null in API response.');
      throw Exception('상세 주문 데이터가 없습니다.');
    }
    return OrderModel.fromJson(data);
  }

  Map<String, dynamic> toJson() {
    return {
      'orderNo': orderNo,
      'shopOrderNo': shopOrderNo,
      'displayOrderNo': displayOrderNo,
      'displayOrderNum': displayNum,
      'orderedAt': DateFormat('yyyy-MM-dd HH:mm:ss').format(orderedAt),
      'totalAmount': totalAmount,
      'orderStatus': orderStatus,
      'storeId': storeId,
      'userId': userId,
      'customerName': customerName,
      'tel': tel,
      'note': note,
      'userName': userName,
      'storeName': storeName,
      'ordererName': ordererName,
      'orderCount': orderCount,
      'paymentAmount': paymentAmount,
      'discountAmount': discountAmount,
      'paymentType': paymentType,
      'paymentCode': paymentCode,
      'paidAt': paidAt != null
          ? DateFormat('yyyy-MM-dd HH:mm:ss').format(paidAt!)
          : null,
      'menus': menus.map((menu) => menu.toJson()).toList(),
      'exceptTaxPrice': exceptTaxPrice,
      'taxPrice': taxPrice,
      'kioskId': kioskId,
      'source': source,
      'orderType': orderType,
      'kdsOrderType': kdsOrderType,
      'isDetailLoaded': isDetailLoaded,
      // 파생값이지만 캐시 왕복(fromJson)·Sunmi 페이로드 shape 호환을 위해 유지.
      'discountTypes': discountTypes,
      'payments': payments.map((p) => p.toJson()).toList(),
      'discounts': discounts.map((d) => d.toJson()).toList(),
      'userBarcode': userBarcode,
    };
  }

  /// 빈 문자열을 null 로 접는다. 서버가 `"barcode": ""` 로 내려주는 케이스가 있어서,
  /// 로그에서 "값 없음"과 "빈 값"을 구분할 필요가 없다면 null 하나로 통일한다.
  static String? _emptyToNull(String? v) => (v == null || v.isEmpty) ? null : v;

  /// JSON 리스트 필드 공통 파서. List 가 아니거나 원소가 Map 이 아니면 스킵한다
  /// (메뉴 파싱과 같은 "항목별 격리" 정책 — 1건 손상이 주문 전체를 죽이지 않게).
  static List<T> _mapJsonList<T>(
      dynamic raw, T Function(Map<String, dynamic>) fromJson) {
    if (raw is! List) return const [];
    final out = <T>[];
    for (final e in raw) {
      if (e is! Map) continue;
      try {
        out.add(fromJson(Map<String, dynamic>.from(e)));
      } catch (err, s) {
        logger.e('주문 상세 배열 항목 파싱 실패 (스킵): $e', error: err, stackTrace: s);
      }
    }
    return out;
  }

  /// 사운드그래프 전송 페이로드. [brandId]는 호출자(브랜드별 hook)가 주입한다
  /// (모델은 브랜드에 무관). 현재 사운드그래프는 매머드(MMTH/MHST) 전용이라 'mmth'.
  Map<String, dynamic> toJsonForSoundGraph(String marketId,
      {required String brandId}) {
    final orderChannel = paymentCode.toUpperCase().contains('KIOSK') ? 1 : 2;
    final vibBell = int.tryParse(displayNum) ?? 0;
    return {
      'brandId': brandId,
      'marketId': marketId,
      'orderChannel': orderChannel,
      'vibBell': vibBell,
      'orderId': orderNo,
      'orders': menus.map((m) => m.toJsonForSoundGraph()).toList(),
      'kioskId': kioskId,
    };
  }

  /// Sunmi 프린터 전용 JSON. 숫자는 포맷된 문자열, Sunmi 호환 키 포함.
  Map<String, dynamic> toSunmiJson() {
    final fmt = NumberFormat('#,###');
    final dtFmt = DateFormat('yyyy-MM-dd HH:mm:ss');
    final formattedTotalAmount = fmt.format(totalAmount);
    final formattedPaymentAmount = fmt.format(paymentAmount);
    final formattedDiscountAmount = fmt.format(discountAmount);
    return {
      ...toJson(),
      'ordrSimpleId': shopOrderNo,
      'ordrDtm': dtFmt.format(orderedAt),
      'totalAmount': formattedTotalAmount,
      'ordrMemo': note,
      'paymentAmount': formattedPaymentAmount,
      'discountAmount': formattedDiscountAmount,
      'ordrPrdList': menus.map((menu) => menu.toJson()).toList(),
      'exceptTaxPrice': fmt.format(exceptTaxPrice),
      'taxPrice': fmt.format(taxPrice),
      // Sunmi Java 호환 키 (SunmiPrintHelper.java 에서 사용)
      'ordrPrc': formattedTotalAmount,
      'payPrc': formattedPaymentAmount,
      'discPrc': formattedDiscountAmount,
    };
  }

  // 주문 총액 계산 (모든 메뉴와 옵션 포함)
  double get calculatedTotalAmount {
    return menus.fold(0, (sum, menu) => sum + menu.totalPrice);
  }

  @override
  String toString() {
    return 'orderNo: $orderNo\nshopOrderNo: $shopOrderNo\ndisplayOrderNo: $displayOrderNo\ndisplayNum: $displayNum\norderStatus: $orderStatus\norderedAt: $orderedAt\ntotalAmount: $totalAmount\nstatus: $status\norderStatus: $orderStatus\nstoreId: $storeId\nuserName: $userName\nnote: $note\nuserId: $userId\norderCount: $orderCount\npaymentAmount: $paymentAmount\ndiscountAmount: $discountAmount\npaymentType: $paymentType\nkioskId: $kioskId\nisDetailLoaded: $isDetailLoaded\nmenus: $menus';
  }

  // 상태 업데이트된 새 OrderModel 반환
  OrderModel copyWith({
    String? orderNo,
    String? shopOrderNo,
    String? displayOrderNo,
    String? orderStatus,
    DateTime? orderedAt,
    double? totalAmount,
    OrderStatus? status,
    String? storeId,
    String? userId,
    String? customerName,
    String? tel,
    String? note,
    String? userName,
    String? storeName,
    String? ordererName,
    String? orderCount,
    double? paymentAmount,
    double? discountAmount,
    String? paymentType,
    String? paymentCode,
    DateTime? paidAt,
    List<OrderMenuModel>? menus,
    DateTime? updateTime,
    String? kioskId,
    String? source,
    String? orderType,
    int? kdsOrderType,
    bool? isDetailLoaded,
    List<OrderPaymentModel>? payments,
    List<OrderDiscountModel>? discounts,
    String? userBarcode,
  }) {
    // menus가 변경되면 캐시 초기화
    if (menus != null) {
      _clearSpecialProductCache();
    }

    return OrderModel(
        orderNo: orderNo ?? this.orderNo,
        shopOrderNo: shopOrderNo ?? this.shopOrderNo,
        displayOrderNo: displayOrderNo ?? this.displayOrderNo,
        orderStatus: orderStatus ?? this.orderStatus,
        orderedAt: orderedAt ?? this.orderedAt,
        totalAmount: totalAmount ?? this.totalAmount,
        status: status ?? this.status,
        storeId: storeId ?? this.storeId,
        userId: userId ?? this.userId,
        customerName: customerName ?? this.customerName,
        tel: tel ?? this.tel,
        note: note ?? this.note,
        userName: userName ?? this.userName,
        storeName: storeName ?? this.storeName,
        ordererName: ordererName ?? this.ordererName,
        orderCount: orderCount ?? this.orderCount,
        paymentAmount: paymentAmount ?? this.paymentAmount,
        discountAmount: discountAmount ?? this.discountAmount,
        paymentType: paymentType ?? this.paymentType,
        paymentCode: paymentCode ?? this.paymentCode,
        paidAt: paidAt ?? this.paidAt,
        menus: menus ?? this.menus,
        updateTime: updateTime ?? this.updateTime,
        kioskId: kioskId ?? this.kioskId,
        source: source ?? this.source,
        orderType: orderType ?? this.orderType,
        kdsOrderType: kdsOrderType ?? this.kdsOrderType,
        isDetailLoaded: isDetailLoaded ?? this.isDetailLoaded,
        payments: payments ?? this.payments,
        discounts: discounts ?? this.discounts,
        userBarcode: userBarcode ?? this.userBarcode);
  }

  // 두 주문의 최신 여부 비교
  bool isNewerThan(OrderModel other) {
    // 같은 주문인지 확인
    if (orderNo != other.orderNo) return false;

    // 업데이트 시간 비교
    return updateTime.isAfter(other.updateTime);
  }

  // 빈 주문 모델 생성을 위한 팩토리 메서드
  factory OrderModel.empty() => OrderModel(
        orderNo: '',
        shopOrderNo: '',
        orderStatus: '',
        orderedAt: DateTime.now(),
        totalAmount: 0,
        status: OrderStatus.CANCELLED,
        storeId: '',
        userId: '',
        ordererName: '',
        orderCount: '0',
        paymentAmount: 0,
        discountAmount: 0,
        paymentType: '',
        paymentCode: '',
        menus: [],
        kioskId: '',
        source: '',
        orderType: 'T',
        kdsOrderType: 0,
        isDetailLoaded:
            true, // 빈 객체는 보통 로딩 완료된 상태로 취급 (또는 false?) - 로직에 따라 다름. 일단 true.
      );

  SpecialProductType? _cachedSpecialProductType;

  // 구 유형 판별 (메뉴 및 옵션 전체 스캔)
  SpecialProductType detectSpecialProductType() {
    if (_cachedSpecialProductType != null) {
      return _cachedSpecialProductType!;
    }

    // orderType 기반 우선 판별 — 상세(menus) 없이 목록의 orderType 필드만으로 매장/포장을
    // 판별한다. 메인 모드 카드는 상세를 프리페치하지 않으므로 이 경로로 프리픽스를 표시한다.
    // AppFit 신규: IN_SHOP/TAKE_OUT, 레거시(키오스크): H/T/C.
    if (orderType.isNotEmpty) {
      switch (orderType) {
        case 'T':
        case 'TAKE_OUT':
          _cachedSpecialProductType = SpecialProductType.takeout;
          break;
        case 'H':
        case 'IN_SHOP':
          _cachedSpecialProductType = SpecialProductType.dineIn;
          break;
        case 'C':
          _cachedSpecialProductType = SpecialProductType.both;
          break;
        default:
          _cachedSpecialProductType = SpecialProductType.none;
      }
      return _cachedSpecialProductType!;
    }

    // orderType 이 빈 값 → 상세(menus)의 메모/상품코드로 판별 (상세 로드 후에만 정확).
    if (orderMenuList.isEmpty) {
      _cachedSpecialProductType = SpecialProductType.none;
      return _cachedSpecialProductType!;
    }

    bool hasDineIn = false;
    bool hasTakeout = false;

    //메모 문구로 판별
    List<String> _takeoutMemo = ['테이크아웃', '포장'];
    List<String> _dineInMemo = ['먹고갈게요', '매장'];
    String specialMemo = note ?? '';
    if (specialMemo.isNotEmpty) {
      if (_dineInMemo.any((element) => specialMemo.contains(element))) {
        hasDineIn = true;
      }
      if (_takeoutMemo.any((element) => specialMemo.contains(element))) {
        hasTakeout = true;
      }
    } else {
      _cachedSpecialProductType = SpecialProductType.none;
    }

    if (storeId.toLowerCase().startsWith('k064')) {
      //밀키프레소인경우 상품코드로 다시 판별
      // none: 해당 없음, dineIn: 매장, takeout: 포장, both: 매장+포장
      // 코드 매핑: '000101' ↔ 매장, '000103' ↔ 포장 (요구사항 기준 가정)
      String dineInCodeForAmericano = '000101';
      String takeoutCodeForAmericano = '000102';
      String dineInCode = '000103';
      String takeoutCode = '000104';

      for (final menu in orderMenuList) {
        // 메뉴 상품코드는 보지 않고, 옵션 상품코드만 체크
        for (final option in menu.options) {
          final opt = option.shopOptionId;
          if (opt == dineInCode || opt == dineInCodeForAmericano) {
            hasDineIn = true;
          } else if (opt == takeoutCode || opt == takeoutCodeForAmericano) {
            hasTakeout = true;
          }
        }
        if (hasDineIn && hasTakeout) {
          _cachedSpecialProductType = SpecialProductType.both;
          return _cachedSpecialProductType!;
        }
      }

      _cachedSpecialProductType = hasDineIn
          ? SpecialProductType.dineIn
          : (hasTakeout ? SpecialProductType.takeout : SpecialProductType.none);
    }

    _cachedSpecialProductType ??= SpecialProductType.none;
    return _cachedSpecialProductType!;
  }

  // 이전 캐시 초기화 메서드 변경 (유형 캐시 초기화)
  void _clearSpecialProductCache() {
    _cachedSpecialProductType = null;
  }

  // 프리픽스 계산 (매장/포장/매장+포장)
  String getOrderPrefix() {
    // storeId가 비어있거나 null인 경우 처리
    if (storeId.isEmpty) {
      return '';
    }

    final type = detectSpecialProductType();
    switch (type) {
      case SpecialProductType.both:
        return '복합';
      case SpecialProductType.dineIn:
        return '매장';
      case SpecialProductType.takeout:
        return '포장';
      case SpecialProductType.none:
        // 기존 로직 유지: 스페셜코드가 없으면 '포장'
        return '';
    }
  }

  // 비교 키에서 제외:
  //  - userName/storeName: non-final (mutable)
  //  - _cachedSpecialProductType: 내부 캐시
  //  - exceptTaxPrice/taxPrice: paymentAmount 파생값
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is OrderModel &&
        orderNo == other.orderNo &&
        shopOrderNo == other.shopOrderNo &&
        displayOrderNo == other.displayOrderNo &&
        orderStatus == other.orderStatus &&
        status == other.status &&
        orderedAt == other.orderedAt &&
        updateTime == other.updateTime &&
        totalAmount == other.totalAmount &&
        paymentAmount == other.paymentAmount &&
        discountAmount == other.discountAmount &&
        paymentType == other.paymentType &&
        paymentCode == other.paymentCode &&
        paidAt == other.paidAt &&
        note == other.note &&
        orderCount == other.orderCount &&
        ordererName == other.ordererName &&
        kioskId == other.kioskId &&
        source == other.source &&
        orderType == other.orderType &&
        kdsOrderType == other.kdsOrderType &&
        isDetailLoaded == other.isDetailLoaded &&
        storeId == other.storeId &&
        userId == other.userId &&
        customerName == other.customerName &&
        tel == other.tel &&
        userBarcode == other.userBarcode &&
        listEquals(payments, other.payments) &&
        listEquals(discounts, other.discounts) &&
        listEquals(menus, other.menus);
  }

  @override
  int get hashCode => Object.hash(
        orderNo,
        status,
        orderStatus,
        updateTime,
        paymentAmount,
        discountAmount,
        orderCount,
        kdsOrderType,
        isDetailLoaded,
        source,
        Object.hash(
          paymentType,
          paymentCode,
          paidAt,
          note,
          ordererName,
          orderType,
          storeId,
          userId,
          Object.hashAll(menus),
          // Object.hash 는 인자 20개가 상한이고 바깥/안쪽 모두 10개로 만석이라
          // 상세 전용 필드는 한 단계 더 중첩해서 넣는다.
          Object.hash(
            Object.hashAll(payments),
            Object.hashAll(discounts),
            userBarcode,
          ),
        ),
      );
}

// 스페셜 코드 유형 정의
enum SpecialProductType { none, dineIn, takeout, both }

// 주문 출처 대분류
enum OrderSourceType { app, kiosk, pos }

/// 주문 출처 문자열을 대분류로 변환한다.
/// '_KIOSK' 접미사 → kiosk, '_POS' 접미사 → pos, 그 외(WALD_APPFIT, WALD_CAMO 등) → app.
OrderSourceType classifyOrderSource(String source) {
  if (source.endsWith('_KIOSK')) return OrderSourceType.kiosk;
  if (source.endsWith('_POS')) return OrderSourceType.pos;
  return OrderSourceType.app;
}
