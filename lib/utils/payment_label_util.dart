/// 서버가 내려주는 결제/할인/현금영수증 코드값을 화면 표시용 라벨로 바꾼다.
///
/// 위젯에 의존하지 않으므로(=`Translations` 만 받는다) 위젯 pump 없이 단위
/// 테스트할 수 있고, 주문 상세 팝업 밖(영수증 등)에서도 그대로 재사용 가능하다.
///
/// **미지의 코드는 원문을 그대로 돌려준다.** 서버가 enum 을 늘렸을 때 빈 칸이
/// 뜨는 것보다 원문 코드라도 보이는 편이 현장에서 진단 가능하다.
library;

import 'package:appfit_order_agent/i18n/strings.g.dart';

/// `payments[].paymentMethod` / 상위 `paymentMethod` 코드 → 라벨.
///
/// 서버 enum 28종 + 레거시 키오스크 값(`CARD`, `SERVICE`)을 커버한다.
/// 과거 정보 패널의 매퍼는 `FREE`/빈 값에 null 을 돌려 행을 숨겼지만, 이제는
/// 결제수단별 금액을 나열하므로 `FREE` 건도 금액과 함께 보여야 한다.
/// 따라서 **절대 null 을 반환하지 않는다.**
String paymentMethodLabel(Translations t, String method) {
  final m = t.order.payment_method;
  switch (method.toUpperCase()) {
    case 'CREDIT_CARD':
    case 'CARD': // 레거시 키오스크
      return m.credit_card;
    case 'PREPAID_CARD':
      return m.prepaid_card;
    case 'FREE':
      return m.free;
    case 'NAVER_PAY':
      return m.naver_pay;
    case 'KAKAO_PAY':
      return m.kakao_pay;
    case 'TOSS_PAY':
      return m.toss_pay;
    case 'TOSS_PAY_DIRECT':
      return m.toss_pay_direct;
    case 'APPLE_PAY':
      return m.apple_pay;
    case 'PAYCO':
      return m.payco;
    case 'EASY_CARD':
      return m.easy_card;
    case 'MOBILE_PAYMENT':
      return m.mobile_payment;
    case 'KB_PAY':
      return m.kb_pay;
    case 'HANA_PAY':
      return m.hana_pay;
    case 'WOORI_PAY':
      return m.woori_pay;
    case 'FELICA_TRANSPORTATION':
      return m.felica_transportation;
    case 'FELICA_ID':
      return m.felica_id;
    case 'FELICA_QUICPAY':
      return m.felica_quicpay;
    case 'QR_PAYMENT':
      return m.qr_payment;
    case 'GIFT':
      return m.gift;
    case 'CASH':
      return m.cash;
    case 'APP_CARD':
      return m.app_card;
    case 'ZERO_PAY':
      return m.zero_pay;
    case 'KARROT_PAY':
      return m.karrot_pay;
    case 'BANK_TRANSFER':
      return m.bank_transfer;
    case 'LOCAL_CURRENCY':
      return m.local_currency;
    case 'EASY_PAYMENT':
      return m.easy_payment;
    case 'MULTI':
      return m.multi;
    case 'OTHER':
      return m.other;
    case 'SERVICE': // 레거시 키오스크
      return m.service;
    default:
      return method;
  }
}

/// `discounts[].discountType` 코드 → 라벨. 서버 enum 8종.
String discountTypeLabel(Translations t, String type) {
  final d = t.order.discount_type;
  switch (type.toUpperCase()) {
    case 'COUPON':
      return d.coupon;
    case 'POINT':
      return d.point;
    case 'GIFT':
      return d.gift;
    case 'PARTNER':
      return d.partner;
    case 'MEMBERSHIP':
      return d.membership;
    case 'EMPLOYEE':
      return d.employee;
    case 'PRE_PAYMENT':
      return d.pre_payment;
    case 'SHOP':
      return d.shop;
    default:
      return type;
  }
}
