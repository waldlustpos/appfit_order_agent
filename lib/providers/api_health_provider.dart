import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:riverpod_annotation/riverpod_annotation.dart';
// 앱 lib 에서 sentry_flutter 첫 직접 사용. 코어 MonitoringService 에는 범용
// setTag 공개 API 가 없고, sentry_flutter 는 앱의 direct dependency 로 코어와
// 단일 버전 해석이라 `Sentry` 정적 Hub 가 같은 인스턴스다 — 코어 수정 없이
// 전역 scope 태그를 세팅할 수 있다. 미init(테스트) 환경에서는 NoOpHub 라
// configureScope 콜백 자체가 실행되지 않아 안전하다.
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:appfit_core/appfit_core.dart' as appfit_core;
import 'package:appfit_order_agent/core/net/api_health.dart';
import 'package:appfit_order_agent/core/net/network_outage_summary.dart';
import 'package:appfit_order_agent/core/net/transient_error.dart';
import 'package:appfit_order_agent/exceptions/network_degraded_exception.dart';
import 'package:appfit_order_agent/services/platform_service.dart';

part 'api_health_provider.g.dart';

/// HTTP 계층 건강도. [ApiService] 가 요청 결과마다 기록하고,
/// 복구 트리거(회복 시 즉시 재동기화)와 원격 관제가 구독한다.
/// 화면에 지연을 알리던 동기화 배너는 제거돼 UI 구독자는 없다.
///
/// 앱 전역 상태이므로 keepAlive. 화면 전환으로 리셋되면 안 된다.
@Riverpod(keepAlive: true)
class ApiHealthNotifier extends _$ApiHealthNotifier {
  @override
  ApiHealth build() => const ApiHealth();

  /// 열화 진입 시각. 회복 이벤트의 지속시간 계산 기준이고, healthy 구간에서는
  /// null 이다. [ApiHealth] 모델이 아니라 notifier 에 두는 이유: 모델은
  /// 구독자(복구 리스너)의 전이 판정용 값만 담아야 상태 비교가 흐려지지 않는다.
  DateTime? _degradedSince;

  /// 열화 구간에서 도달한 **최대** 연속 실패 횟수.
  ///
  /// 진입 이벤트에는 임계를 넘긴 순간의 값(2)만 담긴다. 2026-08-11 PAIK00002
  /// 장애의 실제 피크는 11회였는데 원격에서는 2회로 보였다 — 그 간극을 메운다.
  int _peakFailures = 0;

  /// 회복 이벤트 쿨다운. `MonitoringService.captureError` 의 5분 쿨다운을
  /// 못 타므로(회복은 `captureMessage` 로 나간다) 여기서 같은 간격을 건다.
  DateTime? _lastRecoveryReportAt;

  static const Duration _recoveryReportCooldown = Duration(minutes: 5);

  /// 마지막으로 계산된 회복 요약. 쿨다운으로 전송이 억제돼도 갱신된다.
  ///
  /// 테스트 환경은 Sentry 미init 이라 이벤트 자체를 검증할 수 없다. 계산 결과를
  /// 여기로 노출해야 지속시간·피크가 관찰 가능해진다.
  @visibleForTesting
  NetworkOutageSummary? lastOutageSummary;

  /// 실제로 Sentry 로 나간 회복 이벤트 수(쿨다운 통과분). 쿨다운 동작 검증용.
  @visibleForTesting
  int outageReportCount = 0;

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
    _publishTransition(
      wasDegraded: wasDegraded,
      before: before,
      at: now,
      recoveryReason: NetworkRecoveryReason.success,
    );
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
  ///
  /// [at] 은 테스트 주입용. 프로덕션에서는 넘기지 않는다.
  void recordFailure(Object error, {DateTime? at}) {
    if (error is DioException && error.type == DioExceptionType.cancel) {
      return;
    }
    final now = at ?? DateTime.now();

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
        _publishTransition(
          wasDegraded: wasDegraded,
          before: before,
          at: now,
          recoveryReason: NetworkRecoveryReason.serverReachable4xx,
        );
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
    // 피크는 전이가 아닌 구간에서도 자라므로 _publishTransition 밖에서 센다.
    // 열화 진입 후 3, 4, 5... 로 쌓이는 구간이 정확히 여기다.
    _peakFailures = math.max(_peakFailures, next);
    if (!wasDegraded && state.isDegraded) {
      logToFile(
        tag: LogTag.SYSTEM,
        message: 'API 건강도 저하 (연속 실패 $next회, kind=$kind)',
      );
    }
    _publishTransition(
      wasDegraded: wasDegraded,
      before: before,
      at: now,
      // transient 실패는 회복 전이를 만들 수 없다 — 이 인자는 여기서 안 읽힌다.
      recoveryReason: null,
    );
  }

