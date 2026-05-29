import 'package:flutter/material.dart';

/// 앱 브랜드 테마. 세션당 하나가 활성화되며 `AppStyles.applyBrand` 로 부팅 시 1회 반영.
enum BrandTheme {
  appfitDefault(
    id: 'appfit_default',
    primary: Color(0xFFfb3e7e),
    primaryAlpha: Color(0x14fb3e7e),
    loginBackground: Color(0xFFfb3e7e),
    onLoginBackground: Colors.white,
    logoAsset: null,
    loginGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFfb3e7e), Color(0xFF9843cb)],
    ),
  ),
  mammothCoffee(
    id: 'mammoth_coffee',
    primary: Color(0xFF4A3730),
    primaryAlpha: Color(0x144A3730),
    loginBackground: Color(0xFF5B443B),
    onLoginBackground: Color(0xFFfcfaf8),
    logoAsset: 'assets/images/brand/mammoth/logo.svg',
    loginGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF5B443B), Color(0xFFC7A79B)],
    ),
  ),
  // 마하테이스트(mahataste) 브랜드 색상(#E31F26).
  //   logo.svg 배치 후 logoAsset 지정 가능.
  mata(
    id: 'mata',
    primary: Color(0xFFe31f26),
    primaryAlpha: Color(0x14e31f26),
    loginBackground: Color(0xFFe31f26),
    onLoginBackground: Colors.white,
    logoAsset: null,
    loginGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFe31f26), Color(0xFF9e1418)],
    ),
  );

  const BrandTheme({
    required this.id,
    required this.primary,
    required this.primaryAlpha,
    required this.loginBackground,
    required this.onLoginBackground,
    required this.logoAsset,
    required this.loginGradient,
  });

  final String id;
  final Color primary;
  final Color primaryAlpha;

  /// 로그인 화면 단색 배경 (loginGradient 가 null 일 때 사용).
  final Color loginBackground;
  final Color onLoginBackground;

  /// 로그인 화면 배경 그라데이션. null 이면 loginBackground(단색) 사용.
  final Gradient? loginGradient;
  final String? logoAsset;

  static BrandTheme fromId(String? id) => BrandTheme.values.firstWhere(
        (t) => t.id == id,
        orElse: () => BrandTheme.appfitDefault,
      );
}
