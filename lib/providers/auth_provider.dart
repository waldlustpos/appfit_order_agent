import 'package:riverpod_annotation/riverpod_annotation.dart';
// import 'package:flutter_dotenv/flutter_dotenv.dart'; // Removed
import '../config/app_env.dart'; // AppEnv 추가
import 'providers.dart';
import 'package:appfit_order_agent/utils/logger.dart';
import '../services/appfit/appfit_providers.dart'; // appFitTokenManagerProvider
import '../services/api_service.dart';
import '../services/platform_service.dart'; // logToFile, LogTag 사용 위해 추가

import '../services/secure_storage_service.dart'; // SecureStorageService
import 'package:appfit_core/appfit_core.dart' as appfit_core; // AppFitConfig (패키지)

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
    if (appFitStatus == appfit_core.ConnectionStatus.connected) {
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

    try {
      // 1. AppFit (v2) Login Only

      // AuthState의 connectionStatus를 connecting으로 즉시 변경
      state = state.copyWith(
          connectionStatus: ConnectionStatus.connecting, clearError: true);

      try {
        // AppFit Token Manager를 통해 토큰 발급 (로그인)
        final tokenManager = ref.read(appFitTokenManagerProvider);
        final t = await tokenManager.getValidToken(storeId, password: password);

        logToFile(
            tag: LogTag.API, message: '[Auth] V2 Login (Token Issue) Success');

        // 프로젝트 정보 및 매장 정보 조회 (API 연동 테스트)
        // Service alias used from api_service.dart
        final appFitApiService = ref.read(appFitApiServiceProvider);

        try {
          await appFitApiService.getProjectInfo();
          logToFile(
              tag: LogTag.API,
              message: '[Auth] V2 Project Info Validation Success');

          // (확인용) 저장된 API Key 유효성 검증
          final isValid =
              await ref.read(appFitTokenManagerProvider).validateApiKey();
          if (!isValid) {
            logger.w('[Auth] API Key 유효성 검증 실패 (로그인은 진행)');
          } else {
            logger.i('[Auth] API Key 유효성 검증 완료');
          }

          logToFile(
              tag: LogTag.API,
              message: '[Auth] V2 Store Info Validation Success');
        } catch (e) {
          logger.e('[Auth] V2 Data Fetch Failed', error: e);
          // 데이터 조회 실패 시 로그만 남기고 일단 진행할지, 실패 처리할지 결정 필요
          // 현재는 테스트 단계이므로 실패로 처리하여 로그 확인 유도
          state = state.copyWith(
              connectionStatus: ConnectionStatus.disconnected,
              errorMessage: '데이터 조회 실패: $e');
          return (false, null, '데이터 조회 실패: $e');
        }

        // V2: AppFit WebSocket 연결 시작
        if (connectSocket) {
          final secureStorage = ref.read(secureStorageServiceProvider);
          final projectId =
              await secureStorage.read(SecureStorageService.appFitProjectId) ??
                  '';
          final apiKey = await secureStorage
                  .read(SecureStorageService.appFitProjectApiKey) ??
              '';
          final aesKey = AppEnv.aesKey;

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
          }
        } else {
          logger.i('[Auth] WebSocket connection skipped by user setting');
          logToFile(
              tag: LogTag.API,
              message: '[Auth] WebSocket connection skipped details');
        }

        state = state.copyWith(connectionStatus: ConnectionStatus.connected);

        return (true, null, null);
      } catch (e) {
        String errorMsg = e.toString().replaceAll('Exception: ', '');

        // 네트워크 관련 에러인 경우 추가 매핑
        if (errorMsg.contains('Connection') || errorMsg.contains('Network')) {
          errorMsg = '네트워크 연결 상태를 확인해주세요.';
        } else if (errorMsg.contains('sign-in')) {
          // 구체적인 메시지가 없는 경우의 폴백
          errorMsg = '아이디 또는 비밀번호가 일치하지 않습니다.';
        }

        logToFile(tag: LogTag.ERROR, message: '[Auth] V2 Login Failed: $e');
        state = state.copyWith(
            connectionStatus: ConnectionStatus.disconnected,
            errorMessage: errorMsg);
        return (false, null, errorMsg);
      }
    } catch (e, s) {
      logger.e('Native login error', error: e, stackTrace: s);
      final errorMsg = '로그인 중 오류가 발생했습니다: $e';
      state = state.copyWith(
          connectionStatus: ConnectionStatus.disconnected,
          errorMessage: errorMsg);
      return (false, null, errorMsg);
    }
  }

  void logout() {
    // 주의: 이 Provider의 의존성이 변경되는 시점에 다른 Provider를 읽으면 Riverpod assertion이 발생할 수 있음
    // 실제 정리는 UI 계층(HomeScreen)과 OrderProvider.cleanupOnLogout에서 수행하도록 위임
    // AuthState는 SocketState 변경 감지를 통해 자동으로 업데이트됨
    // state = AuthState(...); // 필요 시 초기 상태로 명시적 리셋
  }

  Future<void> reconnect() async {
    // AppFit은 내부적으로 재연결을 시도하므로 별도 호출 불필요
    // 필요한 경우 Credentials을 다시 로드하여 connect 호출 가능
    logger.i('[Auth] Reconnect requested (AppFit handles this internally)');
  }
}

// 기존 Provider 정의 삭제 (Generator가 자동으로 생성)
