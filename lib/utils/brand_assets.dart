import '../services/preference_service.dart';

/// 매장 ID prefix → 브랜드 키 매핑.
///
/// 새 브랜드 추가는 3단계로 단순화된다:
///   1. `assets/images/brand/<slug>/` 폴더에 표준 파일명으로 자산 배치
///      (`label_logo.bmp`, 선택적으로 `receipt_logo.png`, `logo.svg`)
///   2. `pubspec.yaml` 의 assets 에 새 폴더 경로 추가
///   3. 본 파일에 `BrandKey` enum 값과 `_brands` Map 한 줄,
///      `_resolveBrand()` if 한 줄 추가 (+ PreferenceService 헬퍼 필요 시)
///
/// 호출부는 매번 getter 를 읽고 캐시된 path 와 비교 (lazy invalidation) 하므로
/// 로그아웃/매장 전환 시 별도 후크 없이 자동 재로드된다.
enum BrandKey { tpcp, mhst }

class BrandAssetSet {
  const BrandAssetSet({
    required this.folder,
    this.hasReceiptLogo = false,
  });

  final String folder;
  final bool hasReceiptLogo;

  String get _base => 'assets/images/brand/$folder';
  String get labelLogo => '$_base/label_logo.bmp';
  String? get receiptLogo => hasReceiptLogo ? '$_base/receipt_logo.png' : null;
  String get themeLogo => '$_base/logo.svg';
}

class BrandAssets {
  BrandAssets._();

  static const BrandKey _fallback = BrandKey.tpcp;

  static const Map<BrandKey, BrandAssetSet> _brands = {
    BrandKey.tpcp: BrandAssetSet(folder: 'tokyoplatz'),
    BrandKey.mhst: BrandAssetSet(folder: 'mammoth', hasReceiptLogo: true),
  };

  static BrandAssetSet _current() =>
      _brands[_resolveBrand()] ?? _brands[_fallback]!;

  static BrandKey? _resolveBrand() {
    final id = PreferenceService().getId();
    if (PreferenceService.isMHSTStoreId(id)) return BrandKey.mhst;
    if (PreferenceService.isTPCPStoreId(id)) return BrandKey.tpcp;
    return null;
  }

  static String get labelLogoPath => _current().labelLogo;
  static String get labelLogoFallbackPath => _brands[_fallback]!.labelLogo;
  static String? get receiptLogoPath => _current().receiptLogo;
}
