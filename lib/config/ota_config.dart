/// Android OTA 자동업데이트용 상수 모음.
///
/// 단일 빌드(단일 패키지 co.kr.waldlust.order.receive.appfit)가 한국/일본을
/// 모두 서빙하므로 OTA 채널도 `_appfit` 하나만 사용한다. 서버(live/japanLive)는
/// 로그인 화면에서 런타임 선택하며 OTA 채널과 무관하다.
///
/// 레거시 무접미 채널(appfit_order_agent.apk / appfit_order_agent_version.json)은
/// 동결(FROZEN)한다. 구 패키지(co.kr.waldlust.order.receive)로 설치된 일본 매장
/// 1곳이 이 채널을 폴링하고 있어, .appfit 패키지 APK 를 업로드하면 패키지 불일치로
/// 설치가 실패한다. 해당 매장이 신규 패키지로 수동 재설치될 때까지 절대 업로드 금지.
class OtaConfig {
  static const String _base = 'http://waldpay.kokonutstamp2.com/';

  static const String versionUrl =
      '${_base}appfit_order_agent_appfit_version.json';
  static const String downloadUrl = '${_base}appfit_order_agent_appfit.apk';
}
