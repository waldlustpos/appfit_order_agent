/// Windows 자동업데이트용 상수 모음.
///
/// 단일 빌드가 한국/일본을 모두 서빙하며 채널은 레거시 무접미 하나만 사용한다.
/// Windows 는 패키지 개념이 없고 exe명(appfit_order_agent.exe)이 기존 설치본과
/// 동일하므로, 기존 설치본이 이 채널로 자연스럽게 자동 업데이트된다.
/// (Android 는 구 패키지 일본 매장 때문에 무접미 채널을 동결하고 `_appfit`
/// 채널을 쓴다 — OtaConfig 참조. 정책이 반대이니 혼동 주의.)
class UpdateConfig {
  static const String _base = 'http://waldpay.kokonutstamp2.com/';

  static const String versionUrl =
      '${_base}appfit_order_agent_windows_version.json';
  static const String downloadUrl = '${_base}appfit_order_agent_windows.zip';

  static const String zipFileName = 'appfit_order_agent_windows.zip';

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
