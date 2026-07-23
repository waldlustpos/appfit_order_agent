import 'package:flutter/foundation.dart';

import 'package:appfit_order_agent/constants/brand_theme.dart';
import 'package:appfit_order_agent/utils/currency_unit.dart';

/// 브랜드별 커스텀 기능(capability) 플래그.
///
/// 게이팅(UI show/hide·로직 enable/disable)을 `brand.has(feature)` 로 선언적으로
/// 통일한다. 산재된 `isTpcpStore`/`isMammothStore` prefix 분기를 대체하기 위한 것.
enum BrandFeature {
  /// TPCP 라벨 카테고리 필터(전체/와플만/와플제외) + 옵션 카테고리 분류.
  labelCategoryFilter,

  /// MHST 사운드그래프 주문 전송(자동접수 성공 후 외부 통합).
  soundGraphSend,

  /// 일본(JPY/japanLive) 환경 브랜드.
  japanEnvironment,

  /// Sunmi 기기에서 Sunmi App Store 채널로 업데이트 → 앱내 자동 OTA 체크 OFF.
  /// 이 기능이 **없는** 브랜드는 Sunmi 여부와 무관하게 OTA(자동 체크 ON)를 쓴다.
  /// (Sunmi 가 아닌 기기·Windows 는 이 기능이 있어도 항상 OTA/ON.)
  sunmiAppStoreUpdate,

  /// 설정의 '화면 상하 반전'(180도 회전) 항목 노출. OS 회전 설정이 없는 특정
  /// 기기 구성을 쓰는 브랜드에만 필요하므로 해당 브랜드에서만 노출한다.
  displayRotate,
}

/// 브랜드 식별 키. 매장 ID prefix 로 결정된다.
enum BrandKey { tpcp, mhst, mata, paik, tljp }

/// 한 브랜드의 모든 메타데이터를 모은 단일 출처(SSOT) 레코드.
///
/// 인쇄 자산(폴더/로고), 테마 색상, 통화, 서버 환경, capability 를 한곳에 선언한다.
/// 기존에 [BrandKey](인쇄 자산)·[BrandTheme](색상)·prefix 헬퍼(기능/통화/환경)로
/// 3중 분리돼 있던 개념을 통합한다.
@immutable
class BrandMeta {
  const BrandMeta({
    required this.key,
    required this.storeIdPrefix,
    required this.assetFolder,
    required this.theme,
    required this.currency,
    required this.serverEnvironment,
    this.hasReceiptLogo = false,
    this.features = const <BrandFeature>{},
  });

  final BrandKey key;

  /// 매장 ID prefix (대문자). 예: 'TPCP'.
  final String storeIdPrefix;

  /// `assets/images/brand/<folder>/` 자산 폴더명.
  final String assetFolder;

  final bool hasReceiptLogo;

  /// 브랜드 테마 색상.
  final BrandTheme theme;

  /// 기본 통화. (저장된 사용자 선택이 우선이며, 그게 없을 때의 기본값)
  final CurrencyUnit currency;

  /// 서버 환경 ('japanLive' / 'live').
  final String serverEnvironment;

  /// 이 브랜드가 지원하는 커스텀 기능 집합.
  final Set<BrandFeature> features;

  /// capability 게이팅 진입점.
  bool has(BrandFeature f) => features.contains(f);

  /// 일반 설정에서 사용자가 고를 수 있는 테마 목록 = 기본 테마 + 브랜드 고유 테마.
  ///
  /// 브랜드 고유 테마가 없는(= [BrandTheme.appfitDefault] 인) 브랜드는
  /// [BrandTheme.appfitDefault] 한 개만 반환한다. UI 는 선택지가 1개면 picker 를
  /// 숨겨(무의미한 단일 선택 방지) "브랜드 테마 없음"을 우아하게 처리한다.
  /// 신규 브랜드는 BrandRegistry 의 [theme] 만 채우면 자동으로 2종이 노출된다.
  List<BrandTheme> get selectableThemes => theme == BrandTheme.appfitDefault
      ? const [BrandTheme.appfitDefault]
      : [BrandTheme.appfitDefault, theme];

  String get _assetBase => 'assets/images/brand/$assetFolder';

  /// 라벨 로고 BMP 경로 (모든 브랜드 필수).
  String get labelLogoPath => '$_assetBase/label_logo.bmp';

  /// 영수증 로고 PNG 경로. [hasReceiptLogo] 가 false 면 null.
  String? get receiptLogoPath =>
      hasReceiptLogo ? '$_assetBase/receipt_logo.png' : null;

