/// HTTP 계층이 지금 살아있는가에 대한 판정 상태.
///
/// **왜 필요한가**: 2026-08-07 매장 장애에서 HTTP 요청이 14분간 전멸했는데
/// 앱의 어떤 신호도 그것을 알아채지 못했다.
/// - `connectivity_plus` 는 링크 계층(wifi/ethernet 인터페이스)만 본다. 공유기는
///   살아있고 WAN 만 죽은 상황에서는 이벤트조차 발생하지 않는다.
/// - 코어 WebSocket heartbeat 는 로컬 `readyState == open` 하나만 본다. 실제로
///   소켓 끊김을 감지하기까지 **14분 7초**가 걸렸고, 그동안 폴링은 "연결됨"
///   기준인 60초 간격을 그대로 유지했다.
///
/// 결국 **HTTP 요청 자체의 성패가 유일하게 남은 진실 신호**여서, 그것을 직접
/// 센다. 이 상태는 (1) 사용자에게 지연을 알리는 배너와 (2) 회복 시점 감지 후
/// 즉시 재동기화하는 트리거로 쓰인다.
///
/// 모델은 수동 작성(freezed 미사용) — 프로젝트 규약.
class ApiHealth {
  /// transient 실패(타임아웃·연결 실패·5xx)의 연속 횟수. 성공 시 0으로 리셋.
  final int consecutiveFailures;

  /// 마지막으로 API 가 성공한 시각. 앱 시작 후 한 번도 성공하지 못했으면 null.
  final DateTime? lastSuccessAt;

  /// 마지막 실패의 종류(`DioExceptionType.name`). 배너 문구 분기와 진단용.
  final String? lastFailureKind;

  const ApiHealth({
    this.consecutiveFailures = 0,
    this.lastSuccessAt,
    this.lastFailureKind,
  });

  /// 열화 판정 임계.
  ///
  /// 폴링만 놓고 보면 2회 = 최대 2분이라 느려 보이지만, 실제로는 사용자 액션
  /// (픽업 요청·완료 처리)의 실패가 훨씬 빨리 카운트를 채운다 — 장애 로그에서는
  /// 20초 안에 5회가 쌓였다. 1회로 낮추면 단발 blip 에도 배너가 깜빡여
  /// 오히려 신뢰를 잃는다.
  static const int degradedThreshold = 2;

  bool get isDegraded => consecutiveFailures >= degradedThreshold;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ApiHealth &&
          other.consecutiveFailures == consecutiveFailures &&
          other.lastSuccessAt == lastSuccessAt &&
          other.lastFailureKind == lastFailureKind;

  @override
  int get hashCode =>
      Object.hash(consecutiveFailures, lastSuccessAt, lastFailureKind);

  @override
  String toString() => 'ApiHealth(fails: $consecutiveFailures, '
      'lastSuccess: $lastSuccessAt, kind: $lastFailureKind)';
}
