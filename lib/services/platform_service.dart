import 'dart:io';

import 'package:flutter/services.dart';
import 'package:appfit_order_agent/utils/logger.dart';
import 'package:appfit_order_agent/services/platform_bridge_service.dart';
import 'package:appfit_order_agent/services/overlay_service.dart';
import 'package:appfit_order_agent/services/windows_log_file_writer.dart';
import 'package:appfit_order_agent/services/windows_restart_service.dart';
import 'package:launch_at_startup/launch_at_startup.dart';

// win32 는 Android 에서 kernel32.dll lookup 크래시를 일으켜 deferred 로만
// 참조한다 (com_port_descriptor.dart 주석 참고).
import 'package:appfit_order_agent/services/windows_timezone_service.dart'
    deferred as win_timezone;

const _kAppfitChannelName = 'co.kr.waldlust.order.receive.appfit_order_agent';

/// Windows 에서 Android MethodChannel 호출이 MissingPluginException 을 던지지
/// 않도록 모든 메서드를 null 반환 no-op 으로 대체한다.
class _WindowsNoopMethodChannel extends MethodChannel {
  const _WindowsNoopMethodChannel(super.name);

  @override
  Future<T?> invokeMethod<T>(String method, [dynamic arguments]) async => null;

  @override
  Future<List<T>> invokeListMethod<T>(String method,
          [dynamic arguments]) async =>
      <T>[];

  @override
  Future<Map<K, V>> invokeMapMethod<K, V>(String method,
          [dynamic arguments]) async =>
      <K, V>{};
}

final MethodChannel platform = Platform.isWindows
    ? const _WindowsNoopMethodChannel(_kAppfitChannelName)
    : const MethodChannel(_kAppfitChannelName);

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
  SOUNDGRAPH,
  FLEET,
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
  if (Platform.isWindows) {
    await WindowsLogFileWriter.appendLogsToFile(messages);
    return;
  }
  try {
    await platform.invokeMethod('logBatchToFile', {'messages': messages});
  } catch (e, s) {
    // 재귀 방지를 위해 일반 로거 대신 developer.log 또는 print 사용 고려
    // 여기서는 간단히 logger.d 사용 (Batch 작업은 빈도가 낮음)
    logger.d('ERROR calling logBatchToFile platform channel: $e \n$s');
  }
}

class PlatformService {
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

  /// WRITE_SETTINGS 권한 보유 여부 확인
  static Future<bool> checkWriteSettingsPermission() async {
    try {
      final bool? result = await platform.invokeMethod('checkWriteSettings');
      return result ?? false;
    } catch (e, s) {
      logger.e('WRITE_SETTINGS 권한 확인 중 오류 발생', error: e, stackTrace: s);
      return false;
    }
  }

  /// WRITE_SETTINGS 권한 요청 (설정 화면으로 이동)
  static Future<void> requestWriteSettingsPermission() async {
    try {
      await platform.invokeMethod('requestWriteSettings');
    } catch (e, s) {
      logger.e('WRITE_SETTINGS 권한 요청 중 오류 발생', error: e, stackTrace: s);
    }
  }

  /// 시스템 디스플레이 회전 설정 (reversed=true: 180도, false: 정상)
  static Future<bool> setSystemRotation(bool reversed) async {
    try {
      final bool? result = await platform
          .invokeMethod('setSystemRotation', {'reversed': reversed});
      return result ?? false;
    } catch (e, s) {
      logger.e('시스템 회전 설정 중 오류 발생', error: e, stackTrace: s);
      return false;
    }
  }

  /// Sunmi 내장 스캐너(바코드 스캔 버튼) 가용 여부 조회.
  /// 네이티브가 startQRScan 이 시도하는 두 intent action 을 resolve 해, 버튼이
  /// 실제로 동작하는 단말에서만 true 를 반환한다. Windows 는 noop 채널이 null 을
  /// 반환하므로 false → 버튼 미노출.
  static Future<bool> hasBuiltinScanner() async {
    try {
      return await platform.invokeMethod<bool>('hasBuiltinScanner') ?? false;
    } catch (e, s) {
      logger.w('[PlatformService] hasBuiltinScanner 실패',
          error: e, stackTrace: s);
      return false;
    }
  }

