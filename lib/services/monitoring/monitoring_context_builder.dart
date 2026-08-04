import 'dart:io';

import 'package:appfit_core/appfit_core.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:appfit_order_agent/services/monitoring/order_agent_monitoring_context.dart';
import 'package:appfit_order_agent/utils/logger.dart';

/// 기기/앱/현재 서버 환경 정보를 모아 [OrderAgentMonitoringContext] 를 만든다.
///
/// 앱 부팅 시(main.dart)와 런타임 중 서버 환경이 바뀌는 시점(로그인 화면 매장 ID
/// 프리픽스 자동 전환, 설정 화면 수동 전환) 양쪽에서 호출된다. `environment` 는
/// 호출 시점의 [AppFitConfig.environment] 를 그대로 반영하므로, 환경 전환 직후
/// 다시 호출하면 최신 값으로 갱신된 컨텍스트를 얻는다.
Future<OrderAgentMonitoringContext> buildOrderAgentMonitoringContext() async {
  String deviceModel = 'Unknown';
  String deviceManufacturer = 'Unknown';
  String appVersion = '';
  String buildNumber = '';

  try {
    final deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final info = await deviceInfo.androidInfo;
      deviceModel = info.model;
      deviceManufacturer = info.manufacturer;
    } else if (Platform.isIOS) {
      final info = await deviceInfo.iosInfo;
      deviceModel = info.model;
      deviceManufacturer = 'Apple';
    } else if (Platform.isWindows) {
      final info = await deviceInfo.windowsInfo;
      deviceModel = info.computerName;
      deviceManufacturer = 'Microsoft';
    }
  } catch (e) {
    logger.d('Failed to get device info: $e');
  }

  try {
    final pkgInfo = await PackageInfo.fromPlatform();
    appVersion = pkgInfo.version;
    buildNumber = pkgInfo.buildNumber;
  } catch (e) {
    logger.d('Failed to get package info: $e');
  }

  return OrderAgentMonitoringContext(
    appVersion: appVersion,
    buildNumber: buildNumber,
    deviceModel: deviceModel,
    deviceManufacturer: deviceManufacturer,
    environment: AppFitConfig.environment.name,
  );
}
