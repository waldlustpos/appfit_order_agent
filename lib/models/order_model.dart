import 'order_menu_model.dart';
import 'package:intl/intl.dart';
import 'package:kokonut_order_agent/utils/logger.dart';
import '../utils/kds_utils.dart' as kds_utils;
import 'enums/order_status.dart';

export 'enums/order_status.dart';

class OrderModel {
  final String orderNo; // ordrId -> orderNo
  final String shopOrderNo; // ordrSimpleId -> shopOrderNo
  // displayNum removed, use shopOrderNo
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
  final String orderType; // 키오스크 주문 타입 (T, H, C)
  final int kdsOrderType; // KDS에서 사용하는 주문 타입 (1: 간단, 2: 복잡)
  final bool isDetailLoaded; // 상세 정보 로딩 여부

  OrderModel({
    required this.orderNo,
    required this.shopOrderNo,
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
    bool? isDetailLoaded,
  })  : updateTime = updateTime ?? DateTime.now(),
        // 메뉴가 있으면 기본적으로 로딩된 것으로 간주, 명시적 값 있으면 그것 사용
        isDetailLoaded = isDetailLoaded ?? (menus.isNotEmpty),
        exceptTaxPrice = _calculateExceptTaxPrice(paymentAmount),
        taxPrice = _calculateTaxPrice(paymentAmount);

  // Getter for displayNum compatibility/logic
  String get displayNum => shopOrderNo.padLeft(3, '0');
  String get orderId => orderNo;
  List<OrderMenuModel> get orderMenuList => menus;
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
    // 주문 상태 코드를 OrderStatus enum으로 변환
    OrderStatus parseStatus(String statusCode) {
      switch (statusCode) {
        case '2003':
          return OrderStatus.NEW;
        case '2007':
          return OrderStatus.PREPARING;
        case '2009':
          return OrderStatus.READY;
        case '2020':
          return OrderStatus.DONE;
        case '9001':
          return OrderStatus.CANCELLED;
        case '2099':
          return OrderStatus.CANCELLED; // 미픽업 -> 취소 처리
        case '9999':
          return OrderStatus.CANCELLED;
        case 'NEW':
          return OrderStatus.NEW;
        case 'ACCEPTED':
          return OrderStatus.PREPARING;
        case 'PICKUP_REQUESTED':
          return OrderStatus.READY;
        case 'CANCELED':
          return OrderStatus.CANCELLED;
        case 'COMPLETED':
          return OrderStatus.DONE;
        default:
          logger.w(
              'Unknown order status code found: $statusCode, mapping to CANCELLED.');
          return OrderStatus.CANCELLED;
      }
    }

    // 주문 메뉴 목록 파싱
    List<OrderMenuModel> menus = [];
    // Handle both 'menus' (AppFit) and 'ordrPrdList' (Internal/Legacy) keys
    var menuListRaw = json['menus'];
    if (menuListRaw != null) {
      try {
        menus = List<OrderMenuModel>.from(
            (menuListRaw as List).map((x) => OrderMenuModel.fromJson(x)));
      } catch (e, s) {
        logger.e('Error parsing menu list', error: e, stackTrace: s);
      }
    }

    // Mapping fields
    String _orderNo = (json['orderNo'])?.toString() ?? '';
    String _shopOrderNo = (json['shopOrderNo'])?.toString() ?? '';
    String _displayOrderNum =
        (json['displayOrderNum'])?.toString() ?? _shopOrderNo;
    String _orderStatus = (json['orderStatus'])?.toString() ?? '';
    DateTime _orderedAt =
        DateTime.tryParse(json['orderedAt'] ?? '') ?? DateTime.now();
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
    DateTime? _paidAt = DateTime.tryParse(json['paidAt'] ?? '');

