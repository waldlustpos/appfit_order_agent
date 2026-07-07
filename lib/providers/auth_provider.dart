import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
// import 'package:flutter_dotenv/flutter_dotenv.dart'; // Removed
import 'package:appfit_order_agent/config/app_env.dart'; // AppEnv 추가
import 'package:appfit_order_agent/providers/providers.dart';
import 'package:appfit_order_agent/utils/logger.dart';
import 'package:appfit_order_agent/services/appfit/appfit_providers.dart'; // appFitTokenManagerProvider
import 'package:appfit_order_agent/services/api_service.dart';
import 'package:appfit_order_agent/exceptions/api_error_mapper.dart'; // DioException → 친화 ApiException 변환
import 'package:appfit_order_agent/i18n/strings.g.dart'; // t (네트워크/타임아웃 i18n 폴백)
import 'package:appfit_order_agent/services/platform_service.dart'; // logToFile, LogTag 사용 위해 추가
import 'package:appfit_order_agent/services/secure_storage_service.dart'; // 로그아웃 cleanup용

import 'package:appfit_core/appfit_core.dart'
    as appfit_core; // AppFitConfig (패키지)

part 'auth_provider.g.dart';

// AuthState에서 isConnected, isConnecting 제거 (SocketState에서 가져옴)
class AuthState {
  final bool hasInternet; // SocketState에서 가져올 수도 있지만, AuthState에 유지
  final String? errorMessage;
  final ConnectionStatus connectionStatus; // 계산된 상태
  var tag = '인증';
  AuthState({
    required this.hasInternet,
    this.errorMessage,
    required this.connectionStatus,
  });

  AuthState copyWith({
    bool? hasInternet,
    String? errorMessage,
    ConnectionStatus? connectionStatus,
    bool clearError = false,
  }) {
    return AuthState(
      hasInternet: hasInternet ?? this.hasInternet,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      connectionStatus: connectionStatus ?? this.connectionStatus,
    );
  }
}

// 연결 상태를 나타내는 enum
enum ConnectionStatus { noInternet, disconnected, connecting, connected }

@Riverpod(keepAlive: true)
class Auth extends _$Auth {
  var tag = '인증';

  @override
  AuthState build() {
    // appFitNotifierServiceProvider 사용
    final appFitStatus = ref.watch(appFitNotifierServiceProvider);

    // SocketState 기반으로 ConnectionStatus 계산
    ConnectionStatus status;
    if (appFitStatus.isConnected) {
      status = ConnectionStatus.connected;
    } else {
      status = ConnectionStatus.disconnected;
    }

    // AppFit은 인터넷 연결 상태를 별도로 제공하지 않으므로 (socketService와 다름)
    // 일단 연결 여부로만 판단 or ConnectivityPlus 별도 사용 필요할수도.
    // 여기서는 socketState.hasInternet 대체로 일단 true 가정하거나 별도 provider 필요.
    // 기존 로직 유지 위해 hasInternet은 true로 고정하거나 제거.

    // 초기 AuthState 반환
    return AuthState(
      hasInternet:
          true, // AppFit assumes internet if connected or handles checks internally
      connectionStatus: status,
    );
  }

