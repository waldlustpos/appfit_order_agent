import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

import 'package:appfit_order_agent/services/platform_service.dart';
import 'package:appfit_order_agent/services/preference_service.dart';
import 'package:appfit_order_agent/utils/logger.dart';

/// 기기 식별 정보 묶음. 관재 운영 표기(매장명+매장코드+기기모델+시리얼)에 사용.
class DeviceIdentity {
  final String? shopName;
  final String? shopCode;

  /// 사람이 읽는 기기 모델명. Android "제조사 모델"(예: "FYD IM-H092W"),
  /// Windows computerName.
  final String deviceModel;

  /// 하드웨어 시리얼(예: "H092W24A1G00862"). 취득 실패 시 null.
  final String? serial;

  /// 명령 타겟팅용 안정 식별자 = serial > Windows deviceId > 설치 UUID.
  final String deviceId;

  /// [deviceId] 의 출처(serial/deviceId/installId). 진단용.
  final String idSource;

  const DeviceIdentity({
    required this.shopName,
    required this.shopCode,
    required this.deviceModel,
    required this.serial,
    required this.deviceId,
    required this.idSource,
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
  /// 시리얼이 없으면 fallback 식별자(설치ID)를 괄호에 표기.
  String get deviceLabel => '$deviceModel (${serial ?? deviceId})';

  /// "매장 · 모델명 (시리얼)" 형식의 한 줄 라벨(로그/캡션용).
  String get label {
    final store = storeLabel;
    return store.isEmpty ? deviceLabel : '$store · $deviceLabel';
  }
}

/// 기기 고유 식별자 해석 서비스.
///
/// 시리얼 우선순위: Android 네이티브(Sunmi 프린터 서비스 / SystemProperties /
/// Build) > Windows deviceId(MachineGuid) > 설치 UUID. 시리얼은 1회 조회 후
/// [PreferenceService] 에 캐시한다. 매장 전환/재로그인으로 매장명·코드가 바뀌면
/// [invalidate] 로 캐시를 비운다.
class DeviceIdentityService {
  final PreferenceService _prefs;

  DeviceIdentityService(this._prefs);

  DeviceIdentity? _cached;

  Future<DeviceIdentity> resolve() async {
    if (_cached != null) return _cached!;

    final shopName = _prefs.getStoreName();
    final shopCode = _prefs.getId();

    // 기기 모델명 + (Windows) deviceId 를 플랫폼 info 1회 조회로 확보.
    String deviceModel = 'Unknown';
    String? windowsDeviceId;
    try {
      final di = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final info = await di.androidInfo;
        deviceModel = '${info.manufacturer} ${info.model}';
      } else if (Platform.isWindows) {
        final info = await di.windowsInfo;
        deviceModel = info.computerName;
        windowsDeviceId = info.deviceId;
      }
    } catch (e, s) {
      logger.w('[DeviceIdentity] 기기 모델 조회 실패', error: e, stackTrace: s);
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

    // 2) Windows deviceId (MachineGuid)
    if (serialOrId == null &&
        windowsDeviceId != null &&
        windowsDeviceId.isNotEmpty) {
      serialOrId = windowsDeviceId;
      source = 'deviceId';
    }

    // 3) fallback: 설치 UUID
    final String deviceId;
    if (serialOrId != null && serialOrId.isNotEmpty) {
      deviceId = serialOrId;
    } else {
      deviceId = await _prefs.getOrCreateInstallId();
      source = 'installId';
    }

    _cached = DeviceIdentity(
      shopName: shopName,
      shopCode: shopCode,
      deviceModel: deviceModel,
      serial: serial,
      deviceId: deviceId,
      idSource: source,
    );
    return _cached!;
  }

  /// 캐시 무효화(매장 전환/재로그인 후 매장명·코드 갱신 시 호출).
  void invalidate() => _cached = null;
}
