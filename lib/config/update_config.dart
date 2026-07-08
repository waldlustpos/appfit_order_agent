import 'package:appfit_order_agent/config/app_env.dart';

/// Windows 자동업데이트용 상수 모음.
///
/// 단일 exe(appfit_order_agent.exe) + 단일 뮤텍스로 통합되어 두 변형이 같은
/// 머신에서 동시 실행될 수 없으므로, 임시 작업 파일명은 분리하지 않고 통일한다.
/// 다만 지역별 서버 기본값이 다르므로 OTA 채널(zip/json)은 접미사로 분리한다.
///
/// japan 은 레거시 무접미 채널을 계속 사용한다(동결 아님). Windows 는 패키지
/// 개념이 없고 통일 후 exe명이 기존 japan 설치본과 동일하므로, 기존 설치본이
/// 레거시 채널로 자연스럽게 자동 업데이트된다. Android 의 레거시 채널 동결
/// 정책과는 반대이니 혼동 주의.
class UpdateConfig {
  static const String _base = 'http://waldpay.kokonutstamp2.com/';

  static const String versionUrl = AppEnv.isKorea
      ? '${_base}appfit_order_agent_korea_windows_version.json'
      : '${_base}appfit_order_agent_windows_version.json';
  static const String downloadUrl = AppEnv.isKorea
      ? '${_base}appfit_order_agent_korea_windows.zip'
      : '${_base}appfit_order_agent_windows.zip';

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
