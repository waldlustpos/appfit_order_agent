import 'package:appfit_order_agent/exceptions/network_degraded_exception.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sentry 이슈 타이틀이 되는 toString 고정.
///
/// 이 문자열이 바뀌면 Sentry 에서 기존 이슈와 다르게 보일 수 있다(그룹핑은
/// fingerprint 고정이라 유지되지만, 타이틀·검색은 영향을 받는다).
void main() {
  test('toString 에 진단 3요소가 모두 들어간다', () {
    final e = NetworkDegradedException(
      consecutiveFailures: 2,
      lastFailureKind: 'connectionError',
      lastSuccessAt: DateTime.utc(2026, 8, 7, 15, 6),
    );

    expect(e.toString(), contains('fails=2'));
    expect(e.toString(), contains('kind=connectionError'));
    expect(e.toString(), contains('2026-08-07'));
  });

  test('한 번도 성공하지 못한 상태를 표현할 수 있다', () {
    final e = NetworkDegradedException(
      consecutiveFailures: 5,
      lastFailureKind: 'connectionTimeout',
    );

    expect(e.lastSuccessAt, isNull);
    expect(e.toString(), contains('lastSuccess=null'));
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