  /// 테마 화면 로고 SVG 경로.
  String get themeLogoPath => '$_assetBase/logo.svg';
}

/// 매장 ID prefix → [BrandMeta] 단일 출처(SSOT).
///
/// 순수(prefs 비의존) 클래스로, 단위 테스트가 쉽다. 현재 브랜드를 얻으려면
/// [resolve] 에 매장 ID 를 넘기거나 `currentBrandProvider`(brand_provider.dart) 를
/// 사용한다.
///
/// 새 브랜드 추가는:
///   1. `assets/images/brand/<slug>/` 자산 배치 + `pubspec.yaml` 등록
///   2. (테마 색상이 다르면) [BrandTheme] enum 한 줄 추가
///   3. 본 [_all] Map 에 [BrandMeta] 항목 한 개 추가 (features 로 기능 선언)
class BrandRegistry {
  BrandRegistry._();

  static const BrandKey _fallbackKey = BrandKey.tpcp;

  static const Map<BrandKey, BrandMeta> _all = {
    BrandKey.tpcp: BrandMeta(
      key: BrandKey.tpcp,
      storeIdPrefix: 'TPCP',
      assetFolder: 'tokyoplatz',
      theme: BrandTheme.appfitDefault,
      currency: CurrencyUnit.jpy,
      serverEnvironment: 'japanLive',
      features: {
        BrandFeature.labelCategoryFilter,
        BrandFeature.japanEnvironment,
        BrandFeature.displayRotate,
      },
    ),
    BrandKey.mhst: BrandMeta(
      key: BrandKey.mhst,
      storeIdPrefix: 'MHST',
      assetFolder: 'mammoth',
      hasReceiptLogo: true,
      theme: BrandTheme.mammothCoffee,
      currency: CurrencyUnit.krw,
      serverEnvironment: 'live',
      features: {
        BrandFeature.soundGraphSend,
        BrandFeature.sunmiAppStoreUpdate,
      },
    ),
    BrandKey.mata: BrandMeta(
      key: BrandKey.mata,
      storeIdPrefix: 'MATA',
      assetFolder: 'mahataste',
      hasReceiptLogo: true,
      theme: BrandTheme.mata,
      currency: CurrencyUnit.krw,
      serverEnvironment: 'live',
    ),
    BrandKey.paik: BrandMeta(
      key: BrandKey.paik,
      storeIdPrefix: 'PAIK',
      assetFolder: 'paik',
      hasReceiptLogo: true,
      theme: BrandTheme.paik,
      currency: CurrencyUnit.jpy,
      serverEnvironment: 'japanLive',
      features: {BrandFeature.japanEnvironment},
    ),
    BrandKey.tljp: BrandMeta(
      key: BrandKey.tljp,
      storeIdPrefix: 'TLJP',
      assetFolder: 'theliterjp',
      theme: BrandTheme.tljp,
      currency: CurrencyUnit.jpy,
      serverEnvironment: 'japanLive',
      features: {BrandFeature.japanEnvironment},
    ),
  };

  /// 미로그인/미지원 prefix 의 fallback 브랜드 (tokyoplatz).
  static BrandMeta get fallback => _all[_fallbackKey]!;

  /// 매장 ID prefix 로 브랜드 해석. 매칭이 없으면 **null** (기타/kokonut/미로그인).
  ///
  /// capability·통화·환경 조회는 반드시 이 메서드를 써서 "미지의 브랜드 = 기능 없음"
  /// 을 보장한다. ([resolve] 는 자산용 fallback 이 있어 미지의 매장에도 TPCP 기능이
  /// 붙는 오작동을 일으킬 수 있다.)
  ///
  /// prefix 들은 서로 접두 관계가 없으므로(TPCP/MHST/MATA) 순회 순서 무관.
  static BrandMeta? resolveOrNull(String? storeId) {
    final id = storeId?.toUpperCase();
    if (id == null || id.isEmpty) return null;
    for (final meta in _all.values) {
      if (id.startsWith(meta.storeIdPrefix)) return meta;
    }
    return null;
  }

  /// 인쇄 자산용 해석 — 매칭이 없으면 [fallback](tokyoplatz). 라벨/영수증은 항상
  /// 로고가 필요하므로 fallback 한다. capability 판단에는 [resolveOrNull] 사용.
  static BrandMeta resolve(String? storeId) =>
      resolveOrNull(storeId) ?? fallback;

  static BrandMeta byKey(BrandKey key) => _all[key] ?? fallback;
}
