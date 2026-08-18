import 'package:appfit_order_agent/config/build_brand.dart';

/// Android OTA 자동업데이트용 상수 모음.
///
/// **채널은 브랜드가 아니라 아티팩트에 종속된다.** 전용 아티팩트는 자기 패키지
/// 때문에 공통 채널을 물리적으로 쓸 수 없으므로(받아도 패키지 불일치로 설치
/// 실패), Tier 1 아티팩트마다 정확히 채널 1세트를 부여한다. 뒤집으면 이게
/// 증식 방지선이다 — **아티팩트 없이 채널만 늘리지 않는다.**
///
/// | 아티팩트 | applicationId | 채널 |
/// | --- | --- | --- |
/// | 공통 | `….appfit` | `appfit_order_agent_release.apk` / `_release_version.json` |
/// | 맘모스 | `….appfit.mammoth` | `appfit_order_agent_mammoth_release.apk` / `_mammoth_release_version.json` |
///
/// 채널명은 슬러그에서 규칙 파생한다(`appfit_order_agent_<brand>_release.*`).
/// 다음 Tier 1 브랜드는 슬러그만 정하면 채널이 따라온다 — 손으로 짓지 않는다.
///
/// 서버(live/japanLive/staging)는 로그인 화면에서 런타임 선택하며 OTA 채널과
/// 무관하다. 채널을 가르는 것은 **패키지**뿐이다.
///
/// 레거시 무접미 채널(appfit_order_agent.apk / appfit_order_agent_version.json)은
/// 동결(FROZEN)한다. 구 패키지(co.kr.waldlust.order.receive)로 설치된 일본 매장
/// 1곳이 이 채널을 폴링하고 있어, .appfit 패키지 APK 를 업로드하면 패키지 불일치로
/// 설치가 실패한다. 해당 매장이 신규 패키지로 수동 재설치될 때까지 절대 업로드 금지.
/// (맘모스 채널 신설도 같은 원리의 반대편이다 — 끄는 게 아니라 자기 채널로 돌린다.)
class OtaConfig {
  static const String _base = 'http://waldpay.kokonutstamp2.com/';

  /// 채널 베이스명. 컴파일 타임 const 분기이므로 릴리즈 빌드에서 반대편 문자열은
  /// 아예 남지 않는다. 공통 빌드의 값은 종전과 **완전히 동일**하다(회귀 방지).
  static const String _channel = BuildBrand.isMammoth
      ? 'appfit_order_agent_mammoth_release'
      : 'appfit_order_agent_release';

  static const String versionUrl = '$_base${_channel}_version.json';
  static const String downloadUrl = '$_base$_channel.apk';
}
