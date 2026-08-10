import 'package:appfit_order_agent/utils/common_util.dart';

/// 주문 1건에 사용된 **결제수단 1건**. `/v1/orders/{orderNo}` 응답의
/// `payments[]`(`OrderPaymentV1Response`) 원소에 대응한다.
///
/// 복합결제(카드 7,000 + 현금 3,000)면 배열에 2건이 담기고, 상위 스칼라
/// `paymentMethod` 는 `MULTI` 로 내려온다. 부분취소 주문에서는 취소된 결제건이
/// 함께 내려올 수 있으므로 합계를 직접 계산하지 말고 각 행을 있는 그대로 표시한다.
///
/// **서버가 주는 필드 중 일부만 담는다.** `approvalNo`/`txDate`/`transactionId`/
/// `payDetail`/`couponType` 은 화면에 쓰지 않기로 해서 의도적으로 뺐다. 특히
/// 날짜·object 필드를 만들지 않는 것이 중요한데, [OrderModel.toSunmiJson] 이
/// `toJson()` 을 스프레드해 `jsonEncode` 로 네이티브 프린터에 넘어가기 때문이다
/// (primitive 가 아닌 값이 섞이면 영수증이 통째로 안 나온다).
class OrderPaymentModel {
  /// 서버 enum 28종 중 하나(CREDIT_CARD, CASH, KAKAO_PAY, MULTI …).
  /// 라벨 변환은 `payment_label_util.dart` 의 `paymentMethodLabel` 사용.
  final String paymentMethod;
  final double amount;

  /// 스키마에 enum 이 선언돼 있지 않다. 상위 `paymentStatus` 와 같은 값 계열
  /// (DONE/PENDING/FAILED/FULL_CANCELLED/PARTIAL_CANCELLED)로 보이지만 보장은 없다.
  ///
  /// **UI 에는 쓰지 않는다** — 주문이 취소면 결제도 취소라는 전제가 성립해서
  /// 주문 상태 배지와 중복이다. 상세 로그·디버깅용으로만 보관한다.
  final String status;

  /// 카드사명(신한, 국민 …). 간편결제는 보통 비어 있고 [vendor] 가 채워진다.
  final String? cardName;

  /// **마스킹된** 카드번호. [OrderPaymentModel.fromJson] 이 원본을 절대 보관하지
  /// 않는다 — 모델이 PAN 을 들고 있으면 toJson→프린터 페이로드로 새어나간다.
  final String? cardNo;

  /// 할부 개월. 0 또는 1 이면 일시불.
  final int? installment;

  /// 선불카드 결제 후 잔액.
  final double? balance;

  /// 결제 대행사/브랜드 식별자. [cardName] 이 없을 때 2번째 줄 폴백으로 쓴다.
  final String? vendor;

  const OrderPaymentModel({
    required this.paymentMethod,
    required this.amount,
    required this.status,
    this.cardName,
    this.cardNo,
    this.installment,
    this.balance,
    this.vendor,
  });

  factory OrderPaymentModel.fromJson(Map<String, dynamic> json) {
    final rawCardNo = json['cardNo']?.toString();
    return OrderPaymentModel(
      paymentMethod: json['paymentMethod']?.toString() ?? '',
      amount: double.tryParse(json['amount']?.toString() ?? '0') ?? 0.0,
      status: json['status']?.toString() ?? '',
      cardName: json['cardName']?.toString(),
      // 저장 시점에 마스킹 — 모델은 원본 카드번호를 보유하지 않는다.
      cardNo: (rawCardNo == null || rawCardNo.isEmpty)
          ? null
          : CommonUtil.maskCardNo(rawCardNo),
      installment: int.tryParse(json['installment']?.toString() ?? ''),
      balance: double.tryParse(json['balance']?.toString() ?? ''),
      vendor: json['vendor']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'paymentMethod': paymentMethod,
      'amount': amount,
      'status': status,
      if (cardName != null) 'cardName': cardName,
      if (cardNo != null) 'cardNo': cardNo,
      if (installment != null) 'installment': installment,
      if (balance != null) 'balance': balance,
      if (vendor != null) 'vendor': vendor,
    };
  }

  @override
  String toString() => 'OrderPaymentModel($paymentMethod, $amount, $status'
      '${cardName != null ? ', $cardName' : ''}'
      '${cardNo != null ? ' $cardNo' : ''})';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is OrderPaymentModel &&
        paymentMethod == other.paymentMethod &&
        amount == other.amount &&
        status == other.status &&
        cardName == other.cardName &&
        cardNo == other.cardNo &&
        installment == other.installment &&
        balance == other.balance &&
        vendor == other.vendor;
  }

  @override
  int get hashCode => Object.hash(paymentMethod, amount, status, cardName,
      cardNo, installment, balance, vendor);
}
