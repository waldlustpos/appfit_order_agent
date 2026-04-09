import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:appfit_order_agent/i18n/strings.g.dart';
import 'package:appfit_order_agent/services/preference_service.dart';
import 'package:appfit_order_agent/utils/logger.dart';

part 'locale_provider.g.dart';

@Riverpod(keepAlive: true)
class LocaleNotifier extends _$LocaleNotifier {
  @override
  AppLocale build() {
    // 1. 저장된 언어 확인
    final savedLocale = PreferenceService().getLocale();
    if (savedLocale != null) {
      try {
        final locale = AppLocale.values.firstWhere(
          (e) => e.languageCode == savedLocale,
          orElse: () => AppLocale.ko,
        );
        logger.i('[LocaleNotifier] 저장된 언어 로드: ${locale.languageCode}');

        // Slang 전역 설정 동기화 추가
        LocaleSettings.setLocale(locale);

        return locale;
      } catch (e, s) {
        logger.e('[LocaleNotifier] 저장된 언어 파싱 실패: $e');
      }
    }

    // 2. 저장된 언어가 없으면 시스템 언어 확인
    final deviceLocale = LocaleSettings.currentLocale;
    logger.i('[LocaleNotifier] 시스템 언어 감지: ${deviceLocale.languageCode}');

    return deviceLocale;
  }

  Future<void> changeLocale(AppLocale newLocale) async {
    state = newLocale;
    LocaleSettings.setLocale(newLocale);
    await PreferenceService().setLocale(newLocale.languageCode);
    logger.i('[LocaleNotifier] 언어 변경 및 저장: ${newLocale.languageCode}');
  }
}
