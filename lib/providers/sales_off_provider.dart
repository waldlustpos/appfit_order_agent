import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:appfit_order_agent/providers/lifecycle_provider.dart';
import 'package:appfit_order_agent/services/shutdown_signal_service.dart';

final shutdownSalesOffSenderProvider = Provider<ShutdownSalesOffSender>(
  (ref) => ShutdownSalesOffSender(ref),
);

/// 종료 시 매장을 CLOSED(오더 준비중)로 내리는 두 경로를 배선한다.
/// `MyApp.build()` 에서 watch 한다 — `fleetSyncProvider` 와 같은 자리다.
///
/// ① 기기 전원종료: 네이티브 `ShutdownSalesOffBridge` 가 `ACTION_SHUTDOWN` 을
///    받아 MethodChannel 로 요청한다. 실측(2026-09-04, T2mini A7 · D3mini A13)
///    상 그 시점에도 네트워크는 validated 상태이고 Dart 왕복은 1~3ms 다.
/// ② 앱 종료(스와이프·Activity 파괴): 라이프사이클 `detached`.
///    전원종료 시엔 detached 가 오지 않으므로 두 경로는 겹치지 않지만,
///    [ShutdownSalesOffSender] 가 1회성 가드로 중복 전송을 막는다.
///
/// 종료 버튼·로그아웃 경로는 예전부터 `home_screen` 이 직접 처리한다. 여기서
/// 다시 다루지 않는다.
final salesOffSyncProvider = Provider<void>((ref) {
  final sender = ref.watch(shutdownSalesOffSenderProvider);
  sender.attachNativeHandler();

  // detached 시점 이후 엔진이 곧 사라지므로 결과를 기다리지 않는다. fleet 의
  // reportClosing 도 같은 자리에서 같은 방식으로 발사된다.
  ref.listen<AppLifecycleState>(appLifecycleObserverProvider, (_, next) {
    if (next == AppLifecycleState.detached) {
      unawaited(sender.sendSalesOff(reason: 'detached'));
    }
  });
});
