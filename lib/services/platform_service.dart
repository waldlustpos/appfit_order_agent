import 'package:flutter/services.dart';
import 'package:kokonut_order_agent/utils/logger.dart';
import 'package:kokonut_order_agent/services/platform_bridge_service.dart';
import 'package:kokonut_order_agent/services/overlay_service.dart';

const platform =
    MethodChannel('co.kr.waldlust.order.receive.kokonut_order_agent');

enum LogTag {
  UI_ACTION,
  NAVIGATION,
  LIFECYCLE,
  STATE,
  API,
  WEBSOCKET,
  STORAGE,
  PLATFORM,
  SYSTEM,
  ERROR,
  WARNING,
}

Future<void> logToFile({required LogTag tag, required String message}) async {
  String msg = '[${tag.name}] $message';
  switch (tag) {
    case LogTag.ERROR:
      logger.e(msg);
      break;
    case LogTag.WARNING:
      logger.w(msg);
      break;
    default:
      logger.d(msg);
  }
}

/// 배치 로그를 네이티브 파일로 기록
Future<void> logBatchToFile({required List<String> messages}) async {
  if (messages.isEmpty) return;
  try {
    await platform.invokeMethod('logBatchToFile', {'messages': messages});
  } catch (e, s) {
    // 재귀 방지를 위해 일반 로거 대신 developer.log 또는 print 사용 고려
    // 여기서는 간단히 logger.d 사용 (Batch 작업은 빈도가 낮음)
    logger.d('ERROR calling logBatchToFile platform channel: $e \n$s');
  }
}

class PlatformService {
  static Future<Map<String, dynamic>?> getLegacyPreferences() async {
    // 레거시 NDK 제거로 인해 더 이상 지원하지 않음
    return null;
  }

  /// 레거시 데이터 접근 가능 여부를 확인 (더 이상 사용되지 않음)
  static Future<bool> checkLegacyDataAccess() async {
    return false;
  }

  /// 레거시 데이터 접근 권한 요청 (더 이상 사용되지 않음)
  static Future<void> requestLegacyDataAccess() async {
    // 레거시 NDK 제거로 인해 아무 작업도 수행하지 않음
  }

  /// 대체 패키지명을 사용하여 레거시 데이터 가져오기 시도 (더 이상 사용되지 않음)
  static Future<Map<String, dynamic>?> tryAlternativeLegacyAccess() async {
    return null;
  }

  Future<bool> playNotificationSound({
    required String soundFileName,
    required int playCount,
  }) async {
    try {
      final bool result = await platform.invokeMethod('playNotificationSound', {
        'soundFileName': soundFileName,
        'playCount': playCount,
      });
      return result;
    } on PlatformException catch (e, s) {
      logger.e('알림음 재생 중 오류 발생', error: e, stackTrace: s);
      return false;
    }
  }

  static Future<bool> moveToBackground() async {
    try {
      await PlatformBridgeService().minimizeApp();
      return true;
    } catch (e, s) {
      logger.e('앱을 백그라운드로 이동하는 중 오류 발생', error: e, stackTrace: s);
      return false;
    }
  }

  static Future<void> bringToFront() async {
    await PlatformBridgeService().bringToFront();
  }

  static Future<void> notifyNewOrder() async {
    await PlatformBridgeService().notifyOrderToOverlay();
  }

  // 오버레이 권한 확인 (브릿지 서비스 위임)
  static Future<bool> checkOverlayPermission() async {
    // Bridge Service의 권한 확인 로직 사용 (request가 포함될 수 있음)
    // 순수 check만 필요한 경우 Bridge에 메서드 추가 필요하나,
    // 현재 requestOverlayPermission()이 check 후 request하는 구조임.
    // 여기서는 단순히 권한이 있는지 확인하는 용도로 사용하되, Side Effect로 요청이 뜰 수 있음을 인지.
    // 또는 패키지 특성상 check만 따로 분리할 수도 있음.
    // 일단 PlatformBridgeService().requestOverlayPermission()이 bool을 반환하므로 이를 사용.
    // (주의: 이미 권한 있으면 true 반환하고 요청창 안 뜸)
    return await PlatformBridgeService().requestOverlayPermission();
  }

  // 오버레이 권한 요청
  static Future<void> requestOverlayPermission() async {
    await PlatformBridgeService().requestOverlayPermission();
  }

  /// 네이티브 오버레이 권한 확인 (Settings.canDrawOverlays 사용)
  static Future<bool> checkOverlayPermissionNative() async {
    try {
      final bool? result =
          await platform.invokeMethod('checkOverlayPermission');
      return result ?? false;
    } catch (e, s) {
      logger.e('네이티브 오버레이 권한 확인 중 오류 발생', error: e, stackTrace: s);
      return false;
    }
  }

  /// 네이티브 오버레이 권한 요청 (Settings.ACTION_MANAGE_OVERLAY_PERMISSION 사용)
  static Future<bool> requestOverlayPermissionNative() async {
    try {
      final bool? result =
          await platform.invokeMethod('requestOverlayPermission');
      return result ?? false;
    } catch (e, s) {
      logger.e('네이티브 오버레이 권한 요청 중 오류 발생', error: e, stackTrace: s);
      return false;
    }
  }

