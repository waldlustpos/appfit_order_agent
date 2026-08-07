import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:appfit_order_agent/core/net/api_health.dart';
import 'package:appfit_order_agent/core/net/transient_error.dart';
import 'package:appfit_order_agent/services/platform_service.dart';

part 'api_health_provider.g.dart';

/// HTTP 계층 건강도. [ApiService] 가 요청 결과마다 기록하고,
/// UI(동기화 배너)와 복구 트리거가 구독한다.
///
/// 앱 전역 상태이므로 keepAlive. 화면 전환으로 리셋되면 안 된다.
@Riverpod(keepAlive: true)
class ApiHealthNotifier extends _$ApiHealthNotifier {
  @override
  ApiHealth build() => const ApiHealth();

  /// 요청이 성공했다. 연속 실패 카운터를 리셋하고 마지막 성공 시각을 갱신한다.
  ///
  /// [at] 은 테스트 주입용. 프로덕션에서는 넘기지 않는다.
  void recordSuccess({DateTime? at}) {
    final now = at ?? DateTime.now();
    final wasDegraded = state.isDegraded;
    state = ApiHealth(consecutiveFailures: 0, lastSuccessAt: now);
    if (wasDegraded) {
      logToFile(
        tag: LogTag.SYSTEM,
        message: 'API 건강도 회복 (지연 → 정상)',
      );
    }
  }

  /// 요청이 실패했다.
  ///
  /// 실패라고 다 같은 실패가 아니다:
  /// - **transient**(타임아웃·연결 실패·5xx) → 열화로 센다. 서버에 닿지 못했다.
  /// - **4xx / 파싱 오류** → 서버가 정상 응답한 것이므로 네트워크는 살아있다.
  ///   열화로 세지 않고 오히려 카운터를 **리셋**한다. (다만 데이터를 받지는
  ///   못했으므로 `lastSuccessAt` 은 갱신하지 않는다)
  /// - **취소**(`DioExceptionType.cancel`) → 네트워크 상태에 대해 아무것도
  ///   말해주지 않는다. 상태를 건드리지 않는다.
  void recordFailure(Object error) {
    if (error is DioException && error.type == DioExceptionType.cancel) {
      return;
    }

    if (!isTransientNetworkError(error)) {
      if (state.consecutiveFailures != 0) {
        state = ApiHealth(
          consecutiveFailures: 0,
          lastSuccessAt: state.lastSuccessAt,
        );
      }
      return;
    }

    final kind =
        error is DioException ? error.type.name : error.runtimeType.toString();
    final next = state.consecutiveFailures + 1;
    final wasDegraded = state.isDegraded;
    state = ApiHealth(
      consecutiveFailures: next,
      lastSuccessAt: state.lastSuccessAt,
      lastFailureKind: kind,
    );
    if (!wasDegraded && state.isDegraded) {
      logToFile(
        tag: LogTag.SYSTEM,
        message: 'API 건강도 저하 (연속 실패 $next회, kind=$kind)',
      );
    }
  }
}
