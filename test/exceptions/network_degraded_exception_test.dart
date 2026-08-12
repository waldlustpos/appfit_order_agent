import 'package:appfit_order_agent/exceptions/network_degraded_exception.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sentry 이슈 타이틀이 되는 toString 고정.
///
/// 이 문자열이 바뀌면 Sentry 에서 기존 이슈와 다르게 보일 수 있다(그룹핑은
/// fingerprint 고정이라 유지되지만, 타이틀·검색은 영향을 받는다).
void main() {
  test('제목 한 줄에 횟수·마지막 정상 통신·원인이 다 들어간다', () {
    final e = NetworkDegradedException(
      consecutiveFailures: 2,
      lastFailureKind: 'connectionError',
      lastSuccessAt: DateTime(2026, 8, 11, 21, 7, 29),
    );

    expect(
      e.toString(),
      '인터넷 연결 끊김 — 서버 응답 없음 2회 연속, '
      '마지막 정상 통신 08-11 21:07 (connectionError)',
    );
  });

  // 이 이벤트는 네트워크가 죽은 상태에서 만들어져 앱 재시작 후에야 도착한다.
  // 제목에 날짜가 없으면 도착 시각을 발생 시각으로 오독한다 (2026-08-11
  // PAIK00002: 21:09 발생분이 다음 날 07:00 알림).
  test('제목의 시각에 날짜가 포함된다 — 지연 도착 오독 방지선', () {
    final e = NetworkDegradedException(
      consecutiveFailures: 2,
      lastFailureKind: 'connectionError',
      lastSuccessAt: DateTime(2026, 8, 11, 21, 7, 29),
    );

    expect(e.toString(), contains('08-11'));
  });

  test('한 번도 성공하지 못한 상태를 표현할 수 있다', () {
    final e = NetworkDegradedException(
      consecutiveFailures: 5,
      lastFailureKind: 'connectionTimeout',
    );

    expect(e.lastSuccessAt, isNull);
    expect(e.toString(), contains('마지막 정상 통신 기록 없음'));
  });

  test('원인을 모르면 괄호째 생략한다', () {
    final e = NetworkDegradedException(
      consecutiveFailures: 2,
      lastFailureKind: null,
      lastSuccessAt: DateTime(2026, 8, 11, 21, 7),
    );

    expect(e.toString(), endsWith('마지막 정상 통신 08-11 21:07'));
  });

  test('Exception 이지만 throw 용이 아니다 (captureError 인자 전용)', () {
    // 타입 계약만 고정한다 — 실제 throw 경로가 생기면 이 주석과 함께
    // 설계 의도를 다시 판단해야 한다.
    expect(
      NetworkDegradedException(consecutiveFailures: 2, lastFailureKind: null),
      isA<Exception>(),
    );
  });
}
