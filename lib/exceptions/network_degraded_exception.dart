/// 매장 HTTP 열화(degraded) 진입을 Sentry 로 알리기 위한 전용 예외.
///
/// **throw 되지 않는다** — `MonitoringService.captureError` 의 인자로만 쓰인다.
/// 전용 타입을 두는 이유: captureError 는 `exception.runtimeType` 으로 5분
/// 쿨다운 키를 만들므로, 범용 Exception 을 쓰면 무관한 오류와 쿨다운을
/// 공유하게 된다 ([OrderDetailFetchFailedException] 과 같은 규약).
///
/// **왜 원격 신호가 필요한가**: 코어 SentryAppFitLogger 는 transient 네트워크
/// 실패(connectionError·타임아웃류)를 breadcrumb 으로만 남기고 이슈를 만들지
/// 않는다. 그래서 2026-08-07 PAIK00002 의 14분 장애(수십 회 실패)가 Sentry 에
/// **0건**이었다 — 매장 네트워크 열화가 원격 관제에서 구조적으로 안 보였다.
/// degraded 전이 시 이 예외 1건(고정 fingerprint + 쿨다운)으로 그 공백을
/// 메운다. store_id 태그는 코어 전역 scope 가 부착하므로 기존 매장별 Slack
/// 알림 라우팅을 그대로 탄다.
class NetworkDegradedException implements Exception {
  NetworkDegradedException({
    required this.consecutiveFailures,
    required this.lastFailureKind,
    this.lastSuccessAt,
  });

  /// degraded 판정 시점의 연속 transient 실패 횟수.
  final int consecutiveFailures;

  /// 마지막 실패의 종류(`DioExceptionType.name`) — `[API진단]` 로그의 kind 와
  /// 동일한 값이라 파일 로그와 교차 대조할 수 있다.
  final String? lastFailureKind;

  /// 마지막으로 API 가 성공한 시각. 열화 지속 시간은 이 값과 Sentry 이벤트
  /// 타임스탬프의 차로 계산한다(클라이언트에서 계산해 싣지 않는다).
  final DateTime? lastSuccessAt;

  @override
  String toString() => 'NetworkDegradedException(fails=$consecutiveFailures, '
      'kind=$lastFailureKind, lastSuccess=$lastSuccessAt)';
}
