import 'dart:io';

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
/// | 매머드 | `appfit_order_agent_mammoth_windows.zip` (신설) |
///
/// 서버(live/japanLive/staging)는 로그인 화면에서 런타임 선택되므로 채널과
/// 무관하다. 채널을 가르는 것은 exe명(=브랜드)뿐이다.
///
/// **공통 브랜드는 `_brandInfix` 가 빈 문자열이라 아래 모든 상수가 이 파일이
/// 생기기 전과 바이트 단위로 동일하다** — 기존 설치본은 그대로 레거시 무접미
/// 채널을 폴링해 자연 업데이트된다(Android 는 구 패키지 일본 매장 때문에
/// 무접미 채널을 동결하고 `_release` 채널을 쓴다 — 정책이 반대이니 혼동 주의).
class UpdateConfig {
  /// HTTPS 고정 (2026-08). OTA 로 받은 바이너리는 updater.bat 이 설치 폴더에
  /// 그대로 덮어쓰므로, 평문 HTTP 로 받으면 매장 네트워크 중간자가 임의 코드를
  /// 앱 자리에 앉힐 수 있다. per-user 전환 이전(Program Files 설치)에서는 그
  /// 코드가 UAC 상승 상태로 실행되기까지 한다.
  ///
  /// **HTTP 폴백을 의도적으로 두지 않는다** — 폴백이 있으면 다운그레이드 공격에
  /// 그대로 노출되어 HTTPS 전환의 의미가 사라진다. TLS 실패 시에는
  /// `checkForUpdate()` 가 null 을 반환해 업데이트만 조용히 건너뛰고 앱은 정상
  /// 기동하므로, 영업이 멈추지는 않는다.
  ///
  /// Android OTA(`lib/config/ota_config.dart`)는 이 전환의 스코프 밖이라 아직
  /// http 를 쓴다 — 같은 도메인이지만 정책이 다르니 혼동 주의.
  static const String _base = 'https://waldpay.kokonutstamp2.com/';

  static const String _brandInfix = BuildBrand.isMammoth ? '_mammoth' : '';

  /// 설치 폴더명 겸 OTA 스테이징 부모 폴더명.
  ///
  /// **`installer/appfit_order_agent.iss` 의 `MyAppDirName` 과 반드시 같아야
  /// 한다.** 설치본이 등록하는 Defender 예외 경로가
  /// `{localappdata}\{#MyAppDirName}` 인데, 이 값이 어긋나면 예외가 실제
  /// 스테이징 폴더를 덮지 못해 **아무 증상 없이 무효화**된다.
  /// `test/config/build_brand_scope_test.dart` 가 .iss 를 직접 읽어 두 값의
  /// 일치를 단언한다(private 이 아니라 public 인 이유).
  static const String installDirName =
      BuildBrand.isMammoth ? 'AppfitOrderAgentMammoth' : 'AppfitOrderAgent';

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

  /// OTA 작업 파일을 모두 담는 앱 소유 폴더.
  /// `%LOCALAPPDATA%\<installDirName>\update`
  ///
  /// 이전에는 ZIP / 압축해제본 / bat / vbs / 로그가 `%TEMP%` 에 흩어져 있었다.
  /// 그 구조는 백신 예외를 걸기가 사실상 불가능했다 — `%TEMP%` 전체를 제외하는
  /// 것은 보안상 불가하고, 압축해제 폴더 하나만 제외하면 정작 새 exe 를 품은
  /// ZIP 과 updater 스크립트가 예외 범위 밖에 남는다.
  ///
  /// 한 폴더로 모으면 설치본이 `{localappdata}\{#MyAppDirName}` 예외 하나로 OTA
  /// 경로 전체를 덮을 수 있다. 로그가 `%TEMP%` 정리 대상에서 벗어나 사후 진단에
  /// 남는다는 이점도 있다.
  ///
  /// `LOCALAPPDATA` 가 비어 있는 예외적인 환경에서는 시스템 임시 폴더로
  /// 폴백한다(예외는 안 걸리지만 업데이트는 된다).
  static Directory stagingDir() {
    final localAppData = Platform.environment['LOCALAPPDATA'];
    if (localAppData == null || localAppData.isEmpty) {
      return Directory(
        '${Directory.systemTemp.path}\\${installDirName}Update',
      );
    }
    return Directory('$localAppData\\$installDirName\\update');
  }

  /// [stagingDir] 을 만들고 경로를 돌려준다.
  static Future<String> ensureStagingDir() async {
    final dir = stagingDir();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir.path;
  }

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration checkReceiveTimeout = Duration(seconds: 10);
  static const Duration downloadReceiveTimeout = Duration(minutes: 10);

  const UpdateConfig._();
}
