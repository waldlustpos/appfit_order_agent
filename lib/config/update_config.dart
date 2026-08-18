import 'package:appfit_order_agent/config/build_brand.dart';

/// Windows 자동업데이트용 상수 모음.
///
/// **채널은 브랜드가 아니라 아티팩트에 종속된다** (`lib/config/ota_config.dart`
/// 와 동일 원칙). Tier 1 아티팩트는 exe명이 달라 공통 채널의 ZIP 을 받아도
/// 자연 업데이트가 걸리지 않으므로(파일명이 다른 exe 로는 in-place 교체가
/// 불가능), 아티팩트마다 정확히 채널 1세트를 둔다.
///
/// | 아티팩트 | 채널 |
/// | --- | --- |
/// | 공통 | `appfit_order_agent_windows.zip` (레거시 무접미 — 계속 사용, 동결 아님) |
/// | 맘모스 | `appfit_order_agent_mammoth_windows.zip` (신설) |
///
/// 서버(live/japanLive/staging)는 로그인 화면에서 런타임 선택되므로 채널과
/// 무관하다. 채널을 가르는 것은 exe명(=브랜드)뿐이다.
///
/// **공통 브랜드는 `_brandInfix` 가 빈 문자열이라 아래 모든 상수가 이 파일이
/// 생기기 전과 바이트 단위로 동일하다** — 기존 설치본은 그대로 레거시 무접미
/// 채널을 폴링해 자연 업데이트된다(Android 는 구 패키지 일본 매장 때문에
/// 무접미 채널을 동결하고 `_release` 채널을 쓴다 — 정책이 반대이니 혼동 주의).
class UpdateConfig {
  static const String _base = 'http://waldpay.kokonutstamp2.com/';

  static const String _brandInfix = BuildBrand.isMammoth ? '_mammoth' : '';

  static const String versionUrl =
      '${_base}appfit_order_agent${_brandInfix}_windows_version.json';
  static const String downloadUrl =
      '${_base}appfit_order_agent${_brandInfix}_windows.zip';

  static const String zipFileName =
      'appfit_order_agent${_brandInfix}_windows.zip';

  static const String extractDirName =
      'appfit_order_agent${_brandInfix}_update_extracted';
  static const String updaterBatName =
      'appfit_order_agent${_brandInfix}_updater.bat';
  static const String updaterVbsName =
      'appfit_order_agent${_brandInfix}_updater_launcher.vbs';
  static const String updaterLogName =
      'appfit_order_agent${_brandInfix}_updater.log';

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration checkReceiveTimeout = Duration(seconds: 10);
  static const Duration downloadReceiveTimeout = Duration(minutes: 10);

  const UpdateConfig._();
}
