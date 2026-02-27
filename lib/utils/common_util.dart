import 'package:intl/intl.dart';

class CommonUtil {
  static String formatPrice(dynamic price) {
    final NumberFormat currencyFormat = NumberFormat.currency(
      locale: 'ko_KR',
      symbol: '',
      decimalDigits: 0,
    );

    return '${currencyFormat.format(price)}원';
  }
}
