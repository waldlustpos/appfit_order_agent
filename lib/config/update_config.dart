import 'package:appfit_order_agent/config/app_env.dart';

/// Windows 자동업데이트용 상수 모음.
///
/// 배포 변형(update | standalone)에 따라 OTA 채널을 분기한다.
/// standalone 은 구앱과 병존 설치되므로 update 채널을 오염시키지 않도록
/// 별도 채널 파일(appfit_order_agent_standalone*_windows*.zip/.json)을 사용하고,
/// 임시 작업 파일명도 분리해 동시 업데이트 시 충돌을 방지한다.
class UpdateConfig {
  static const String _base = 'http://waldpay.kokonutstamp2.com/';

  static const String versionUrl = AppEnv.isStandalone
      ? '${_base}appfit_order_agent_standalone_windows_version.json'
      : '${_base}appfit_order_agent_windows_version.json';
  static const String downloadUrl = AppEnv.isStandalone
      ? '${_base}appfit_order_agent_standalone_windows.zip'
      : '${_base}appfit_order_agent_windows.zip';

  static const String zipFileName = AppEnv.isStandalone
      ? 'appfit_order_agent_standalone_windows.zip'
      : 'appfit_order_agent_windows.zip';
  static const String exeName = AppEnv.isStandalone
      ? 'appfit_order_agent_standalone.exe'
      : 'appfit_order_agent.exe';

  static const String extractDirName = AppEnv.isStandalone
      ? 'appfit_order_agent_standalone_update_extracted'
      : 'appfit_order_agent_update_extracted';
  static const String updaterBatName = AppEnv.isStandalone
      ? 'appfit_order_agent_standalone_updater.bat'
      : 'appfit_order_agent_updater.bat';
  static const String updaterVbsName = AppEnv.isStandalone
      ? 'appfit_order_agent_standalone_updater_launcher.vbs'
      : 'appfit_order_agent_updater_launcher.vbs';
  static const String updaterLogName = AppEnv.isStandalone
      ? 'appfit_order_agent_standalone_updater.log'
      : 'appfit_order_agent_updater.log';

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration checkReceiveTimeout = Duration(seconds: 10);
  static const Duration downloadReceiveTimeout = Duration(minutes: 10);

  const UpdateConfig._();
}
