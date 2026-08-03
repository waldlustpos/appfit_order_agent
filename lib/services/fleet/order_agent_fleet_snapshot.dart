import 'package:appfit_core/appfit_core.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:appfit_order_agent/models/store_model.dart';
import 'package:appfit_order_agent/services/monitoring/device_identity_service.dart';
import 'package:appfit_order_agent/services/preference_service.dart';
import 'package:appfit_order_agent/utils/logger.dart';

/// order_agent 전용 스냅샷 조달기. **core 승격 대상이 아니다** — 앱의
/// PreferenceService·storeProvider·DeviceIdentityService 에 의존하기 때문이다.
/// core 쪽(FleetReporter)은 이 클래스를 모르고 `Future<FleetSnapshot?>` 콜백만 안다.
///
/// 매 틱 호출되므로 값이 늦게 채워지는 문제(로그인 전 storeId 없음)가 저절로
/// 해결된다. 아직 준비가 안 됐으면 null 을 돌려주고, 리포터는 실패로 세지 않는다.
class OrderAgentFleetSnapshotBuilder {
  static const String appType = 'ORDER_AGENT';

  final DeviceIdentityService _identityService;
  final PreferenceService _prefs;
  final StoreModel? Function() _readStore;
  final Future<PackageInfo> Function() _packageInfo;
  final Future<List<ConnectivityResult>> Function() _connectivity;

  /// 소켓 연결 상태. fleetSyncProvider 가 갱신한다.
  bool socketConnected = false;

  /// 앱 라이프사이클(resumed/paused/...). fleetSyncProvider 가 갱신한다.
  /// 대시보드가 "백그라운드"와 "무응답"을 구분하는 근거.
  String lifecycle = 'resumed';

  /// 장시간 명령 진행 여부. 리포터 생성 후 배선한다(순환 참조 회피).
  bool Function()? commandRunningProbe;

  PackageInfo? _cachedPackageInfo;

  OrderAgentFleetSnapshotBuilder({
    required DeviceIdentityService identityService,
    required PreferenceService prefs,
    required StoreModel? Function() readStore,
    Future<PackageInfo> Function()? packageInfo,
    Future<List<ConnectivityResult>> Function()? connectivity,
  })  : _identityService = identityService,
        _prefs = prefs,
        _readStore = readStore,
        _packageInfo = packageInfo ?? PackageInfo.fromPlatform,
        _connectivity = connectivity ?? Connectivity().checkConnectivity;

  Future<FleetSnapshot?> build() async {
    try {
      final identity = await _identityService.resolve();
      final pkg = _cachedPackageInfo ??= await _packageInfo();
      final store = _readStore();

      // storeId 는 저장값(getId)을 정본으로 쓴다. storeProvider 는 로그인 후
      // 로드되지만 저장값은 재시작 직후에도 남아 있어, 부팅하자마자 올바른
      // 매장으로 보고된다.
      final storeId = store?.storeId ?? _prefs.getId() ?? '';
      final storeName = store?.name ?? _prefs.getStoreName() ?? '';

      return FleetSnapshot(
        device: FleetDeviceInfo(
          deviceId: identity.deviceId,
          idSource: identity.idSource,
          serial: identity.serial,
          appType: appType,
          storeId: storeId,
          storeName: storeName,
          appVersion: pkg.version,
          buildNumber: pkg.buildNumber,
          platform: identity.platform,
          osVersion: identity.osVersion,
          deviceModel: identity.deviceModel,
          deviceManufacturer: identity.deviceManufacturer,
          environment: AppFitConfig.environment.name,
        ),
        runtime: FleetRuntime(
          status: FleetStatus.online,
          lifecycle: lifecycle,
          socketConnected: socketConnected,
          mode: _prefs.getKdsMode() ? 'KDS' : 'MAIN',
          businessOpen: store?.isOpen,
          connection: await _readConnection(),
          commandRunning: commandRunningProbe?.call() ?? false,
        ),
      );
    } catch (e, s) {
      // 관제가 앱을 막으면 안 된다. 조용히 건너뛰고 다음 틱에 재시도한다.
      logger.w('[Fleet] 스냅샷 생성 실패 — 이번 틱 건너뜀', error: e, stackTrace: s);
      return null;
    }
  }

  Future<String?> _readConnection() async {
    try {
      final results = await _connectivity();
      if (results.isEmpty) return null;
      if (results.every((r) => r == ConnectivityResult.none)) return 'none';
      // 유선 > wifi > 모바일 순으로 대표값 하나만 보고한다.
      for (final preferred in [
        ConnectivityResult.ethernet,
        ConnectivityResult.wifi,
        ConnectivityResult.mobile,
      ]) {
        if (results.contains(preferred)) return preferred.name;
      }
      return results.first.name;
    } catch (_) {
      return null;
    }
  }
}
