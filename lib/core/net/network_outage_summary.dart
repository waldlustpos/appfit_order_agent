import 'package:appfit_order_agent/core/net/net_report_format.dart';

/// HTTP 열화가 어떻게 끝났는가.
enum NetworkRecoveryReason {
  /// 요청이 정상 응답을 받았다 — 데이터까지 돌아왔다.
  success,

  /// 4xx 를 받았다 — 데이터는 못 받았지만 서버에 닿는 것은 확인됐다.
  /// (`ApiHealthNotifier.recordFailure` 의 non-transient 경로)
  serverReachable4xx,
}

/// 매장 HTTP 열화 **한 건**의 요약. degraded → healthy 전이에서 만들어져
/// 원격 관제(Sentry `level=info` 이벤트)로 나간다.
///
/// **왜 회복 쪽에 이벤트가 필요한가**: 열화 *진입* 이벤트
/// ([NetworkDegradedException])는 네트워크가 죽은 상태에서 만들어지므로 그 순간
/// Sentry 로 전송될 수 없다. SDK 가 디스크에 캐시했다가 앱이 재시작돼야 올라간다
/// — 2026-08-11 PAIK00002 장애는 21:09 발생분이 다음 날 07:00 에 도착했다
/// (9시간 41분 지연). 반면 **회복 시점은 네트워크가 살아 있어 즉시 전송된다.**
/// 실시간 도달이 보장되는 유일한 채널이다.
///
/// **왜 진입 이벤트만으로 부족한가**: 진입 이벤트에는 임계를 넘긴 순간의 값
/// (`fails=2`)만 담긴다. 위 장애의 실제 피크는 **11회**였는데 원격에서는 2회로
/// 보였다. 장애 규모와 지속 시간은 끝나봐야 알 수 있고, 그것을 싣는 게 이 객체다.
///
/// 모델은 수동 작성(freezed 미사용) — 프로젝트 규약.
class NetworkOutageSummary {
  const NetworkOutageSummary({
    required this.degradedSince,
    required this.recoveredAt,
    required this.peakFailures,
    required this.lastFailureKind,
    required this.reason,
  });

  /// degraded 로 판정된 시각(임계 도달 시점).
  final DateTime degradedSince;

  /// healthy 로 돌아온 시각.
  final DateTime recoveredAt;

  /// 장애 구간에서 도달한 **최대** 연속 실패 횟수. 진입 시점 값이 아니다.
  final int peakFailures;

  /// 마지막 실패의 종류(`DioExceptionType.name`) — `[API진단]` 파일 로그의
  /// `kind` 와 같은 값이라 교차 대조할 수 있다.
  final String? lastFailureKind;

  final NetworkRecoveryReason reason;

  Duration get outage => recoveredAt.difference(degradedSince);

  int get outageSeconds => outage.inSeconds;

  /// Sentry 이슈 제목이자 슬랙 알림 제목. 한 줄로 사건 전체가 읽혀야 한다.
  ///
  /// 예: `인터넷 연결 회복 — 08-11 21:09~21:19 총 9분 41초 끊김
  /// (최대 11회 연속 실패, connectionError)`
  @override
  String toString() {
    final head = reason == NetworkRecoveryReason.serverReachable4xx
        ? '인터넷 연결 회복(서버 응답 확인)'
        : '인터넷 연결 회복';
    final kind = lastFailureKind == null ? '' : ', $lastFailureKind';
    return '$head — ${formatRange(degradedSince, recoveredAt)} '
        '총 ${formatDuration(outage)} 끊김 (최대 $peakFailures회 연속 실패$kind)';
  }

  /// 제목에서 뺀 정밀값은 여기 남는다 — 제목은 사람이 읽고, 이쪽은 대조용이다.
  Map<String, dynamic> toExtras() => {
        'outage_seconds': outageSeconds,
        'degraded_since': degradedSince.toIso8601String(),
        'recovered_at': recoveredAt.toIso8601String(),
        'peak_failures': peakFailures,
        'last_failure_kind': lastFailureKind ?? '-',
        'recovery_reason': reason.name,
      };
}
