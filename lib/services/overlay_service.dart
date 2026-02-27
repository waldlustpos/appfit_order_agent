import 'package:kokonut_order_agent/services/platform_bridge_service.dart';
import 'package:kokonut_order_agent/utils/logger.dart';

/// 오버레이(버블)의 비즈니스 로직 및 수명 주기를 관리하는 서비스
class OverlayService {
  static final OverlayService _instance = OverlayService._internal();

  factory OverlayService() => _instance;

  OverlayService._internal();

  final _platformBridge = PlatformBridgeService();

  /// 오버레이 표시 (권한 체크 포함)
  Future<void> show() async {
    logger.d('[OverlayService] 버블 표시 요청');
    await _platformBridge.showOverlay();
  }

  /// 오버레이 숨김
  Future<void> hide() async {
    logger.d('[OverlayService] 버블 숨김 요청');
    await _platformBridge.hideOverlay();
  }

  /// 앱을 백그라운드로 보내면서 오버레이 표시 (최소화 시나리오)
  Future<void> minimizeAndShowBubble() async {
    logger.i('[OverlayService] 앱 최소화 및 버블 표시 시도');

    // 1. 오버레이 표시 (먼저 띄우고 내리기)
    await show();

    // 2. 앱 최소화
    await _platformBridge.minimizeApp();
  }

  /// 앱 활성화 시 오버레이 숨김 (포그라운드 복귀 시나리오)
  Future<void> onAppForeground() async {
    logger.d('[OverlayService] 앱 포그라운드 전환: 버블 숨김');
    await hide();
  }
}