  /// degraded ↔ healthy **전이 시에만** 원격 관제로 발행한다.
  ///
  /// - 태그 `api_health`: 이후 모든 Sentry 이벤트(라벨 오류 포함)에 붙어
  ///   "그 시점 HTTP 열화였나"를 즉시 판별하게 한다. 라벨/출력 오류가
  ///   네트워크 교란인지 분리하는 게 목적. 태그 부재 = "앱 시작 후 열화
  ///   전이 없음" 시맨틱이므로 초기값은 세팅하지 않는다.
  /// - degraded **진입** 시 이슈 1건([NetworkDegradedException]) —
  ///   코어가 transient 실패를 breadcrumb 으로만 남겨 매장 열화가 원격에서
  ///   구조적으로 안 보이는 공백(2026-08-07 PAIK00002 14분 장애 = Sentry
  ///   0건)을 메운다. 고정 fingerprint 로 단일 이슈 그룹 + 5분 쿨다운이라
  ///   알림 폭주 없음.
  /// - **회복** 시 이슈 1건([NetworkOutageSummary], `level=info`) — 진입
  ///   이벤트는 네트워크가 죽은 상태에서 만들어져 그 순간 전송될 수 없다.
  ///   SDK 가 디스크에 캐시했다가 앱이 재시작돼야 올라간다(2026-08-11
  ///   PAIK00002: 21:09 발생분이 다음 날 07:00 도착). 회복 시점은 네트워크가
  ///   살아 있어 **즉시 전송되는 유일한 채널**이고, 진입 이벤트가 담지 못하는
  ///   지속시간·피크 실패 횟수를 여기서 싣는다.
  ///
  /// [before] 는 전이 직전 상태 — 진입 이벤트의 extras 는 진입을 만든
  /// 시점의 값(state)을 쓰고, 회복 breadcrumb 은 직전 열화의 규모를 남긴다.
  /// [recoveryReason] 은 회복 분기에서만 읽힌다(진입 호출은 null).
  void _publishTransition({
    required bool wasDegraded,
    required ApiHealth before,
    required DateTime at,
    required NetworkRecoveryReason? recoveryReason,
  }) {
    if (wasDegraded == state.isDegraded) return;

    Sentry.configureScope(
      (scope) =>
          scope.setTag('api_health', state.isDegraded ? 'degraded' : 'healthy'),
    );

    if (state.isDegraded) {
      _degradedSince = at;
      _peakFailures = state.consecutiveFailures;
      // StackTrace.current 는 provider 내부 스택이라 판독 가치가 없다 —
      // 이슈 판독은 extras(kind/횟수/마지막 성공)와 store_id 태그로 한다.
      appfit_core.MonitoringService.instance.captureError(
        NetworkDegradedException(
          consecutiveFailures: state.consecutiveFailures,
          lastFailureKind: state.lastFailureKind,
          lastSuccessAt: state.lastSuccessAt,
        ),
        StackTrace.current,
        hint: '매장 HTTP 열화 감지',
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
      final degradedSince = _degradedSince;
      _degradedSince = null;

      // breadcrumb 은 쿨다운과 무관하게 **항상** 남긴다 — 이벤트가 억제돼도
      // 다음 이슈의 추적 trail 에는 회복이 보여야 한다(기존 동작 보존).
      appfit_core.MonitoringService.instance.addBreadcrumb(
        'API 건강도 회복',
        category: 'net',
        data: {
          'prior_failures': before.consecutiveFailures,
          'prior_kind': before.lastFailureKind ?? '-',
        },
      );

      // 진입 시각을 모르면 지속시간을 지어내지 않고 이벤트를 건너뛴다.
      // (진입 전이가 항상 _degradedSince 를 세우므로 실제로는 도달하지 않는다)
      if (degradedSince == null) return;

      final summary = NetworkOutageSummary(
        degradedSince: degradedSince,
        recoveredAt: at,
        peakFailures: math.max(_peakFailures, before.consecutiveFailures),
        lastFailureKind: before.lastFailureKind,
        reason: recoveryReason ?? NetworkRecoveryReason.success,
      );
      _peakFailures = 0;
      lastOutageSummary = summary;

      final last = _lastRecoveryReportAt;
      if (last != null && at.difference(last) < _recoveryReportCooldown) return;
      _lastRecoveryReportAt = at;
      outageReportCount++;

      // captureError 가 아니라 captureMessage 인 이유: 회복은 오류가 아니다.
      // level 은 슬랙 알림 태그로 노출되므로 회복을 error 로 올리면 이번 사건
      // (지연 도착을 실시간 장애로 오독)과 똑같은 오독을 새로 만든다.
      // 대신 MonitoringService 의 쿨다운을 못 타므로 위에서 직접 건다.
      Sentry.captureMessage(
        summary.toString(),
        level: SentryLevel.info,
        withScope: (scope) {
          scope.setContexts('extras', summary.toExtras());
          scope.fingerprint = ['network-recovered'];
        },
      );
    }
  }
}
