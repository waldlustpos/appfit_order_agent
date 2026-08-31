import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:appfit_core/appfit_core.dart';
import 'package:appfit_order_agent/services/preference_service.dart';
import 'package:appfit_order_agent/services/appfit/kokonut_appfit_logger.dart';
import 'package:appfit_order_agent/services/appfit/benign_api_log_filter.dart';

/// 오류를 Sentry 로 올리는 기본 로거. 단 [BenignApiLogFilter] 가 지정한
/// "예상된" 서버 오류(미가입 조회 404 등)는 파일 로그로만 흘린다 —
/// Dio 인터셉터가 호출부보다 먼저 로깅하므로 여기서만 막을 수 있다.
AppFitLogger _makeSentryLogger() => BenignApiLogFilter(
      sentry: SentryAppFitLogger(delegate: AppfitAppFitLogger()),
      plain: AppfitAppFitLogger(),
    );

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
    logger: _makeSentryLogger(),
  );
});

/// AppFit Dio Provider (Core 사용)
final appFitDioProvider = Provider<Dio>((ref) {
  final tokenManager = ref.watch(appFitTokenManagerProvider);

  final dioProvider = AppFitDioProvider(
    tokenManager: tokenManager,
    authProvider: _AgentAuthStateProvider(),
    logger: _makeSentryLogger(),
  );

  return dioProvider.instance;
});

final appFitNotifierServiceProvider =
    NotifierProvider<AppFitNotifierNotifier, ConnectionStatus>(
        () => AppFitNotifierNotifier(logger: _makeSentryLogger()));

/// AuthStateProvider 구현체 for Dio Interceptor
///
/// kokonut은 PreferenceService를 통해 동기 접근합니다.
/// currentPassword는 동기 접근 불가로 null 반환 (저장된 토큰이 유효하면 불필요).
class _AgentAuthStateProvider implements AuthStateProvider {
  final _preferenceService = PreferenceService();

  // getId()(=KEY_MID) 가 아니라 세션 매장 ID 를 본다. KEY_MID 는 "아이디 저장"
  // 체크박스가 꺼지면 clearLoginInfo() 가 비우는 값이라, 그 상태에서는 요청 경로에
  // shopCode 가 없는 엔드포인트(/v0/shops/... , /v1/orders/{id} 등)의 인증 헤더가
  // 통째로 누락된다.
  @override
  String? get currentStoreId => _preferenceService.getActiveStoreId();

  @override
  String? get currentPassword => null;
}
