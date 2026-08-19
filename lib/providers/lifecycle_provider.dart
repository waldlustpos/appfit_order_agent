import 'package:flutter/widgets.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:appfit_order_agent/utils/logger.dart';
import 'package:appfit_order_agent/services/platform_service.dart';
import 'package:appfit_order_agent/providers/order/order_provider.dart';

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
        // 복귀 즉시 재동기화한다. 백그라운드에 있는 동안 폴링 타이머가 멈춰 있었을
        // 수 있고(OS 가 임의로 억제), 그렇지 않더라도 다음 틱까지 최대 60초 동안
        // 낡은 목록을 보여주게 된다. 로그아웃 상태·중복 호출은 refreshOrders
        // 내부 가드가 흡수하므로 여기서 조건을 더 걸지 않는다.
        ref.read(orderProvider.notifier).refreshOrders();
        break;
      case AppLifecycleState.inactive:
        // 예: 전화 수신 등 비활성 상태
        break;
      case AppLifecycleState.paused:
        logToFile(tag: LogTag.LIFECYCLE, message: 'App paused (background)');
        // 앱이 백그라운드로 전환될 때 필요한 작업 수행
        break;
      case AppLifecycleState.detached:
        // 종료 흔적을 파일 로그에 남긴다. 이게 없으면 "언제 죽었는지"를 사후에
        // 알 수 없다. 관제 서버로의 closing 보고는 fleetSyncProvider 가 이
        // 상태를 listen 해서 담당한다(역방향 의존을 만들지 않으려고 여기서
        // 직접 호출하지 않는다).
        logToFile(tag: LogTag.LIFECYCLE, message: 'App detached (terminating)');
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
