import 'package:appfit_core/appfit_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:appfit_order_agent/config/app_env.dart';
import 'package:appfit_order_agent/providers/lifecycle_provider.dart';
import 'package:appfit_order_agent/providers/log_collection_provider.dart';
import 'package:appfit_order_agent/providers/preference_provider.dart';
import 'package:appfit_order_agent/providers/store_provider.dart';
import 'package:appfit_order_agent/services/appfit/appfit_providers.dart';
import 'package:appfit_order_agent/services/appfit/kokonut_appfit_logger.dart';
import 'package:appfit_order_agent/services/fleet/fleet_store_allowlist_service.dart';
import 'package:appfit_order_agent/services/fleet/order_agent_fleet_command_handler.dart';
import 'package:appfit_order_agent/services/fleet/order_agent_fleet_snapshot.dart';
import 'package:appfit_order_agent/services/platform_service.dart';

AppFitLogger _fleetLogger() =>
    SentryAppFitLogger(delegate: AppfitAppFitLogger());

final fleetStoreAllowlistServiceProvider =
    Provider<FleetStoreAllowlistService>((ref) {
  return FleetStoreAllowlistService(ref.watch(preferenceServiceProvider));
});

/// 이 기기가 관제 **대상 매장**에 속하는지.
///
/// 앱 시작 시에는 캐시된 목록과 저장된 매장 코드([PreferenceService.getId])로
/// 시드한다. 로그인 성공 시 [reconcileFleetTarget] 가 원격 목록을 다시 받아
/// 갱신한다.
///
/// 시작 시 시드가 필요한 이유: 로그인 훅만 두면 **로그인에 실패한 기기**가
/// 대시보드에서 통째로 사라진다. 그게 오히려 가장 먼저 확인하고 싶은 상태다.
/// 저장된 매장 코드는 재시작 직후에도 남아 있으므로 파일럿 매장 한정으로
/// 로그인 전 구간의 보고가 유지된다.
final fleetTargetedProvider = StateProvider<bool>((ref) {
  final service = ref.watch(fleetStoreAllowlistServiceProvider);
  final storeId = ref.watch(preferenceServiceProvider).getId();
  return service.isTargeted(storeId);
});

/// 관제 기동의 최종 판정 = **빌드 타임 설정 AND 런타임 대상 매장**.
///
/// 두 게이트의 역할이 다르다. [AppEnv.hasFleetConfig] 는 "이 빌드가 관제를
/// 말할 수 있는가"(`.env` 미주입 빌드 보호), [fleetTargetedProvider] 는
/// "이 매장이 지금 관제 대상인가"(파일럿 범위 제어)다.
final fleetEnabledProvider = Provider<bool>((ref) {
  return AppEnv.hasFleetConfig && ref.watch(fleetTargetedProvider);
});

/// 로그인 성공 시 호출. 원격 목록을 재조회하고 대상 여부를 갱신한다.
///
/// 로그인 흐름을 막지 않도록 호출부에서 fire-and-forget 으로 쓴다. 조회가
/// 실패해도 캐시로 판정하므로 결과는 항상 나온다.
Future<void> reconcileFleetTarget(
  FleetStoreAllowlistService service,
  StateController<bool> targeted,
  String storeId,
) async {
  await service.refresh();
  final next = service.isTargeted(storeId);
  if (targeted.state != next) {
    logToFile(
      tag: LogTag.FLEET,
      message: '대상 매장 판정 변경: $storeId → ${next ? '대상' : '비대상'}',
    );
  }
  targeted.state = next;
}

/// 앱바 아이콘이 watch 하는 관제 연결 상태. 최초값은 게이트로 정하고,
/// 이후 register/heartbeat 결과는 [fleetSinkProvider] 의 [ObservingFleetSink]
/// 가 갱신한다. 게이트가 꺼지면 이 provider 가 재빌드되며 `disabled` 로
/// 리셋되고, 앱바 아이콘은 그 값으로 자동으로 숨는다.
final fleetConnectionStatusProvider = StateProvider<FleetConnectionStatus>(
  (ref) => ref.watch(fleetEnabledProvider)
      ? FleetConnectionStatus.connecting
      : FleetConnectionStatus.disabled,
);

