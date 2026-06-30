import 'dart:io';

import 'package:appfit_order_agent/services/monitoring/device_identity_service.dart';

/// 기기 상태 스냅샷(관재 대시보드용).
class DeviceStatusSnapshot {
  final String storeLabel;
  final String deviceId;
  final String idSource;
  final bool connected;
  final String platform;
  final String? appVersion;

  const DeviceStatusSnapshot({
    required this.storeLabel,
    required this.deviceId,
    required this.idSource,
    required this.connected,
    required this.platform,
    this.appVersion,
  });

  Map<String, dynamic> toMap() => {
        'storeLabel': storeLabel,
        'deviceId': deviceId,
        'idSource': idSource,
        'connected': connected,
        'platform': platform,
        if (appVersion != null) 'appVersion': appVersion,
      };

  @override
  String toString() =>
      'DeviceStatus(store=$storeLabel, device=$deviceId/$idSource, '
      'connected=$connected, platform=$platform, version=$appVersion)';
}

/// 기기 상태 보고 서비스 (스캐폴딩).
///
/// 현재는 [snapshot] 으로 상태 객체만 생성한다(설정화면 표시/원격 명령 응답 로깅).
/// 전송 경로(소켓 emit / REST)는 서버 inbound 계약 확정 후 추가한다 — 그때
/// `AppFitNotifierService.sendRaw` 또는 백엔드 엔드포인트로 [toMap] 을 보낸다.
class DeviceStatusReporter {
  final DeviceIdentityService _identity;

  DeviceStatusReporter(this._identity);

  Future<DeviceStatusSnapshot> snapshot({
    bool connected = false,
    String? appVersion,
  }) async {
    final id = await _identity.resolve();
    return DeviceStatusSnapshot(
      storeLabel: id.storeLabel,
      deviceId: id.deviceId,
      idSource: id.idSource,
      connected: connected,
      platform: Platform.isWindows ? 'Windows' : 'Android',
      appVersion: appVersion,
    );
  }
}
