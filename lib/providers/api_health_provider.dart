import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
// 앱 lib 에서 sentry_flutter 첫 직접 사용. 코어 MonitoringService 에는 범용
// setTag 공개 API 가 없고, sentry_flutter 는 앱의 direct dependency 로 코어와
// 단일 버전 해석이라 `Sentry` 정적 Hub 가 같은 인스턴스다 — 코어 수정 없이
// 전역 scope 태그를 세팅할 수 있다. 미init(테스트) 환경에서는 NoOpHub 라
// configureScope 콜백 자체가 실행되지 않아 안전하다.
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:appfit_core/appfit_core.dart' as appfit_core;
import 'package:appfit_order_agent/core/net/api_health.dart';
import 'package:appfit_order_agent/core/net/transient_error.dart';
import 'package:appfit_order_agent/exceptions/network_degraded_exception.dart';
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
    final before = state;
    state = ApiHealth(consecutiveFailures: 0, lastSuccessAt: now);
    if (wasDegraded) {
      logToFile(
        tag: LogTag.SYSTEM,
        message: 'API 건강도 회복 (지연 → 정상)',
      );
    }
    _publishTransition(wasDegraded: wasDegraded, before: before);
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
        // degraded 중 4xx 수신 = 서버 도달 확인 = **정식 회복 전이**다.
        // 여기서 태그를 갱신하지 않으면 'degraded' 가 sticky 하게 남아
        // 코어 connection_status 태그와 같은 병(갱신 누락)을 재현한다.
        final wasDegraded = state.isDegraded;
        final before = state;
        state = ApiHealth(
          consecutiveFailures: 0,
          lastSuccessAt: state.lastSuccessAt,
        );
        if (wasDegraded) {
          // 이 전이도 order_provider 의 회복 리스너(refreshOrders)를
          // 발화시키므로 파일 로그가 없으면 진단 공백이 된다.
          logToFile(
            tag: LogTag.SYSTEM,
            message: 'API 건강도 회복 (4xx 응답 수신 — 서버 도달 확인)',
          );
        }
        _publishTransition(wasDegraded: wasDegraded, before: before);
      }
      return;
    }

    final kind =
        error is DioException ? error.type.name : error.runtimeType.toString();
    final next = state.consecutiveFailures + 1;
    final wasDegraded = state.isDegraded;
    final before = state;
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
    _publishTransition(wasDegraded: wasDegraded, before: before);
  }

  /// degraded ↔ healthy **전이 시에만** 원격 관제로 발행한다.
  ///
  /// - 태그 `api_health`: 이후 모든 Sentry 이벤트(라벨 오류 포함)에 붙어
  ///   "그 시점 HTTP 열화였나"를 즉시 판별하게 한다. 라벨/출력 오류가
  ///   네트워크 교란인지 분리하는 게 목적. 태그 부재 = "앱 시작 후 열화
  ///   전이 없음" 시맨틱이므로 초기값은 세팅하지 않는다.
  /// - degraded **진입** 시에만 이슈 1건([NetworkDegradedException]) —
  ///   코어가 transient 실패를 breadcrumb 으로만 남겨 매장 열화가 원격에서
  ///   구조적으로 안 보이는 공백(2026-08-07 PAIK00002 14분 장애 = Sentry
  ///   0건)을 메운다. 고정 fingerprint 로 단일 이슈 그룹 + 5분 쿨다운이라
  ///   알림 폭주 없음. 회복은 breadcrumb 만(이슈 미생성).
  ///
  /// [before] 는 전이 직전 상태 — 진입 이벤트의 extras 는 진입을 만든
  /// 시점의 값(state)을 쓰고, 회복 breadcrumb 은 직전 열화의 규모를 남긴다.
  void _publishTransition({
    required bool wasDegraded,
    required ApiHealth before,
  }) {
    if (wasDegraded == state.isDegraded) return;

    Sentry.configureScope(
      (scope) =>
          scope.setTag('api_health', state.isDegraded ? 'degraded' : 'healthy'),
    );

    if (state.isDegraded) {
      // StackTrace.current 는 provider 내부 스택이라 판독 가치가 없다 —
      // 이슈 판독은 extras(kind/횟수/마지막 성공)와 store_id 태그로 한다.
      appfit_core.MonitoringService.instance.captureError(
        NetworkDegradedException(
          consecutiveFailures: state.consecutiveFailures,
          lastFailureKind: state.lastFailureKind,
          lastSuccessAt: state.lastSuccessAt,
        ),
        StackTrace.current,
        hint: '매장 HTTP 열화 감지 — 동기화 배너 표시됨',
        extras: {
          'consecutive_failures': state.consecutiveFailures,
          'last_failure_kind': state.lastFailureKind ?? '-',
          'last_success_at': state.lastSuccessAt?.toIso8601String() ?? 'never',
        },
        // kind 가 connectionError ↔ receiveTimeout 으로 바뀌어도 단일 이슈로
        // 그룹 — Slack 알림은 이슈 단위라 이벤트가 늘어도 폭주하지 않는다.
        fingerprint: ['network-degraded'],
        cooldownKey: 'net:degraded',
      );
    } else {
      appfit_core.MonitoringService.instance.addBreadcrumb(
        'API 건강도 회복',
        category: 'net',
        data: {
          'prior_failures': before.consecutiveFailures,
          'prior_kind': before.lastFailureKind ?? '-',
        },
      );
    }
  }
}
