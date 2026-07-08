import 'package:appfit_order_agent/config/app_env.dart';

/// Android OTA 자동업데이트용 상수 모음.
///
/// 단일 패키지(co.kr.waldlust.order.receive.appfit)로 통합되었으며,
/// 배포 지역 변형(japan | korea)은 --dart-define=APPFIT_VARIANT 로만 구분한다.
/// 지역별로 서버 기본값이 다르므로 OTA 채널도 접미사(_japan / _korea)로 분리한다.
///
/// 레거시 무접미 채널(appfit_order_agent.apk / appfit_order_agent_version.json)은
/// 동결(FROZEN)한다. 구 패키지(co.kr.waldlust.order.receive)로 설치된 일본 매장
/// 1곳이 이 채널을 폴링하고 있어, .appfit 패키지 APK 를 업로드하면 패키지 불일치로
/// 설치가 실패한다. 해당 매장이 신규 패키지로 수동 재설치될 때까지 절대 업로드 금지.
class OtaConfig {
  static const String _base = 'http://waldpay.kokonutstamp2.com/';

  static const String versionUrl = AppEnv.isKorea
      ? '${_base}appfit_order_agent_korea_version.json'
      : '${_base}appfit_order_agent_japan_version.json';
  static const String downloadUrl = AppEnv.isKorea
      ? '${_base}appfit_order_agent_korea.apk'
      : '${_base}appfit_order_agent_japan.apk';
}
