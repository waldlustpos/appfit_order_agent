import 'dart:io';

import 'package:flutter/services.dart';
import 'package:appfit_order_agent/utils/logger.dart';
import 'package:window_manager/window_manager.dart';

/// 플랫폼별 기능(최소화, 오버레이 등)을 추상화하여 제공하는 서비스
/// Android, Windows 등 OS별 차이를 내부에서 처리합니다.
class PlatformBridgeService {
  static final PlatformBridgeService _instance =
      PlatformBridgeService._internal();

  factory PlatformBridgeService() => _instance;

  PlatformBridgeService._internal();

  static const _channel =
      MethodChannel('co.kr.waldlust.order.receive.appfit_order_agent');

  /// 앱 최소화 (백그라운드 이동)
  Future<void> minimizeApp() async {
    try {
      if (Platform.isAndroid) {
        logger.d('[PlatformBridge] Android: 앱 백그라운드로 이동 및 오버레이 표시 요청');

        // 1. 오버레이 먼저 표시 (최소화 전에 실행하여 UI 스레드 blocking 방지)
        await showOverlay();

        // 2. 약간의 딜레이 후 백그라운드 이동 (오버레이가 뜰 시간 확보)
        await Future.delayed(const Duration(milliseconds: 100));

        // 3. 네이티브 백그라운드 이동 요청
        await _channel.invokeMethod('moveToBackground');
      } else if (Platform.isWindows) {
        logger.d('[PlatformBridge] Windows: 창 최소화 요청');
        await windowManager.minimize();
      } else {
        logger.w('[PlatformBridge] 지원하지 않는 플랫폼입니다.');
      }
    } catch (e, s) {
      logger.e('[PlatformBridge] 최소화 실패', error: e, stackTrace: s);
    }
  }

  /// 앱을 포그라운드로 가져오기
  Future<void> bringToFront() async {
    try {
      if (Platform.isAndroid) {
        logger.d('[PlatformBridge] Android: 앱 포그라운드 전환 요청');
        await _channel.invokeMethod('bringToFront');
      } else if (Platform.isWindows) {
        logger.d('[PlatformBridge] Windows: 창 복원 및 포커스 요청');
        await windowManager.restore();
        await windowManager.focus();
      }
    } catch (e, s) {
      logger.e('[PlatformBridge] 앱 포그라운드 전환 실패', error: e, stackTrace: s);
    }
  }

  /// 오버레이에 새 주문 알림 메시지 전송 (Blink 처리용)
  Future<void> notifyOrderToOverlay() async {
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod('notifyNewOrder');
        logger.d('[PlatformBridge] Android: 오버레이에 새 주문 알림 전송');
      } catch (e, s) {
        logger.e('[PlatformBridge] 오버레이 메시지 전송 실패', error: e, stackTrace: s);
      }
    }
  }

  /// 오버레이 권한 확인 및 요청
  Future<bool> requestOverlayPermission() async {
    if (Platform.isAndroid) {
      try {
        // 네이티브 메서드로 권한 확인
        final bool granted =
            await _channel.invokeMethod('checkOverlayPermission');
        if (!granted) {
          logger.i('[PlatformBridge] Android: 네이티브 오버레이 권한 요청');
          await _channel.invokeMethod('requestOverlayPermission');
          // 권한 요청 화면으로 이동했으므로, 결과는 보장할 수 없음.
          // 사용자 경험상 요청을 띄웠으면 일단 진행.
          return true;
        }
        return true;
      } catch (e, s) {
        logger.e('[PlatformBridge] 권한 확인 실패', error: e, stackTrace: s);
        return false;
      }
    }
    // Windows는 별도 오버레이 권한이 필요 없음 (Always on Top 사용)
    return true;
  }

  /// 오버레이(버블) 표시
  Future<void> showOverlay() async {
    try {
      if (Platform.isAndroid) {
        final hasPermission = await requestOverlayPermission();

        if (hasPermission) {
          logger.d('[PlatformBridge] Android: 네이티브 오버레이 표시 요청');
          await _channel.invokeMethod('showOverlay');
        } else {
          logger.w('[PlatformBridge] 오버레이 권한이 없어 표시할 수 없습니다.');
        }
      } else if (Platform.isWindows) {
        logger.d('[PlatformBridge] Windows: Always On Top 활성화 (오버레이 대체)');
        await windowManager.setAlwaysOnTop(true);
      }
    } catch (e, s) {
      logger.e('[PlatformBridge] 오버레이 표시 중 오류', error: e, stackTrace: s);
    }
  }

  /// 오버레이(버블) 숨김
  Future<void> hideOverlay() async {
    try {
      if (Platform.isAndroid) {
        logger.d('[PlatformBridge] Android: 네이티브 오버레이 숨김 요청');
        await _channel.invokeMethod('hideOverlay');
      } else if (Platform.isWindows) {
        logger.d('[PlatformBridge] Windows: Always On Top 비활성화');
        await windowManager.setAlwaysOnTop(false);
      }
    } catch (e, s) {
      logger.e('[PlatformBridge] 오버레이 숨김 실패', error: e, stackTrace: s);
    }
  }

  /// 오버레이 활성 상태 확인 (네이티브 상태를 확인하기 어려우므로 항상 false 반환하거나, 별도 추적 필요)
  Future<bool> isOverlayActive() async {
    if (Platform.isWindows) {
      return await windowManager.isAlwaysOnTop();
    }
    return false;
  }
}
