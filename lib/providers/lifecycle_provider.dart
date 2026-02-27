import 'package:flutter/widgets.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:kokonut_order_agent/utils/logger.dart';
import 'package:kokonut_order_agent/services/platform_service.dart';

part 'lifecycle_provider.g.dart';

// 앱 라이프사이클 상태를 관찰하고 제공하는 Notifier
@Riverpod(keepAlive: true)
class AppLifecycleObserver extends _$AppLifecycleObserver
    with WidgetsBindingObserver {
  @override
  AppLifecycleState build() {
    // 초기 상태는 WidgetsBinding에서 가져옴
    final initialState =
        WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
    // Observer 등록
    WidgetsBinding.instance.addObserver(this);
    // Notifier가 dispose될 때 observer 제거
    ref.onDispose(() {
      WidgetsBinding.instance.removeObserver(this);
      logger.i('AppLifecycleObserver disposed');
    });
    logger.i('AppLifecycleObserver initialized with state: $initialState');
    return initialState;
  }

  // 라이프사이클 상태 변경 시 호출됨
  @override
  void didChangeAppLifecycleState(AppLifecycleState newState) {
    logger.i('App lifecycle changed from ${state.name} to ${newState.name}');

    switch (newState) {
      case AppLifecycleState.resumed:
        logToFile(tag: LogTag.LIFECYCLE, message: 'App resumed (foreground)');
        // 앱이 다시 활성화될 때 필요한 작업 수행 (예: 데이터 새로고침)
        // 이 부분은 HomeScreen에서 ref.watch(appLifecycleObserverProvider)를 통해 상태 변경을 감지하고 처리할 수 있습니다.
        // 또는 특정 프로바이더의 데이터를 여기서 직접 refresh 할 수도 있습니다.
        // 예: ref.read(orderProvider.notifier).refreshOrders(); (필요시)
        break;
      case AppLifecycleState.inactive:
        // 예: 전화 수신 등 비활성 상태
        break;
      case AppLifecycleState.paused:
        logToFile(tag: LogTag.LIFECYCLE, message: 'App paused (background)');
        // 앱이 백그라운드로 전환될 때 필요한 작업 수행
        break;
      case AppLifecycleState.detached:

        break;
      case AppLifecycleState.hidden:
        // 앱이 숨겨진 상태 (예: 다른 앱 위에 표시될 때)
        break;
    }

    // 상태 업데이트
    state = newState;
    super.didChangeAppLifecycleState(newState);
  }



  // 앱 종료 시 호출할 수 있는 메서드 (main.dart 에서도 사용 가능하도록 public 으로 변경)
  Future<void> uploadLogsOnExit() async {
    logToFile(tag: LogTag.SYSTEM, message: '앱 종료 전 로그 업로드 시작');
    logToFile(tag: LogTag.SYSTEM, message: '앱 종료 전 로그 업로드 완료');
  }
}
