import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

import 'package:appfit_order_agent/services/platform_service.dart';
import 'package:appfit_order_agent/services/preference_service.dart';
import 'package:appfit_order_agent/utils/logger.dart';

/// 기기 식별 정보 묶음. 관재 운영 표기(매장명+매장코드+기기모델+시리얼)에 사용.
class DeviceIdentity {
  /// 프로젝트명(=브랜드명). /v0/project/info 의 projectName(예: "발트커피").
  final String? projectName;
  final String? shopName;
  final String? shopCode;

  /// 사람이 읽는 기기 모델명. Android "제조사 모델"(예: "FYD IM-H092W"),
  /// Windows computerName.
  final String deviceModel;

  /// 하드웨어 시리얼(예: "H092W24A1G00862"). 취득 실패 시 null.
  final String? serial;

  /// 명령 타겟팅용 안정 식별자 = Android 시리얼 > 설치 UUID.
  /// **Windows 는 항상 설치 UUID 다** — 사유는 [DeviceIdentityService.resolve].
  final String deviceId;

  /// [deviceId] 의 출처. 이 앱이 만드는 값은 `serial` / `installId` 둘뿐이다.
  /// 관제 대시보드에 보이는 `deviceId` 는 Windows MachineGuid 를 쓰던 시절
  /// D1 에 기록된 **레거시 값**이고, 앱은 더 이상 생성하지 않는다. 진단용.
  final String idSource;

  /// 제조사. Android 는 `Build.MANUFACTURER`, Windows 는 'Microsoft' 고정.
  /// [deviceModel] 이 Android 에서 "제조사 모델" 합성이라 값이 겹치지만,
  /// 관제 서버는 제조사로 필터링(예: Sunmi 기기만)하므로 별도로 보낸다.
  final String deviceManufacturer;

  /// android | windows | ios | unknown
  final String platform;

  /// Android 는 `version.release`(예: "13"), Windows 는 displayVersion
  /// (예: "22H2") 또는 major.minor.build. 취득 실패 시 'unknown'.
  final String osVersion;

  const DeviceIdentity({
    required this.projectName,
    required this.shopName,
    required this.shopCode,
    required this.deviceModel,
    required this.serial,
    required this.deviceId,
    required this.idSource,
    required this.deviceManufacturer,
    required this.platform,
    required this.osVersion,
  });

  /// 설정화면 "매장" 값. "매장명 (매장코드)" / 코드만 / 매장명만 / 빈 문자열.
  String get storeLabel {
    final hasName = shopName != null && shopName!.isNotEmpty;
    final hasCode = shopCode != null && shopCode!.isNotEmpty;
    if (hasName && hasCode) return '$shopName ($shopCode)';
    if (hasCode) return shopCode!;
    if (hasName) return shopName!;
    return '';
  }

  /// 설정화면 "기기" 값. "모델명 (시리얼)" 형식(예: "FYD IM-H092W (H092W24A1G00862)").
  /// 시리얼이 없으면 fallback 식별자(설치ID)를 괄호에 표기 — Windows 는 시리얼을
  /// 조회하지 않으므로 **항상** "컴퓨터이름 (설치ID)" 가 된다.
  String get deviceLabel => '$deviceModel (${serial ?? deviceId})';

  /// "매장 · 모델명 (시리얼)" 형식의 한 줄 라벨(로그/캡션용).
  String get label {
    final store = storeLabel;
    return store.isEmpty ? deviceLabel : '$store · $deviceLabel';
  }
}

/// 기기 고유 식별자 해석 서비스.
///
/// 우선순위: Android 네이티브 시리얼(Sunmi 프린터 서비스 / SystemProperties /
/// Build) > 설치 UUID. **Windows 는 항상 설치 UUID 다** — 기기에서 읽은 값을
/// 식별자로 쓰지 않는다(사유는 [resolve] 의 2단계 주석). 시리얼은 1회 조회 후
/// [PreferenceService] 에 캐시한다. 매장 전환/재로그인으로 매장명·코드가 바뀌면
/// [invalidate] 로 캐시를 비운다.
class DeviceIdentityService {
  final PreferenceService _prefs;

  DeviceIdentityService(this._prefs);

  DeviceIdentity? _cached;