  Future<(bool, String?, String?)> login(String storeId, String password,
      {bool connectSocket = true}) async {
    // AuthState의 connectionStatus를 connecting으로 즉시 변경
    state = state.copyWith(
        connectionStatus: ConnectionStatus.connecting, clearError: true);

    // 진입부: 매장 prefix 전환 감지 — 저장된 토큰의 shopCode와 다르면
    // 이전 자격증명(토큰/비밀번호/projectId/apiKey)을 모두 정리해
    // stale 토큰 재사용 + 잘못된 Project-ID 헤더 주입을 방지한다.
    final tokenManager = ref.read(appFitTokenManagerProvider);
    final storedTokenShopCode = await tokenManager.getStoredTokenShopCode();
    if (storedTokenShopCode != null &&
        storedTokenShopCode.isNotEmpty &&
        storedTokenShopCode != storeId) {
      logToFile(
        tag: LogTag.SYSTEM,
        message:
            '[Auth] 매장 전환 감지 ($storedTokenShopCode → $storeId) — 이전 자격증명 정리',
      );
      await _cleanupCredentials(tokenManager);
    }

    try {
      // 1. AppFit (v2) Login Only

      // AuthState의 connectionStatus를 connecting으로 즉시 변경
      state = state.copyWith(
          connectionStatus: ConnectionStatus.connecting, clearError: true);

      try {
        // AppFit Token Manager를 통해 토큰 발급 (로그인)
        // 발급된 토큰은 TokenManager 가 내부 캐시/보안저장하므로 반환값은 사용하지 않음.
        await tokenManager.getValidToken(storeId, password: password);
        // 추가: 장시간 세션 토큰 갱신용 - SecureStorage에 비밀번호 보안 저장
        await tokenManager.savePassword(password);

        logToFile(
            tag: LogTag.API,
            message: '[Auth] V2 Token Acquired (shopCode=$storeId)');

        // 프로젝트 정보 및 매장 정보 조회 (API 연동 테스트)
        // Service alias used from api_service.dart
        final appFitApiService = ref.read(apiServiceProvider);

        // getProjectInfo()는 복호화된 projectId/apiKey를 반환합니다.
        // apiKey는 즉시 connect()에 사용하며, 프로젝트는 별도로 보관하지 않습니다.
        // (영구 저장은 패키지 내부의 saveProjectCredentials가 담당)
        final String projectId;
        final String apiKey;
        try {
          final projectInfo = await appFitApiService.getProjectInfo();
          projectId = projectInfo.projectId;
          apiKey = projectInfo.apiKey;
          // projectName(=브랜드명)을 로그 전송/식별 표기용으로 영속화.
          final projectName = projectInfo.data['projectName'] as String?;
          if (projectName != null && projectName.isNotEmpty) {
            await ref
                .read(preferenceServiceProvider)
                .setProjectName(projectName);
          }
          logToFile(
              tag: LogTag.API,
              message: '[Auth] V2 Project Info Validation Success');
          logToFile(
              tag: LogTag.API,
              message: '[Auth] V2 Store Info Validation Success');
        } catch (e, s) {
          logger.e('[Auth] V2 Data Fetch Failed', error: e, stackTrace: s);
          // getProjectInfo 가 친화 ApiException 을 던지므로 매퍼는 그대로 통과(멱등).
          // raw '데이터 조회 실패: $e'(긴 DioException 영문) 대신 친화 메시지 노출.
          final errorMsg =
              mapDioErrorToApiException(e, s, context: '프로젝트 정보 조회').message;
          // stale 토큰/projectId/apiKey/password 잔존 차단 — 다음 시도 깨끗한 상태
          await _cleanupCredentials(tokenManager);
          state = state.copyWith(
              connectionStatus: ConnectionStatus.disconnected,
              errorMessage: errorMsg);
          return (false, null, errorMsg);
        }

        // V2: AppFit WebSocket 연결 시작
        if (connectSocket) {
          final aesKey = AppEnv.aesKey;

          logToFile(
              tag: LogTag.SYSTEM,
              message:
                  '[Auth] WS connect 직전 env=${appfit_core.AppFitConfig.websocketUrl} '
                  'projectId.len=${projectId.length} apiKey.len=${apiKey.length} '
                  'aesKey.len=${aesKey.length}');

          if (projectId.isNotEmpty && apiKey.isNotEmpty && aesKey.isNotEmpty) {
            // AppFitNotifierService 연결
            final notifier = ref.read(appFitNotifierServiceProvider.notifier);
            await notifier.connect(
                shopCode: storeId,
                projectId: projectId,
                apiKey: apiKey,
                aesKey: aesKey);
            logToFile(
                tag: LogTag.API, message: '[Auth] AppFit WebSocket Connected');
          } else {
            logger.w('[Auth] Missing credentials for WebSocket connection');
            logToFile(
                tag: LogTag.SYSTEM,
                message:
                    '[Auth] WS connect SKIP: credentials missing (projectId.len=${projectId.length} apiKey.len=${apiKey.length})');
          }
        } else {
          logger.i('[Auth] WebSocket connection skipped by user setting');
          logToFile(
              tag: LogTag.API,
              message: '[Auth] WebSocket connection skipped details');
        }

        state = state.copyWith(connectionStatus: ConnectionStatus.connected);

        return (true, null, null);
      } catch (e, s) {
        // DioException 진단 정보 수집 (원본 보존 — 아래 logToFile 용으로 유지).
        final baseUrl = appfit_core.AppFitConfig.baseUrl;
        DioException? dioErr;
        if (e is DioException) dioErr = e;
        final diag = dioErr == null
            ? 'baseUrl=$baseUrl runtimeType=${e.runtimeType}'
            : 'baseUrl=$baseUrl type=${dioErr.type} '
                'msg=${dioErr.message} '
                'inner=${dioErr.error?.runtimeType}:${dioErr.error} '
                'status=${dioErr.response?.statusCode}';

        // 사용자 노출 메시지 결정.
        // appfit_core v1.0.13+ 부터 token_manager 가 로그인 실패 시 원본
        // DioException 을 그대로 전파하므로(과거의 평문 'Exception: 로그인 API
        // 오류:' collapse 제거), 토큰/네트워크/타임아웃 오류는 모두 매퍼가
        // 서버 message/status/type 으로 깔끔히 처리한다. else 분기는 도메인
        // 검증(비밀번호 누락 등)·WebSocket 등 비-Dio 예외용 폴백.
        String errorMsg;
        if (e is DioException) {
          errorMsg = mapDioErrorToApiException(e, s, context: '로그인').message;
        } else {
          errorMsg = e.toString().replaceAll('Exception: ', '').trim();
          if (errorMsg.isEmpty || errorMsg == 'null') {
            errorMsg = t.common.api_error.generic;
          }
        }

        logToFile(
            tag: LogTag.ERROR,
            message: '[Auth] V2 Login Failed: $e | diag=$diag');
        await _cleanupCredentials(tokenManager);
        state = state.copyWith(
            connectionStatus: ConnectionStatus.disconnected,
            errorMessage: errorMsg);
        return (false, null, errorMsg);
      }
    } catch (e, s) {
      logger.e('Native login error', error: e, stackTrace: s);
      final errorMsg = mapDioErrorToApiException(e, s, context: '로그인').message;
      await _cleanupCredentials(tokenManager);
      state = state.copyWith(
          connectionStatus: ConnectionStatus.disconnected,
          errorMessage: errorMsg);
      return (false, null, errorMsg);
    }
  }