  /// 듀얼모니터(D3 MINI 전면 디스플레이) capability 조회.
  /// 보조 디스플레이 존재 여부 + 해당 브랜드(slug)의 영상/이미지 콘텐츠 존재 여부.
  /// Windows 는 noop 채널이 빈 맵을 반환하므로 모두 false → 섹션 미노출.
  static Future<Map<String, bool>> getDualMonitorCapability(String slug) async {
    try {
      final res = await platform.invokeMapMethod<String, dynamic>(
          'getDualMonitorCapability', {'slug': slug});
      final cap = {
        'hasSecondaryDisplay': res?['hasSecondaryDisplay'] == true,
        'hasVideo': res?['hasVideo'] == true,
        'hasImage': res?['hasImage'] == true,
      };
      logger.d('[DualMonitor] capability slug=$slug raw=$res -> $cap');
      return cap;
    } catch (e, s) {
      logger.e('듀얼모니터 capability 조회 중 오류 발생', error: e, stackTrace: s);
      return const {
        'hasSecondaryDisplay': false,
        'hasVideo': false,
        'hasImage': false,
      };
    }
  }

  /// 전면 모니터를 검은 화면으로 되돌린다(로그아웃 등). 네이티브가 brand slug 를
  /// 비우고 재렌더 -> 콘텐츠 없음 -> 검은 화면.
  static Future<void> clearDualMonitor() async {
    try {
      await platform.invokeMethod('clearDualMonitor');
    } catch (e, s) {
      logger.e('듀얼모니터 초기화(검은화면) 중 오류 발생', error: e, stackTrace: s);
    }
  }