  Future<DeviceIdentity> resolve() async {
    if (_cached != null) return _cached!;

    final projectName = _prefs.getProjectName();
    final shopName = _prefs.getStoreName();
    final shopCode = _prefs.getActiveStoreId();

    // 플랫폼 판정은 info 조회 성공 여부와 무관하게 확정할 수 있다.
    final platform = Platform.isAndroid
        ? 'android'
        : Platform.isWindows
            ? 'windows'
            : Platform.isIOS
                ? 'ios'
                : 'unknown';

    // 기기 모델명 + 제조사 + OS 버전을 플랫폼 info 1회 조회로 확보한다.
    // 관제(FleetReporter)와 설정화면이 같은 정본을 본다. 여기서 얻는 값은
    // 전부 **표시·보고용**이며 식별자로 쓰지 않는다.
    String deviceModel = 'Unknown';
    String deviceManufacturer = 'Unknown';
    String osVersion = 'unknown';
    try {
      final di = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final info = await di.androidInfo;
        deviceModel = '${info.manufacturer} ${info.model}';
        deviceManufacturer = info.manufacturer;
        osVersion = info.version.release;
      } else if (Platform.isWindows) {
        final info = await di.windowsInfo;
        deviceModel = info.computerName;
        deviceManufacturer = 'Microsoft';
        // displayVersion 은 "22H2" 같은 사람이 읽는 표기. 비어 있으면 빌드 번호로.
        osVersion = info.displayVersion.isNotEmpty
            ? info.displayVersion
            : '${info.majorVersion}.${info.minorVersion}.${info.buildNumber}';
      }
    } catch (e, s) {
      logger.w('[DeviceIdentity] 기기 정보 조회 실패', error: e, stackTrace: s);
    }

    String? serial;
    String? serialOrId;
    String source = 'installId';

    // 1) 하드웨어 시리얼 (캐시 우선, 없으면 Android 네이티브 1회 조회 후 캐시)
    final cachedSerial = _prefs.getCachedDeviceSerial();
    if (cachedSerial != null && cachedSerial.isNotEmpty) {
      serial = cachedSerial;
      serialOrId = cachedSerial;
      source = 'serial';
    } else if (Platform.isAndroid) {
      final s = await PlatformService.getDeviceSerial();
      if (s != null && s.isNotEmpty) {
        await _prefs.setCachedDeviceSerial(s);
        serial = s;
        serialOrId = s;
        source = 'serial';
      }
    }

    // 2) 설치 UUID — Android 시리얼 실패 시 폴백이자, **Windows 의 유일한 경로**.
    //
    // ⚠️ Windows MachineGuid 를 여기에 다시 끼워 넣지 말 것.
    // device_info_plus 의 WindowsDeviceInfo.deviceId 는 레지스트리
    // HKLM\SOFTWARE\Microsoft\SQMClient\MachineId 를 그대로 읽은 값이고,
    // 하드웨어 파생값이 아니다. sysprep 없이 디스크 이미지를 복제해 배포한
    // POS 들은 이 값이 전부 같다.
    //
    // 실사고(2026-09-03): 동대문구청점(MMTH01050)과 약수역점(MMTH01066)이
    // 같은 {B4496514-2412-4720-8692-ABBFA52A5903} 으로 보고해 관제 D1 의
    // PK (app_type, device_id) 한 행을 30초마다 번갈아 덮어썼다. 관제 데이터가
    // 무의미해졌고, 한 매장은 대시보드에서 사라졌고, 로그 요청이 엉뚱한 매장
    // PC 로 배달돼 FleetReporter 의 대상 검증에서 INVALID_TARGET 이 났다.
    // 기기 레지스트리 수정이 불가능한 환경이라 식별 기준 자체를 바꿨다.
    // "보통은 유일하다" 는 식별자의 조건이 아니다. 경위는
    // docs/DEVICE_MONITORING.md.
    final String deviceId;
    if (serialOrId != null && serialOrId.isNotEmpty) {
      deviceId = serialOrId;
    } else {
      deviceId = await _prefs.getOrCreateInstallId();
      source = 'installId';
    }

    _cached = DeviceIdentity(
      projectName: projectName,
      shopName: shopName,
      shopCode: shopCode,
      deviceModel: deviceModel,
      serial: serial,
      deviceId: deviceId,
      idSource: source,
      deviceManufacturer: deviceManufacturer,
      platform: platform,
      osVersion: osVersion,
    );
    logger.i(
      '[DeviceIdentity] 설정카드 표기값 — 매장="${_cached!.storeLabel}", '
      '기기="${_cached!.deviceLabel}" (serial=$serial, source=$source, '
      'platform=$platform, os=$osVersion)',
    );
    return _cached!;
  }

  /// 캐시 무효화(매장 전환/재로그인 후 매장명·코드 갱신 시 호출).
  void invalidate() => _cached = null;
}
