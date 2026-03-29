import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:appfit_order_agent/i18n/strings.g.dart';
import 'package:appfit_order_agent/providers/locale_provider.dart';
import 'package:appfit_order_agent/services/preference_service.dart';
import 'package:appfit_order_agent/utils/currency_unit.dart';
import 'package:appfit_order_agent/utils/logger.dart';

part 'currency_provider.g.dart';

@Riverpod(keepAlive: true)
class CurrencyNotifier extends _$CurrencyNotifier {
  @override
  CurrencyUnit build() {
    final saved = PreferenceService().getCurrency();
    logger.i('[CurrencyNotifier] 화폐단위 로드: ${saved.name}');
    return saved;
  }

  Future<void> changeCurrency(CurrencyUnit unit) async {
    state = unit;
    await PreferenceService().setCurrency(unit);
    logger.i('[CurrencyNotifier] 화폐단위 변경 및 저장: ${unit.name}');
  }
}

/// 현재 언어 + 화폐단위 설정에 따라 표시할 통화 기호 문자열을 반환합니다.
/// - KRW 선택 시: "원" (언어 무관)
/// - JPY 선택 시: 일본어 → "円", 그 외 → "¥"
@Riverpod(keepAlive: true)
String currencySymbol(Ref ref) {
  final currency = ref.watch(currencyNotifierProvider);
  final locale = ref.watch(localeNotifierProvider);
  if (currency == CurrencyUnit.krw) return '원';
  return locale == AppLocale.ja ? '円' : '¥';
}