  /// 로그인 진입/실패 시 자격증명 일괄 정리.
  ///
  /// 토큰(메모리+SecureStorage) + 비밀번호 + Project ID/API Key 모두 삭제해
  /// 다음 로그인 시도가 stale 자격증명 없이 깨끗한 상태에서 시작되도록 한다.
  /// best-effort: 개별 실패는 무시한다.
  Future<void> _cleanupCredentials(
      appfit_core.AppFitTokenManager tokenManager) async {
    try {
      await tokenManager.clearToken();
    } catch (_) {}
    try {
      await tokenManager.clearPassword();
    } catch (_) {}
    try {
      final secureStorage = SecureStorageService();
      await secureStorage.delete(SecureStorageService.appFitProjectId);
      await secureStorage.delete(SecureStorageService.appFitProjectApiKey);
    } catch (_) {}
  }

  /// 로그아웃 — credentials/토큰/소켓을 모두 정리하는 단일 진입점
  ///
  /// UI 계층은 이 메서드만 호출. 영업 상태 변경/OrderProvider cleanup/네비게이션
  /// 같은 UI 관련 작업은 호출자(예: HomeScreen)가 담당.
  ///
  /// 주의: `Auth.build()`가 `appFitNotifierServiceProvider`를 watch하므로,
  /// `disconnect()` 호출 후에는 dependency 변경으로 `ref.read()` 사용이 차단된다.
  /// → 모든 provider를 disconnect 호출 전에 미리 read해 둔다.
  Future<void> logout() async {
    try {
      // ⭐ 모든 의존성을 dependency 변경 전에 미리 캐시
      final notifier = ref.read(appFitNotifierServiceProvider.notifier);
      final tokenManager = ref.read(appFitTokenManagerProvider);
      final preferenceService = ref.read(preferenceServiceProvider);
      final secureStorage = SecureStorageService();

      // 1. WebSocket 연결 종료 (이 시점부터 Auth dependency가 outdated 될 수 있음)
      notifier.disconnect();

      // 2. JWT 토큰 / 비밀번호 삭제 (캐시된 tokenManager 사용 — ref 미접근)
      await tokenManager.clearToken();
      await tokenManager.clearPassword();

      // 3. SecureStorage의 projectId/apiKey cleanup
      //    (값을 read하지 않고 키 이름으로 delete만 수행 — core 보안 원칙 준수)
      await secureStorage.delete(SecureStorageService.appFitProjectId);
      await secureStorage.delete(SecureStorageService.appFitProjectApiKey);

      // 4. 로그인 정보(SharedPreferences) 정리 (캐시된 preferenceService 사용)
      await preferenceService.clearLoginInfo();

      // 5. 전면(듀얼) 모니터 검은 화면 처리 (흰 이미지 배경 등이 남지 않도록)
      await PlatformService.clearDualMonitor();

      logToFile(tag: LogTag.SYSTEM, message: '[Auth] 로그아웃 cleanup 완료');
    } catch (e, s) {
      logger.e('[Auth] 로그아웃 처리 중 오류', error: e, stackTrace: s);
    }
  }