  // 플로팅 버블 표시
  static Future<bool> showBubble() async {
    try {
      await OverlayService().show();
      return true;
    } catch (e, s) {
      logger.e('플로팅 버블 표시 중 오류 발생', error: e, stackTrace: s);
      return false;
    }
  }

  // 플로팅 버블 숨김
  static Future<bool> hideBubble() async {
    try {
      await OverlayService().hide();
      return true;
    } catch (e, s) {
      logger.e('플로팅 버블 숨김 중 오류 발생', error: e, stackTrace: s);
      return false;
    }
  }

  // 버블 위치 저장 (더 이상 사용하지 않음 or 추후 Dart 구현)
  static Future<bool> saveBubblePosition(double x, double y) async {
    // Flutter 패키지 사용 시 위치 저장을 Dart 레벨에서 해야 함.
    // 현재는 미구현 (필요 시 SharedPreferences 사용)
    return true;
  }

  // 버블 위치 불러오기
  static Future<Map<String, double>> getBubblePosition() async {
    try {
      final Map<dynamic, dynamic> result =
          await platform.invokeMethod('getBubblePosition');
      return {
        'x': result['x'] ?? 0.0,
        'y': result['y'] ?? 100.0,
      };
    } on PlatformException catch (e, s) {
      logger.e('버블 위치 불러오기 중 오류 발생', error: e, stackTrace: s);
      return {'x': 0.0, 'y': 100.0};
    }
  }

  // 파일 권한 확인 및 요청
  static Future<bool> checkAndRequestFilePermissions() async {
    try {
      final bool? granted =
          await platform.invokeMethod('checkAndRequestFilePermissions');
      logger.d('Platform checkAndRequestFilePermissions result: $granted');
      return granted ?? false;
    } on PlatformException catch (e, s) {
      logger.e('Error check/request file permissions via platform',
          error: e, stackTrace: s);
      return false; // 오류 발생 시 false 반환
    } catch (e, s) {
      logger.e('Error calling checkAndRequestFilePermissions platform channel',
          error: e, stackTrace: s);
      return false;
    }
  }

  // 앱 설정 화면 열기
  static Future<void> openAppSettings() async {
    try {
      await platform.invokeMethod('openAppSettings');
    } on PlatformException catch (e, s) {
      logger.e('Error opening app settings', error: e, stackTrace: s);
    } catch (e, s) {
      logger.e('Error calling openAppSettings platform channel',
          error: e, stackTrace: s);
    }
  }

  // Android SDK 버전 가져오기
  static Future<int> getAndroidSdkVersion() async {
    try {
      final int? version = await platform.invokeMethod('getAndroidSdkVersion');
      return version ?? 0;
    } on PlatformException catch (e, s) {
      logger.e('Error getting Android SDK version', error: e, stackTrace: s);
      return 0; // 오류 시 기본값 0 반환
    } catch (e, s) {
      logger.e('Error calling getAndroidSdkVersion platform channel',
          error: e, stackTrace: s);
      return 0;
    }
  }

  // 네트워크 연결 타입 확인 (WiFi/Ethernet/Other)
  static Future<String> getNetworkConnectionType() async {
    try {
      final String? connectionType =
          await platform.invokeMethod('getNetworkConnectionType');
      logger.d('Network connection type: $connectionType');
      return connectionType ?? 'UNKNOWN';
    } on PlatformException catch (e, s) {
      logger.e('Error getting network connection type',
          error: e, stackTrace: s);
      return 'UNKNOWN';
    } catch (e, s) {
      logger.e('Error calling getNetworkConnectionType platform channel',
          error: e, stackTrace: s);
      return 'UNKNOWN';
    }
  }

  // 부팅 시 자동 실행 설정/해제
  static Future<bool> setAutoStartup(bool enable) async {
    try {
      final result = await platform.invokeMethod('setAutoStartup', {
        'enable': enable,
      });
      logToFile(
        tag: LogTag.SYSTEM,
        message: '부팅 시 자동 실행 ${enable ? '활성화' : '비활성화'} 요청 결과: $result',
      );
      return result ?? false;
    } on PlatformException catch (e, s) {
      logger.e('부팅 시 자동 실행 설정 중 오류 발생', error: e, stackTrace: s);
      return false;
    }
  }

  /// 구 앱의 주문번호 기록 파일(Downloads/appfit/orderNum/current_num.txt)에서 마지막 주문번호를 읽음 (더 이상 사용되지 않음)
  static Future<String?> readLastOrderNumberFromLegacyFile() async {
    return null;
  }

  /// 연결된 USB 디바이스 목록 가져오기
  static Future<List<Map<String, dynamic>>> getConnectedUsbDevices() async {
    try {
      final List<dynamic>? result =
          await platform.invokeMethod('getConnectedUsbDevices');
      if (result == null) return [];

      return result.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e, s) {
      logger.e('USB 디바이스 목록 조회 중 오류 발생', error: e, stackTrace: s);
      return [];
    }
  }

  /// 배치 로그 기록 (정적 메서드)
  static Future<void> logBatchToFile(List<String> messages) async {
    if (messages.isEmpty) return;
    try {
      await platform.invokeMethod('logBatchToFile', {'messages': messages});
    } catch (e, s) {
      logger.d('ERROR calling logBatchToFile static platform channel: $e \n$s');
    }
  }
}
