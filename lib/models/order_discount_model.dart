/// 주문에 적용된 **할인 1건**. `/v1/orders/{orderNo}` 응답의
/// `discounts[]`(`OrderDiscountV1Response`) 원소에 대응한다.
/// 구버전 응답에서는 배열 키가 `orderDiscounts` 였다.
///
/// 과거에는 `discountType` 문자열만 뽑아 쓰고 [discountAmount] 를 버렸다.
class OrderDiscountModel {
  /// COUPON / POINT / GIFT / PARTNER / MEMBERSHIP / EMPLOYEE / PRE_PAYMENT / SHOP.
  /// 라벨 변환은 `payment_label_util.dart` 의 `discountTypeLabel` 사용.
  final String discountType;
  final double discountAmount;

  /// ORDER(주문 전체) / ITEM(특정 라인). ITEM 할인은 `orderLines[].discPrc` 에도
  /// 반영돼 있어 이중으로 보일 수 있으나, 현재는 필터링하지 않고 전부 나열한다.
  final String discountScope;

  final String? couponNo;

  /// 쿠폰명("1,000원 할인권" 등). 있으면 할인 종류 옆에 괄호로 덧붙인다.
  final String? couponName;

  const OrderDiscountModel({
    required this.discountType,
    required this.discountAmount,
    required this.discountScope,
    this.couponNo,
    this.couponName,
  });

  factory OrderDiscountModel.fromJson(Map<String, dynamic> json) {
    return OrderDiscountModel(
      discountType: json['discountType']?.toString() ?? '',
      discountAmount:
          double.tryParse(json['discountAmount']?.toString() ?? '0') ?? 0.0,
      discountScope: json['discountScope']?.toString() ?? '',
      couponNo: json['couponNo']?.toString(),
      couponName: json['couponName']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'discountType': discountType,
      'discountAmount': discountAmount,
      'discountScope': discountScope,
      if (couponNo != null) 'couponNo': couponNo,
      if (couponName != null) 'couponName': couponName,
    };
  }

  @override
  String toString() => 'OrderDiscountModel($discountType/$discountScope, '
      '$discountAmount${couponName != null ? ', $couponName' : ''})';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is OrderDiscountModel &&
        discountType == other.discountType &&
        discountAmount == other.discountAmount &&
        discountScope == other.discountScope &&
        couponNo == other.couponNo &&
        couponName == other.couponName;
  }

  @override
  int get hashCode => Object.hash(
      discountType, discountAmount, discountScope, couponNo, couponName);
}
