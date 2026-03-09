import 'package:appfit_core/appfit_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/store_provider.dart';

/// 매장 정보가 로드되면 MonitoringService 컨텍스트를 업데이트하는 Provider
///
/// 앱 진입점(HomeScreen 등)에서 `ref.watch(monitoringSyncProvider)` 로 활성화.
final monitoringSyncProvider = Provider<void>((ref) {
  final storeAsync = ref.watch(storeProvider);

  storeAsync.whenData((store) {
    if (store == null) return;
    MonitoringService.instance.updateStoreInfo(
      storeId: store.storeId,
      storeName: store.name,
    );
  });
});
