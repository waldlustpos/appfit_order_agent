/// 빌드 시점에 고정되는 **브랜드 아티팩트 식별자**.
///
/// 2-티어 아티팩트 모델의 Tier 1(전용 아티팩트)을 구분하는 유일한 축이다.
///
/// - `common`  — 기본값. 모든 브랜드가 쓰는 공통 아티팩트.
/// - `mammoth` — 매머드커피 전용 아티팩트. 별도 패키지
///   (`co.kr.waldlust.order.receive.appfit.mammoth`)·전용 런처 이름·아이콘·
///   전용 OTA 채널을 갖는다.
///
/// ## 이 값이 건드려도 되는 것 (전부)
/// applicationId, 런처 label/icon, Windows BINARY_NAME·ProductName·mutex·
/// Inno GUID, **인앱 OTA 채널 URL**, 로그인 전 기본 브랜드 프리시드.
///
/// ## 이 값이 절대 건드리면 안 되는 것
/// 서버 환경, `BrandFeature` 게이팅, 프린터·주문 로직, i18n 분기. 전부
/// `BrandRegistry`(`lib/utils/brand_registry.dart`) 런타임 정본으로 남는다.
/// 2026-07 변형 폐기의 교훈은 "브랜드로 빌드를 나누지 마라"가 아니라
/// **"빌드 축이 로직까지 번지게 두지 마라"** 였다.
///
/// 이 규율은 컴파일 타임에 강제할 수 없으므로 참조 지점 화이트리스트 테스트
/// (`test/config/build_brand_scope_test.dart`)로 고정한다. 새 참조를 만들려면
/// 그 테스트의 목록을 사람이 의도적으로 늘려야 한다.
///
/// ## 왜 `app_env.dart` 가 아닌 별도 파일인가
/// `app_env.dart` 는 **머신별 gitignored 로컬 파일**이다. 거기에 멤버를 추가하면
/// 다른 빌드 머신의 stale 사본에서 컴파일이 깨진다(과거 실사고). 이 파일은
/// 커밋된다.
///
/// ## 주입
/// `--dart-define=APPFIT_BRAND=<slug>`. Android 는 **`--flavor <slug>` 와 반드시
/// 함께** 넘겨야 한다 — 둘이 어긋나면 매머드 패키지가 공통 OTA 채널을 보게 되고,
/// 다운로드한 APK 는 패키지 불일치로 설치가 실패한다. 빌드 스크립트는 하나의
/// `BRAND` 변수로 두 인자를 동시에 구동한다.
class BuildBrand {
  const BuildBrand._();

  /// 빌드된 아티팩트의 브랜드 슬러그. 기본 `common`.
  static const String slug =
      String.fromEnvironment('APPFIT_BRAND', defaultValue: 'common');

  /// 매머드 전용 아티팩트 여부.
  ///
  /// getter 가 아니라 **`const`** 여야 한다 — `OtaConfig` 의 컴파일 타임 const
  /// 채널 분기가 이 값을 쓴다.
  static const bool isMammoth = slug == 'mammoth';

  /// 공통(Tier 0) 아티팩트 여부.
  static const bool isCommon = slug == 'common';
}
