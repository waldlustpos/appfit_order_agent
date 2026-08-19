/// 기기 관제(Fleet) 대상 매장 화이트리스트 조회용 상수.
///
/// 백엔드 접속 정보(`FLEET_BASE_URL`/`FLEET_DEVICE_KEY`)는 빌드 타임 주입이라
/// [AppEnv] 에 있고, 여기 있는 것은 **런타임에 조회하는 대상 매장 목록**의 위치다.
/// 둘은 목적이 다르다 — 전자는 "이 빌드가 관제를 말할 수 있는가", 후자는
/// "이 매장이 지금 관제 대상인가".
///
/// 목록은 OTA 아티팩트와 **같은 정적 호스트**에 올라간다. 배포 스크립트가
/// 다루는 파일은 아티팩트 + version JSON 2개뿐이므로 이 파일은 파이프라인 밖의
/// 수동 자산이다(레포 정본은 `fleet_targets/fleet_stores.json`).
///
/// 브랜드·플랫폼 공용 **단일 파일**이라 OTA 처럼 채널 접미사를 붙이지 않는다.
/// 매장 코드는 이미 전역 고유해서 채널을 가를 이유가 없다. 여기서 빌드 축(브랜드
/// 슬러그) 상수를 끌어오면 `test/config/build_brand_scope_test.dart` 의 참조
/// 화이트리스트를 늘려야 하는데, 그 목록의 취지(OS 셸 아이덴티티 + 배포 채널)에
/// 관제 대상 판정은 해당하지 않는다 — 대상 여부는 런타임 매장 속성이다.
class FleetConfig {
  const FleetConfig._();

  /// OTA 아티팩트와 같은 정적 호스트(`OtaConfig`/`UpdateConfig` 와 동일 값).
  /// 저 둘은 브랜드 채널 규칙에 묶여 있어 재사용하지 않고 여기서 따로 든다.
  static const String _base = 'http://waldpay.kokonutstamp2.com/';

  /// 대상 매장 목록. `{"version": 1, "stores": ["MHST00001", ...]}`
  static const String storeAllowlistUrl = '${_base}fleet_stores.json';

  /// 로그인 흐름에 얹히는 부가 조회라 짧게 끊는다. 실패해도 캐시로 판정하므로
  /// 오래 기다릴 이유가 없다.
  static const Duration fetchConnectTimeout = Duration(seconds: 5);
  static const Duration fetchReceiveTimeout = Duration(seconds: 5);
}