/// 기기 보고의 전송 목적지. **단일 교체 지점**이다
/// (logUploadSinkProvider 와 같은 패턴).
///
/// 설정이 없거나 대상 매장이 아니면 [NoopFleetSink] 로 폴백해 관제만 꺼지고
/// 앱 동작은 그대로다. 여기에 `kReleaseMode` 가드를 넣으면 안 된다 — 매장
/// 출고본에서만 정확히 동작하지 않는, 가장 발견이 늦는 버그가 된다.
final fleetSinkProvider = Provider<FleetSink>((ref) {
  if (!AppEnv.hasFleetConfig) {
    logToFile(
      tag: LogTag.FLEET,
      message: '설정 없음 — 관제 보고 비활성 (FLEET_BASE_URL/FLEET_DEVICE_KEY 미주입)',
    );
    return NoopFleetSink(logger: _fleetLogger());
  }
  if (!ref.watch(fleetEnabledProvider)) {
    logToFile(
      tag: LogTag.FLEET,
      message: '대상 매장 아님 — 관제 보고 비활성',
    );
    return NoopFleetSink(logger: _fleetLogger());
  }
  logToFile(
    tag: LogTag.FLEET,
    message: '관제 보고 활성화 (baseUrl=${AppEnv.fleetBaseUrl})',
  );
  // 대상 매장 게이트가 뒤집히면 이 provider 가 재빌드되며 여기 캡처된 ref 가
  // 무효해진다. 그런데 구 sink 의 in-flight 요청은 그 뒤에 완료돼 onStatus 를
  // 부를 수 있다 — 그때 dispose 된 ref 를 읽으면 예외가 난다. 게이트가 생기기
  // 전에는 이 provider 가 재빌드될 일이 없어서 없던 경로다.
  var disposed = false;
  ref.onDispose(() => disposed = true);
  return ObservingFleetSink(
    inner: HttpFleetSink(
      baseUrl: AppEnv.fleetBaseUrl,
      deviceKey: AppEnv.fleetDeviceKey,
      logger: _fleetLogger(),
    ),
    onStatus: (status) {
      if (disposed) return;
      final prev = ref.read(fleetConnectionStatusProvider);
      if (prev != status) {
        logToFile(
          tag: LogTag.FLEET,
          message: '연결 상태 전환: ${prev.name} → ${status.name}',
        );
      }
      ref.read(fleetConnectionStatusProvider.notifier).state = status;
    },
  );
});

final fleetSnapshotBuilderProvider =
    Provider<OrderAgentFleetSnapshotBuilder>((ref) {
  return OrderAgentFleetSnapshotBuilder(
    identityService: ref.watch(deviceIdentityServiceProvider),
    prefs: ref.watch(preferenceServiceProvider),
    readStore: () => ref.read(storeProvider).value,
  );
});

final fleetCommandHandlerProvider =
    Provider<OrderAgentFleetCommandHandler>((ref) {
  return OrderAgentFleetCommandHandler(
    logCollection: ref.watch(logCollectionServiceProvider),
    identityService: ref.watch(deviceIdentityServiceProvider),
    readStoreName: () => ref.read(storeProvider).value?.name,
  );
});

final fleetReporterProvider = Provider<FleetReporter>((ref) {
  final builder = ref.watch(fleetSnapshotBuilderProvider);
  final reporter = FleetReporter(
    sink: ref.watch(fleetSinkProvider),
    snapshotBuilder: builder.build,
    commandHandler: ref.watch(fleetCommandHandlerProvider).handle,
    logger: _fleetLogger(),
    // 정전 복구로 매장 기기가 한꺼번에 부팅할 때 첫 보고가 동시에 몰리지 않게.
    jitterMs: 15000,
  );
  // 순환 참조를 피하려고 생성 후에 배선한다(builder → reporter → builder).
  builder.commandRunningProbe = () => reporter.isCommandRunning;
  ref.onDispose(reporter.stop);
  return reporter;
});

/// 리포터를 켜고 외부 신호를 연결한다. `MyApp.build()` 에서 watch 한다.
///
/// **home_screen 이 아니라 MyApp 인 이유**: 로그인 화면에 머무는 기기(설치했는데
/// 로그인이 안 된 기기)가 관제에서 통째로 사라지면 안 된다. 그게 오히려 가장
/// 먼저 확인하고 싶은 상태다. 로그인 전에는 storeId 가 빈 문자열로 보고되고
/// 서버가 "미배정" 버킷으로 묶는다.
///
/// 대상 매장이 아니면 타이머 자체를 돌리지 않는다. 게이트가 뒤집히면
/// sink → reporter → 여기로 재빌드가 연쇄하고, 구 reporter 는
/// [fleetReporterProvider] 의 `onDispose` 가 정리한다.
final fleetSyncProvider = Provider<void>((ref) {
  final enabled = ref.watch(fleetEnabledProvider);
  final reporter = ref.watch(fleetReporterProvider);
  if (!enabled) {
    if (reporter.isRunning) reporter.stop();
    return;
  }
  if (!reporter.isRunning) reporter.start();

  // ① 매장 재바인딩. 매장이 바뀌면 캐시된 기기 식별 정보(매장명/코드)가 stale
  //    이 되므로 함께 무효화한다 — invalidate() 호출처가 여기 생기기 전까지
  //    0개였고, 그래서 매장 전환 후에도 옛 매장명이 남아 있었다.
  ref.listen(storeProvider, (prev, next) {
    final storeId = next.value?.storeId;
    if (storeId == null || storeId.isEmpty) return;
    if (storeId == prev?.value?.storeId) return;

    logToFile(tag: LogTag.FLEET, message: '매장 전환 감지 → 재등록 ($storeId)');
    ref.read(deviceIdentityServiceProvider).invalidate();
    reporter.invalidateRegistration();
    reporter.flushNow();
  });

  // ② 소켓 연결 상태를 스냅샷에 반영.
  ref.listen(appFitNotifierServiceProvider, (_, status) {
    ref.read(fleetSnapshotBuilderProvider).socketConnected = status.isConnected;
  });

  // ③ 라이프사이클. detached 에서만 closing 을 보낸다 — paused 는 Android
  //    오버레이 버블 때문에 상시 발생해서 대시보드가 "종료 중"으로 도배된다.
  ref.listen<AppLifecycleState>(appLifecycleObserverProvider, (_, next) {
    ref.read(fleetSnapshotBuilderProvider).lifecycle = next.name;
    if (next == AppLifecycleState.detached) {
      reporter.reportClosing();
    }
  });
});
