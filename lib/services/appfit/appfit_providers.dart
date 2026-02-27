import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:appfit_core/appfit_core.dart';
import '../preference_service.dart';
import 'kokonut_appfit_logger.dart';

/// AppFit TokenManager Provider (Core 사용)
///
/// appfit_core의 AppFitConfig.configure()에서 설정된 baseUrl을 사용합니다.
final appFitTokenManagerProvider = Provider<AppFitTokenManager>((ref) {
  if (!AppFitConfig.isConfigured()) {
    throw Exception('AppFitConfig가 초기화되지 않았습니다.');
  }

  return AppFitTokenManager(
    projectId: '', // 런타임에 saveProjectCredentials()로 SecureStorage에서 관리
    baseUrl: AppFitConfig.baseUrl,
    logger: AppfitAppFitLogger(),
  );
});

/// AppFit Dio Provider (Core 사용)
final appFitDioProvider = Provider<Dio>((ref) {
  final tokenManager = ref.watch(appFitTokenManagerProvider);

  final dioProvider = AppFitDioProvider(
    tokenManager: tokenManager,
    authProvider: _AgentAuthStateProvider(),
    logger: AppfitAppFitLogger(),
  );

  return dioProvider.instance;
});

/// AppFit Notifier 서비스 Notifier (thin wrapper)
///
/// 재연결 로직은 appfit_core의 AppFitNotifierService 내부에서 완전히 처리됩니다.
/// 앱 레이어는 connect() / disconnect() 만 호출합니다.
class AppFitNotifierNotifier extends Notifier<ConnectionStatus> {
  late final AppFitNotifierService _coreService;
  StreamSubscription<ConnectionStatus>? _connectionStateSubscription;

  /// 연결된 매장 코드 (Getter)
  String? get cachedShopCode => _coreService.cachedShopCode;

  /// 주문 알림 스트림 (Getter)
  Stream<Map<String, dynamic>> get stream => _coreService.stream;

  @override
  ConnectionStatus build() {
    _coreService = AppFitNotifierService(logger: AppfitAppFitLogger());
    _connectionStateSubscription = _coreService.connectionStateStream.listen(
      (status) => state = status,
    );
    ref.onDispose(() {
      _connectionStateSubscription?.cancel();
      _coreService.dispose();
    });
    return ConnectionStatus.disconnected;
  }

  Future<void> connect({
    required String shopCode,
    required String projectId,
    required String apiKey,
    required String aesKey,
  }) async =>
      _coreService.connect(
        shopCode: shopCode,
        projectId: projectId,
        apiKey: apiKey,
        aesKey: aesKey,
      );

  void disconnect() => _coreService.disconnect();
}

final appFitNotifierServiceProvider =
    NotifierProvider<AppFitNotifierNotifier, ConnectionStatus>(
        AppFitNotifierNotifier.new);

/// AuthStateProvider 구현체 for Dio Interceptor
///
/// kokonut은 PreferenceService를 통해 동기 접근합니다.
/// currentPassword는 동기 접근 불가로 null 반환 (저장된 토큰이 유효하면 불필요).
class _AgentAuthStateProvider implements AuthStateProvider {
  final _preferenceService = PreferenceService();

  @override
  String? get currentStoreId => _preferenceService.getId();

  @override
  String? get currentPassword => null;
}