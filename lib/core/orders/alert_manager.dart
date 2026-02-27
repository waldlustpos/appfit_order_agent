import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/providers.dart';
import '../../utils/logger.dart';
import '../../services/platform_bridge_service.dart';
// import '../../services/platform_service.dart'; // Unused
import 'sound_service.dart'; // Import SoundService (relative import since same directory)

class AlertManager {
  final Ref ref;

  AlertManager(this.ref);

  /// 신규 주문 알림 발생 (통합 진입점)
  /// [playSound] : 소리 재생 여부 (기본값 true)
  /// [triggerOverlay] : 오버레이(버블) 알림 여부 (기본값 true)
  /// [triggerAppBar] : 앱바 깜빡임 여부 (기본값 true)
  void triggerNewOrderAlert({
    bool playSound = true,
    bool triggerOverlay = true,
    bool triggerAppBar = true,
  }) {
    logger.d(
        '[AlertManager] 알림 발생 요청 - Sound: $playSound, Overlay: $triggerOverlay, AppBar: $triggerAppBar');

    // 1. 소리 재생
    if (playSound) {
      _playSound();
    }

    // 2. 앱바 깜빡임 시작 (BlinkStateNotifier가 카운트 기반으로 동작하므로 카운트가 0보다 크면 자동 시작될 수 있음)
    if (triggerAppBar) {
      ref.read(blinkStateProvider.notifier).startBlinking();
    }

    // 3. 오버레이(버블) 알림 전송 (앱이 백그라운드일 때 유효)
    if (triggerOverlay) {
      _triggerOverlayAlert();
    }
  }

  /// 모든 알림 중지 (사용자 확인 시)
  void stopAlert() {
    logger.d('[AlertManager] 모든 알림 중지 요청');

    // 1. 앱바 깜빡임 및 소리 중지 (BlinkStateNotifier.stopBlinking 내에서 처리됨)
    // 기존 로직: blinkStateProvider.notifier.stopBlinking()이 소리 중지 플래그도 설정함.
    ref.read(blinkStateProvider.notifier).stopBlinking();

    // 2. 소리 강제 중지 (OrderProvider 등을 통해 제어되던 부분)
    // BlinkStateNotifier가 소리 중지를 담당하지만, 명시적으로 확실히 끄기 위해 추가 로직이 필요할 수 있음.
    // 현재 구조상 OrderProvider가 AudioPlayer를 들고 있으므로, OrderProvider에 중지 요청을 보내야 함.
    // 하지만 순환 참조 방지를 위해 여기서는 BlinkStateNotifier를 통한 상태 변경에 의존하거나,
    // 추후 AudioPlayer를 AlertManager나 별도 SoundService로 가져오는 리팩토링이 필요함.
    // 우선은 BlinkStateNotifier.stopBlinking()이 UI와 연동되어 소리를 끄도록 유도.

    // TODO: AudioPlayer 권한을 AlertManager나 SoundService로 완전히 가져오면 직접 stop 호출 가능.
    // 현재는 OrderProvider가 AudioPlayer를 소유하므로, OrderProvider가 blinkState를 보고 끄거나,
    // OrderProvider.stopBlinking() (기존 메서드)을 호출해야 함.
    // 일단 OrderProvider 수정 단계에서 이 부분을 연결할 예정.
  }

  /// 소리 재생 내부 로직
  void _playSound() {
    // 소리 재생 로직.
    // 현재 AudioPlayer가 OrderProvider에 있어 직접 제어가 어려울 수 있음.
    // 1단계: OrderProvider의 메서드를 호출하거나 (Provider 간 의존성 주의)
    // 2단계: SoundAppService를 통해 재생 (이미 존재)

    try {
      // SoundAppService 사용 (기존 코드 참고: ref.read(soundAppServiceProvider).playNotificationSound())
      ref.read(soundAppServiceProvider).playNotificationSound();
    } catch (e) {
      logger.e('[AlertManager] 소리 재생 실패', error: e);
    }
  }

  /// 오버레이 알림 전송 내부 로직
  void _triggerOverlayAlert() {
    try {
      final appLifecycleState = ref.read(appLifecycleObserverProvider);

      // 앱이 포그라운드(resumed) 상태가 아닐 때만 오버레이 알림 전송
      if (appLifecycleState != AppLifecycleState.resumed) {
        logger.d(
            '[AlertManager] App is not resumed ($appLifecycleState), triggering overlay.');
        PlatformBridgeService().notifyOrderToOverlay();
      } else {
        logger.d('[AlertManager] App is resumed, skipping overlay trigger.');
      }
    } catch (e) {
      logger.e('[AlertManager] 오버레이 알림 전송 실패', error: e);
    }
  }
}

final alertManagerProvider = Provider<AlertManager>((ref) {
  return AlertManager(ref);
});