  /// 듀얼모니터 콘텐츠 표시 모드 설정 ("video"/"image"/"none"). 네이티브가
  /// prefs 에 저장하고 보조 디스플레이를 즉시 다시 렌더한다.
  static Future<void> setDualMonitorMode(String mode) async {
    try {
      await platform.invokeMethod('setDualMonitorMode', {'mode': mode});
    } catch (e, s) {
      logger.e('듀얼모니터 모드 설정 중 오류 발생', error: e, stackTrace: s);
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

  /// 로그 파일(`appfit_YYYY-MM-DD.txt`)이 실제 저장된 디렉터리의 절대경로.
  ///
  /// Android: 네이티브가 `appendLogsToFile` 과 동일한 선택(공개 `Documents/appfit`
  /// 우선 → `getExternalFilesDir("logs")` fallback)으로 단일 경로를 반환한다.
  /// `path_provider` 로는 공개 Documents 경로를 얻을 수 없으므로 네이티브 정본 사용.
  /// Windows: noop 채널이 null 을 반환하므로 호출 측이 [WindowsLogFileWriter] 사용.
  static Future<String?> getLogDirPath() async {
    try {
      return await platform.invokeMethod<String>('getLogDirPath');
    } catch (e, s) {
      logger.w('[PlatformService] getLogDirPath 실패', error: e, stackTrace: s);
      return null;
    }
  }

  /// 기기 고유 시리얼(Sunmi 단말 한정, 예: `DE33256H10784`).
  ///
  /// 비-Sunmi 단말이거나 프린터 서비스 미바인딩 시 null. Windows 는 noop 채널이
  /// null 을 반환한다. 호출 측은 null 일 때 deviceId/installId 로 fallback 한다.
  static Future<String?> getDeviceSerial() async {
    try {
      return await platform.invokeMethod<String>('getDeviceSerial');
    } catch (e, s) {
      logger.w('[PlatformService] getDeviceSerial 실패', error: e, stackTrace: s);
      return null;
    }
  }

  /// 기기 타임존 ID. Android 는 IANA 형식(`"Asia/Seoul"`), Windows 는
  /// 레지스트리 키 이름(`"Korea Standard Time"`)을 반환 — 형식이 다르므로
  /// 호출 측은 부분 문자열(도시/국가명) 매칭으로 판정해야 한다. 조회 실패 시 null.
  static Future<String?> getDeviceTimezoneId() async {
    if (Platform.isWindows) {
      try {
        await win_timezone.loadLibrary();
        return win_timezone.getWindowsTimezoneKeyName();
      } catch (e, s) {
        logger.w('[PlatformService] Windows 타임존 조회 실패',
            error: e, stackTrace: s);
        return null;
      }
    }
    try {
      return await platform.invokeMethod<String>('getTimezoneId');
    } catch (e, s) {
      logger.w('[PlatformService] getDeviceTimezoneId 실패',
          error: e, stackTrace: s);
      return null;
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
  // Windows: launch_at_startup 패키지로 HKCU\...\Run 레지스트리 직접 갱신.
  // Android: native MethodChannel(setAutoStartup) 경로 유지.
  static Future<bool> setAutoStartup(bool enable) async {
    if (Platform.isWindows) {
      try {
        if (enable) {
          await LaunchAtStartup.instance.enable();
        } else {
          await LaunchAtStartup.instance.disable();
        }
        logToFile(
          tag: LogTag.SYSTEM,
          message: 'Windows 부팅 자동 실행 ${enable ? '활성화' : '비활성화'} 완료',
        );
        return true;
      } catch (e, s) {
        logger.e('Windows 자동 실행 레지스트리 변경 오류', error: e, stackTrace: s);
        return false;
      }
    }
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

  /// Android 라벨 프린터 USB 포트를 시작 시점에 미리 연다 (warm-up).
  ///
  /// Windows 의 `WindowsLabelRouter.warmupOpen` 과 같은 역할이다. 이것이 없으면
  /// 세션 최초 open 을 첫 주문의 라벨이 대신 지불하고, 실패 시 `실패 [연결오류]`
  /// 후 1.5초 뒤 재시도에서야 인쇄된다. 네이티브는 벤더(BIXOLON G30 / Caysn·REXOD)를
  /// 인쇄 경로와 **같은 규칙**으로 라우팅한다.
  ///
  /// ★ [autoReplyMode] 는 실제 인쇄가 넘기는 값과 반드시 같아야 한다
  /// (`PrintService.printLabelDetailed` 의 `getLabelAutoReplyMode()`). 다르면 첫
  /// 인쇄가 모드 불일치로 포트를 닫고 다시 열어 warm-up 이 무효가 된다.
  ///
  /// 실패해도 예외를 던지지 않는다 — 앱 시작을 막지 않고, 기존 lazy 연결이
  /// 그대로 폴백으로 남는다.
  static Future<bool> warmupLabelPrinter({required int autoReplyMode}) async {
    if (!Platform.isAndroid) return false;
    try {
      return await platform.invokeMethod<bool>(
              'warmupLabelPrinter', {'autoReplyMode': autoReplyMode}) ??
          false;
    } catch (e, s) {
      logger.w('[PlatformService] 라벨 warm-up 호출 실패', error: e, stackTrace: s);
      return false;
    }
  }

  /// 앱 재시작.
  /// - Android: 네이티브에서 새 Activity로 재부팅(AlarmManager + killProcess).
  ///   기존 동작 그대로이며 별도 정리(cleanup) 없이 즉시 종료된다.
  /// - Windows: 단일 인스턴스 뮤텍스 때문에 자기 자신을 직접 재실행할 수 없어
  ///   외부 VBS 런처(WindowsRestartService)에 위임한다. [onBeforeExit] 는
  ///   재시작 스크립트 준비가 끝난 뒤, 실제 종료 직전에 한 번 호출된다.
  ///
  /// 반환값 false = 재시작이 이뤄지지 않았고 앱은 계속 살아있다(호출 측에서
  /// 사용자에게 안내할 것).
  static Future<bool> restartApp({
    Future<void> Function()? onBeforeExit,
  }) async {
    if (Platform.isWindows) {
      return WindowsRestartService.instance.restart(
        onBeforeExit: onBeforeExit ?? () async {},
      );
    }
    try {
      await platform.invokeMethod('restartApp');
      return true;
    } on PlatformException catch (e) {
      logger.w('[PlatformService] restartApp 호출 실패: ${e.message}');
      return false;
    }
  }

  /// 플랫폼별 앱 종료. Windows는 SystemNavigator.pop()이 프로세스를 종료하지
  /// 않으므로 exit(0)을 사용한다. 호출 측에서 cleanup을 모두 마친 뒤 마지막에
  /// 호출할 것.
  static Future<void> exitApp() async {
    if (Platform.isWindows) {
      exit(0);
    }
    await SystemNavigator.pop();
  }

  /// 배치 로그 기록 (정적 메서드)
  static Future<void> logBatchToFile(List<String> messages) async {
    if (messages.isEmpty) return;
    if (Platform.isWindows) {
      await WindowsLogFileWriter.appendLogsToFile(messages);
      return;
    }
    try {
      await platform.invokeMethod('logBatchToFile', {'messages': messages});
    } catch (e, s) {
      logger.d('ERROR calling logBatchToFile static platform channel: $e \n$s');
    }
  }
}
