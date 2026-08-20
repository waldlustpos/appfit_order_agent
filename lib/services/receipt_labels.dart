import 'package:appfit_order_agent/i18n/strings.g.dart';

/// 영수증/주문서 출력에 쓰이는 고정 라벨을 현재 로캘 번역에서 평면 맵으로 추출.
///
/// Sunmi(Java) 는 Slang 에 접근할 수 없으므로, Dart 에서 이 맵을 만들어
/// `orderMap['labels']` 로 주입하면 [ReceiptEscPosBuilder] 와 `SunmiPrintHelper.java`
/// 가 동일한 라벨을 읽는다(번역 정본은 i18n JSON 한 곳). 키는 양쪽이 공유하며,
/// 라벨 누락 시 각 빌더가 한국어 literal 로 fallback 한다.
///
/// 테스트 페이지(`test_*`)와 라벨 페인터(`section_*`)는 `orderMap` 을 거치지 않고
/// 정적 `t` 를 직접 사용하므로 이 맵에 포함하지 않는다.
Map<String, String> buildReceiptLabels(Translations t) {
  final r = t.receipt;
  return {
    'cancel_receipt': r.cancel_receipt,
    'cancel_order': r.cancel_order,
    'order_no': r.order_no,
    'datetime': r.datetime,
    'col_menu': r.col_menu,
    'col_qty': r.col_qty,
    'col_amount': r.col_amount,
    'taxable': r.taxable,
    'vat': r.vat,
    'order_amount': r.order_amount,
    'discount_amount': r.discount_amount,
    'payment_amount': r.payment_amount,
    'kiosk': r.kiosk,
    'customer_suffix': r.customer_suffix,
    'type_dine_in': t.order.type_dine_in,
    'type_takeout': t.order.type_takeout,
  };
}
