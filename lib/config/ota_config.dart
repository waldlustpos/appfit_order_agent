import 'package:appfit_order_agent/config/app_env.dart';

/// Android OTA 자동업데이트용 상수 모음.
///
/// 배포 변형(update | standalone)에 따라 OTA 채널을 분기한다.
/// standalone 은 구앱과 병존 설치되므로 update 채널을 오염시키지 않도록
/// 별도 채널 파일(appfit_order_agent_standalone*.json/.apk)을 사용한다.
class OtaConfig {
  static const String _base = 'http://waldpay.kokonutstamp2.com/';

  static const String versionUrl = AppEnv.isStandalone
      ? '${_base}appfit_order_agent_standalone_version.json'
      : '${_base}appfit_order_agent_version.json';
  static const String downloadUrl = AppEnv.isStandalone
      ? '${_base}appfit_order_agent_standalone.apk'
      : '${_base}appfit_order_agent.apk';
}
