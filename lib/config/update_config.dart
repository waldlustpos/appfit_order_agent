/// Windows 자동업데이트용 상수 모음.
class UpdateConfig {
  static const String versionUrl =
      'http://waldpay.kokonutstamp2.com/appfit_order_agent_windows_version.json';
  static const String downloadUrl =
      'http://waldpay.kokonutstamp2.com/appfit_order_agent_windows.zip';

  static const String zipFileName = 'appfit_order_agent_windows.zip';
  static const String exeName = 'appfit_order_agent.exe';

  static const String extractDirName = 'appfit_order_agent_update_extracted';
  static const String updaterBatName = 'appfit_order_agent_updater.bat';
  static const String updaterVbsName =
      'appfit_order_agent_updater_launcher.vbs';
  static const String updaterLogName = 'appfit_order_agent_updater.log';

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration checkReceiveTimeout = Duration(seconds: 10);
  static const Duration downloadReceiveTimeout = Duration(minutes: 10);

  const UpdateConfig._();
}
