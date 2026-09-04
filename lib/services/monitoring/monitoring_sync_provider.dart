import 'dart:async';

import 'package:appfit_core/appfit_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:appfit_order_agent/providers/log_collection_provider.dart';
import 'package:appfit_order_agent/providers/preference_provider.dart';
import 'package:appfit_order_agent/providers/store_provider.dart';
import 'package:appfit_order_agent/services/monitoring/device_inventory_reporter.dart';

/// 기기 대장 주기 점검 간격. 대장 이벤트 자체는 7일에 1건이고, 이 틱은 그
/// 7일이 지났는지 **물어보기만** 한다(캐시된 identity + prefs 2회 읽기).
const Duration kDeviceInventoryTickInterval = Duration(hours: 6);

/// 매장 ↔ 기기 대장 리포터. 기기 식별 정본은 [deviceIdentityServiceProvider]
/// 하나뿐이라 Fleet·원격로그와 같은 인스턴스를 공유한다(네이티브 조회 1회).
final deviceInventoryReporterProvider = Provider<DeviceInventoryReporter>(
  (ref) => DeviceInventoryReporter(
    ref.watch(preferenceServiceProvider),
    ref.watch(deviceIdentityServiceProvider),
  ),
);

/// 매장 정보가 로드되면 MonitoringService 컨텍스트를 업데이트하는 Provider
///
/// 앱 진입점(HomeScreen 등)에서 `ref.watch(monitoringSyncProvider)` 로 활성화.
///
/// `watch` 가 아니라 `listen` 인 이유: `storeProvider` 는 영업상태 토글·리워드
/// 설정 변경에도 새 값을 낸다. watch 로 두면 그때마다 이 Provider 가 재빌드되며
/// 아래 주기 타이머가 매번 리셋돼 **6시간 틱이 영영 안 온다.**
final monitoringSyncProvider = Provider<void>((ref) {
  ref.listen(storeProvider, (prev, next) {
    final store = next.asData?.value;
    if (store == null) return;

    MonitoringService.instance.updateStoreInfo(
      storeId: store.storeId,
      storeName: store.name,
    );

    // 기기 대장 수집(정보성). 매장이 그대로면 판정 자체를 건너뛴다 — 영업상태
    // 토글까지 리포터를 깨울 이유가 없다(주기 틱이 7일 경과를 따로 본다).
    if (store.storeId == prev?.asData?.value?.storeId) return;
    unawaited(ref.read(deviceInventoryReporterProvider).report(
          storeId: store.storeId,
          storeName: store.name,
        ));
  }, fireImmediately: true);

  // 계속 켜둔 채 매장 전환도 업데이트도 없는 기기(특히 상시가동 Windows POS)는
  // storeProvider 가 값을 내지 않아 7일 규칙이 발동할 계기가 없다. 대장의
  // "지금도 살아 있다" 신호가 여기 달려 있으므로 별도 틱으로 깨운다.
  final timer = Timer.periodic(
    kDeviceInventoryTickInterval,
    (_) => unawaited(ref.read(deviceInventoryReporterProvider).report()),
  );
  ref.onDispose(timer.cancel);
});
