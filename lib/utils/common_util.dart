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
}
