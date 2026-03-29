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
}