  /// 환경 변경 시 호출 — WebSocket 연결만 해제 (앱 재시작 없이 로그인 화면으로 이동)
  void unauthenticate() {
    ref.read(appFitNotifierServiceProvider.notifier).disconnect();
  }

  Future<void> reconnect() async {
    logger.i('[Auth] 수동/라이프사이클 재연결 요청');
    try {
      final aesKey = AppEnv.aesKey;
      final storeId = ref.read(preferenceServiceProvider).getId() ?? '';

      if (storeId.isEmpty || aesKey.isEmpty) {
        logger.w('[Auth] 재연결 실패: storeId/aesKey 없음');
        return;
      }

      // apiKey는 프로젝트가 보관하지 않으므로, getProjectInfo()를 다시 호출해
      // 신선한 projectId/apiKey를 받아 connect에 사용한다.
      final projectInfo = await ref.read(apiServiceProvider).getProjectInfo();
      final projectId = projectInfo.projectId;
      final apiKey = projectInfo.apiKey;
      // projectName(=브랜드명) 최신값 영속화(로그인 이후 변경 반영).
      final projectName = projectInfo.data['projectName'] as String?;
      if (projectName != null && projectName.isNotEmpty) {
        await ref.read(preferenceServiceProvider).setProjectName(projectName);
      }

      if (projectId.isNotEmpty && apiKey.isNotEmpty) {
        await ref.read(appFitNotifierServiceProvider.notifier).connect(
              shopCode: storeId,
              projectId: projectId,
              apiKey: apiKey,
              aesKey: aesKey,
            );
        logToFile(tag: LogTag.API, message: '[Auth] 재연결 완료');
      } else {
        logger.w('[Auth] 재연결 실패: 자격증명 불충분');
      }
    } catch (e, s) {
      logger.e('[Auth] 재연결 오류', error: e, stackTrace: s);
    }
  }
}

// 기존 Provider 정의 삭제 (Generator가 자동으로 생성)