    final tempOrder = OrderModel(
      orderNo: _orderNo,
      shopOrderNo: _shopOrderNo.isNotEmpty
          ? _shopOrderNo
          : _displayOrderNum, // Use display num if shopOrderNo is empty
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
      orderType: json['orderType'] ?? json['order_type'] ?? '',
      kdsOrderType: 0, // 임시값
      updateTime: DateTime.tryParse(json['updateTime'] ?? '') ?? DateTime.now(),
      kioskId: (json['kioskId'])?.toString() ?? '',
      isDetailLoaded:
          json['isDetailLoaded'] ?? (menus.isNotEmpty), // JSON에 없으면 메뉴 유무로 판단
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
      'displayOrderNum': displayNum, // Keep for legacy systems if needed
      'ordrSimpleId': shopOrderNo, // Sunmi 호환용 추가
      'orderedAt': DateFormat('yyyy-MM-dd HH:mm:ss').format(orderedAt),
      'ordrDtm':
          DateFormat('yyyy-MM-dd HH:mm:ss').format(orderedAt), // Sunmi 호환용 추가
      'totalAmount': NumberFormat('#,###').format(totalAmount),
      'orderStatus': orderStatus,
      'storeId': storeId,
      'userId': userId,
      'customerName': customerName,
      'tel': tel,
      'note': note,
      'ordrMemo': note, // Sunmi 호환용 추가
      'userName': userName,
      'storeName': storeName,
      'ordererName': ordererName,
      'orderCount': orderCount,
      'paymentAmount': NumberFormat('#,###').format(paymentAmount),
      'discountAmount': NumberFormat('#,###').format(discountAmount),
      'paymentType': paymentType,
      'paymentCode': paymentCode,
      'paidAt': paidAt != null
          ? DateFormat('yyyy-MM-dd HH:mm:ss').format(paidAt!)
          : null,
      'menus': menus.map((menu) => menu.toJson()).toList(),
      'ordrPrdList':
          menus.map((menu) => menu.toJson()).toList(), // Sunmi 호환용 추가
      'exceptTaxPrice': NumberFormat('#,###').format(exceptTaxPrice),
      'taxPrice': NumberFormat('#,###').format(taxPrice),
      'kioskId': kioskId,

      'orderType': orderType,
      'kdsOrderType': kdsOrderType,
      'isDetailLoaded': isDetailLoaded,
    };
  }

  // 주문 총액 계산 (모든 메뉴와 옵션 포함)
  double get calculatedTotalAmount {
    return menus.fold(0, (sum, menu) => sum + menu.totalPrice);
  }

  String toString() {
    return 'orderNo: $orderNo\nshopOrderNo: $shopOrderNo\ndisplayNum: $displayNum\norderStatus: $orderStatus\norderedAt: $orderedAt\ntotalAmount: $totalAmount\nstatus: $status\norderStatus: $orderStatus\nstoreId: $storeId\nuserName: $userName\nnote: $note\nuserId: $userId\norderCount: $orderCount\npaymentAmount: $paymentAmount\ndiscountAmount: $discountAmount\npaymentType: $paymentType\nkioskId: $kioskId\nisDetailLoaded: $isDetailLoaded\nmenus: $menus';
  }

  // 상태 업데이트된 새 OrderModel 반환
  OrderModel copyWith({
    String? orderNo,
    String? shopOrderNo,
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
    String? orderType,
    int? kdsOrderType,
    bool? isDetailLoaded,
  }) {
    // menus가 변경되면 캐시 초기화
    if (menus != null) {
      _clearSpecialProductCache();
    }

    return OrderModel(
        orderNo: orderNo ?? this.orderNo,
        shopOrderNo: shopOrderNo ?? this.shopOrderNo,
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
        updateTime: updateTime ?? DateTime.now(),
        kioskId: kioskId ?? this.kioskId,
        orderType: orderType ?? this.orderType,
        kdsOrderType: kdsOrderType ?? this.kdsOrderType,
        isDetailLoaded: isDetailLoaded ?? this.isDetailLoaded);
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

    if (orderMenuList.isEmpty) {
      _cachedSpecialProductType = SpecialProductType.none;
      return _cachedSpecialProductType!;
    }

    bool hasDineIn = false;
    bool hasTakeout = false;

    //밀키프레소인경우 끝

    if (orderType.isNotEmpty) {
      if (orderType == 'T') {
        _cachedSpecialProductType = SpecialProductType.takeout;
      } else if (orderType == 'H') {
        _cachedSpecialProductType = SpecialProductType.dineIn;
      } else if (orderType == 'C') {
        _cachedSpecialProductType = SpecialProductType.both;
      } else {
        _cachedSpecialProductType = SpecialProductType.none;
      }
    } else {
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
        // ... (existing k064 logic)
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
            : (hasTakeout
                ? SpecialProductType.takeout
                : SpecialProductType.none);
      }
    }

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
}

// 스페셜 코드 유형 정의
enum SpecialProductType { none, dineIn, takeout, both }
