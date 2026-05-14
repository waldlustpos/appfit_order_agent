import '../services/preference_service.dart';

/// 매장 ID prefix에 따라 인쇄용 로고 자원 경로를 결정한다.
///
/// - TPCP… → tokyoplatz: 라벨 로고만 사용, 영수증 로고 없음
/// - MHST… → mammoth: 라벨/영수증 모두 mammoth 자원
/// - 그 외/미로그인 → tokyoplatz 자원으로 fallback (라벨), 영수증 null
///
/// 호출부는 매번 getter를 읽고 캐시된 path와 비교(lazy invalidation)하므로
/// 로그아웃/매장 전환 시 별도 후크 없이 자동 재로드된다.
class BrandAssets {
  BrandAssets._();

  static const String _tokyoplatzLabelLogo =
      'assets/images/brand/tokyoplatz_label_logo.bmp';
  static const String _mammothLabelLogo =
      'assets/images/brand/mammoth_label_logo.bmp';
  static const String _mammothReceiptLogo =
      'assets/images/brand/mammoth_receipt_logo.png';

  static String get labelLogoPath {
    return _isMammoth() ? _mammothLabelLogo : _tokyoplatzLabelLogo;
  }

  static String get labelLogoFallbackPath => _tokyoplatzLabelLogo;

  static String? get receiptLogoPath {
    return _isMammoth() ? _mammothReceiptLogo : null;
  }

  static bool _isMammoth() {
    return PreferenceService().isMammothStore();
  }
}
