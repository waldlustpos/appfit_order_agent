import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

import 'package:appfit_order_agent/services/platform_service.dart';
import 'package:appfit_order_agent/services/preference_service.dart';
import 'package:appfit_order_agent/utils/logger.dart';

/// 기기 식별 정보 묶음. 관재 운영 표기(매장명+매장코드+기기식별자)에 사용.
class DeviceIdentity {
  final String? shopName;
  final String? shopCode;

  /// 안정적 기기 식별자(Sunmi serial > Windows deviceId > installId 순 결정).
  final String deviceId;

  /// [deviceId] 의 출처(serial/deviceId/installId). 진단·표시용.
  final String idSource;

  const DeviceIdentity({
    required this.shopName,
    required this.shopCode,
    required this.deviceId,
    required this.idSource,
  });

  /// "매장명 (매장코드)" 형식. 비어 있으면 빈 문자열.
  String get storeLabel {
    final parts = <String>[
      if (shopName != null && shopName!.isNotEmpty) shopName!,
      if (shopCode != null && shopCode!.isNotEmpty) '($shopCode)',
    ];
    return parts.join(' ');
  }

  /// "매장명 (매장코드) · <deviceId>" 형식의 사람용 라벨.
  String get label {
    final store = storeLabel;
    return store.isEmpty ? deviceId : '$store · $deviceId';
  }
}

/// 기기 고유 식별자 해석 서비스.
///
/// 우선순위: Sunmi 시리얼(Android) > Windows deviceId(MachineGuid) > 설치 UUID.
/// 시리얼은 1회 조회 후 [PreferenceService] 에 캐시한다. 매장 전환/재로그인으로
/// 매장명·코드가 바뀌면 [invalidate] 로 캐시를 비운다.
class DeviceIdentityService {
  final PreferenceService _prefs;

  DeviceIdentityService(this._prefs);

  DeviceIdentity? _cached;

  Future<DeviceIdentity> resolve() async {
    if (_cached != null) return _cached!;

    final shopName = _prefs.getStoreName();
    final shopCode = _prefs.getId();

    String? serialOrId;
    String source = 'installId';

    // 1) Sunmi 시리얼 (캐시 우선, 없으면 네이티브 1회 조회 후 캐시)
    final cachedSerial = _prefs.getCachedDeviceSerial();
    if (cachedSerial != null && cachedSerial.isNotEmpty) {
      serialOrId = cachedSerial;
      source = 'serial';
    } else if (Platform.isAndroid) {
      final serial = await PlatformService.getDeviceSerial();
      if (serial != null && serial.isNotEmpty) {
        await _prefs.setCachedDeviceSerial(serial);
        serialOrId = serial;
        source = 'serial';
      }
    }

    // 2) Windows deviceId (MachineGuid)
    if (serialOrId == null && Platform.isWindows) {
      try {
        final winId = (await DeviceInfoPlugin().windowsInfo).deviceId;
        if (winId.isNotEmpty) {
          serialOrId = winId;
          source = 'deviceId';
        }
      } catch (e, s) {
        logger.w('[DeviceIdentity] windowsInfo 조회 실패', error: e, stackTrace: s);
      }
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
      deviceId: deviceId,
      idSource: source,
    );
    return _cached!;
  }

  /// 캐시 무효화(매장 전환/재로그인 후 매장명·코드 갱신 시 호출).
  void invalidate() => _cached = null;
}
