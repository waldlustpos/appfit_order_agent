import 'package:intl/intl.dart';

class CommonUtil {
  static String formatPrice(dynamic price, {String currencyUnit = '¥'}) {
    final NumberFormat currencyFormat = NumberFormat.currency(
      locale: 'ja_JP',
      symbol: '',
      decimalDigits: 0,
    );

    return '${currencyFormat.format(price)}$currencyUnit';
  }

  /// 뒤 [visible]자리만 노출하고 앞을 마스킹. 길이가 모자라면(빈 문자열 포함) 전체 마스킹.
  /// 전화번호/회원바코드 로그용. 쿠폰번호에는 사용하지 않는다(정책상 원문 유지).
  static String maskTail(String value, {int visible = 4}) {
    if (value.length <= visible) return '*******';
    return '*******${value.substring(value.length - visible)}';
  }

  /// 카드번호 표시용 마스킹. 앞 4자리(BIN 일부)만 남긴다: `5327111122223333` → `5327-****`.
  ///
  /// 서버가 이미 마스킹해 보내면(`*` 포함) 원문을 그대로 둔다. 자릿수가 4 이하면
  /// 마스킹할 게 없으므로 원문 유지. 결제 응답을 모델에 담는 시점에 적용해서
  /// 원본 PAN 이 앱 메모리·프린터 페이로드·로그 어디에도 남지 않게 한다.
  static String maskCardNo(String value) {
    if (value.contains('*')) return value;
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length <= 4) return value;
    return '${digits.substring(0, 4)}-****';
  }
}
