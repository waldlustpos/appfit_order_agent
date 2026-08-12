import 'package:appfit_order_agent/core/net/network_outage_summary.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-08-11 PAIK00002 장애의 실제 값 — 이 요약이 그때 있었다면 무엇이
/// 나갔어야 하는가를 고정한다.
NetworkOutageSummary _paik00002({
  NetworkRecoveryReason reason = NetworkRecoveryReason.success,
}) =>
    NetworkOutageSummary(
      degradedSince: DateTime(2026, 8, 11, 21, 9, 49),
      recoveredAt: DateTime(2026, 8, 11, 21, 19, 30),
      peakFailures: 11,
      lastFailureKind: 'connectionError',
      reason: reason,
    );

void main() {
  group('지속 시간', () {
    test('진입~회복 차이를 초로 준다', () {
      expect(_paik00002().outageSeconds, 581);
    });
  });

  group('제목 (Sentry 이슈 = 슬랙 알림 제목)', () {
    test('한 줄로 구간·지속·피크·원인이 다 읽힌다', () {
      expect(
        _paik00002().toString(),
        '인터넷 연결 회복 — 08-11 21:09~21:19 총 9분 41초 끊김 '
        '(최대 11회 연속 실패, connectionError)',
      );
    });

    test('4xx 회복은 데이터를 못 받았음을 제목에서 구분한다', () {
      expect(
        _paik00002(reason: NetworkRecoveryReason.serverReachable4xx).toString(),
        startsWith('인터넷 연결 회복(서버 응답 확인) —'),
      );
    });

    test('원인을 모르면 괄호째 생략한다', () {
      final s = NetworkOutageSummary(
        degradedSince: DateTime(2026, 8, 11, 21, 9),
        recoveredAt: DateTime(2026, 8, 11, 21, 10),
        peakFailures: 2,
        lastFailureKind: null,
        reason: NetworkRecoveryReason.success,
      );
      expect(s.toString(), endsWith('(최대 2회 연속 실패)'));
    });
  });

  group('extras', () {
    test('제목에서 뺀 정밀값이 대조 가능하게 남는다', () {
      expect(_paik00002().toExtras(), {
        'outage_seconds': 581,
        'degraded_since': '2026-08-11T21:09:49.000',
        'recovered_at': '2026-08-11T21:19:30.000',
        'peak_failures': 11,
        'last_failure_kind': 'connectionError',
        'recovery_reason': 'success',
      });
    });

    test('원인 미상은 - 로 채운다 (키 자체는 유지)', () {
      final s = NetworkOutageSummary(
        degradedSince: DateTime(2026, 8, 11, 21, 9),
        recoveredAt: DateTime(2026, 8, 11, 21, 10),
        peakFailures: 2,
        lastFailureKind: null,
        reason: NetworkRecoveryReason.success,
      );
      expect(s.toExtras()['last_failure_kind'], '-');
    });
  });
}
