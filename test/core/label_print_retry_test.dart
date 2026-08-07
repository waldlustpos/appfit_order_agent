import 'package:appfit_order_agent/core/orders/label_print_retry.dart';
import 'package:appfit_order_agent/services/label_printer/label_print_outcome.dart';
import 'package:flutter_test/flutter_test.dart';

/// 라벨 재시도 정책 불변식 고정.
///
/// 핵심은 **submittedNoAck 에서 dispatch 가 정확히 1회** 라는 것. 이게 깨지면
/// 이미 펌웨어에 들어간 페이지가 한 번 더 발사돼 같은 라벨이 2장 인쇄된다
/// (2026-08-03 아오야마점 #0906/#0956 — QueryPrintResult 30초 timeout 을
/// 인쇄 실패로 오판한 사고).
void main() {
  /// 테스트에서 실제로 1.5초 기다리지 않도록 하는 값.
  const noDelay = Duration.zero;

  /// [outcomes] 를 순서대로 반환하며 호출 횟수를 세는 dispatch.
  ({Future<LabelPrintOutcome> Function() dispatch, List<int> calls})
      dispatcherOf(List<LabelPrintOutcome> outcomes) {
    final calls = <int>[0];
    return (
      dispatch: () async {
        final index = calls[0];
        calls[0] = index + 1;
        return outcomes[index];
      },
      calls: calls,
    );
  }

  Future<({bool ok, int dispatchCount, List<int> ackAttempts})> run(
      List<LabelPrintOutcome> outcomes) async {
    final d = dispatcherOf(outcomes);
    final ackAttempts = <int>[];
    final ok = await runLabelPrintWithRetry(
      dispatch: d.dispatch,
      onAckTimeout: (attempt) async => ackAttempts.add(attempt),
      logPrefix: '[Label] 0956 1/1',
      retryDelay: noDelay,
    );
    return (ok: ok, dispatchCount: d.calls[0], ackAttempts: ackAttempts);
  }

  group('submittedNoAck (ACK 미수신)', () {
    test('1차에서 발생하면 재시도하지 않고 성공 처리한다', () async {
      final r = await run([LabelPrintOutcome.submittedNoAck]);

      expect(r.dispatchCount, 1, reason: '재발사하면 라벨이 2장 인쇄된다');
      expect(r.ok, isTrue, reason: '종이는 나간 것으로 간주 — 누락 아님');
      expect(r.ackAttempts, [1], reason: '1차 시도로 집계');
    });

    test('재시도 중 발생해도 3번째 발사는 없다', () async {
      final r = await run([
        LabelPrintOutcome.retryable,
        LabelPrintOutcome.submittedNoAck,
      ]);

      expect(r.dispatchCount, 2);
      expect(r.ok, isTrue);
      expect(r.ackAttempts, [2], reason: '2차 시도로 집계');
    });

    test('집계 훅이 끝날 때까지 기다린 뒤 반환한다', () async {
      // 훅은 네이티브에서 진단 스냅샷을 가져온다. 기다리지 않으면 다음 라벨의
      // printBitmap 이 그 스냅샷을 덮어써 엉뚱한 값이 Sentry 로 올라간다.
      var hookFinished = false;
      final ok = await runLabelPrintWithRetry(
        dispatch: () async => LabelPrintOutcome.submittedNoAck,
        onAckTimeout: (_) async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          hookFinished = true;
        },
        logPrefix: '[Label] 0956 1/1',
        retryDelay: noDelay,
      );

      expect(hookFinished, isTrue, reason: '반환 시점에 훅이 이미 완료돼 있어야 한다');
      expect(ok, isTrue);
    });
  });

  group('retryable (전송 전 실패)', () {
    test('1차 실패 후 재시도해서 성공하면 총 2회 발사', () async {
      final r = await run([
        LabelPrintOutcome.retryable,
        LabelPrintOutcome.success,
      ]);

      expect(r.dispatchCount, 2);
      expect(r.ok, isTrue);
      expect(r.ackAttempts, isEmpty);
    });

    test('두 번 다 실패하면 누락(false)이고 발사는 2회에서 멈춘다', () async {
      final r = await run([
        LabelPrintOutcome.retryable,
        LabelPrintOutcome.retryable,
      ]);

      expect(r.dispatchCount, 2);
      expect(r.ok, isFalse, reason: '운영자 재출력이 필요한 진짜 누락');
      expect(r.ackAttempts, isEmpty);
    });
  });

  test('success 면 한 번만 발사한다', () async {
    final r = await run([LabelPrintOutcome.success]);

    expect(r.dispatchCount, 1);
    expect(r.ok, isTrue);
    expect(r.ackAttempts, isEmpty);
  });

  group('LabelPrintOutcome 계약', () {
    test('네이티브 코드 매핑', () {
      expect(LabelPrintOutcome.fromNativeCode(0), LabelPrintOutcome.success);
      expect(LabelPrintOutcome.fromNativeCode(1), LabelPrintOutcome.retryable);
      expect(LabelPrintOutcome.fromNativeCode(2),
          LabelPrintOutcome.submittedNoAck);
    });

    test('알 수 없는 값·null 은 보수적으로 retryable', () {
      expect(
          LabelPrintOutcome.fromNativeCode(null), LabelPrintOutcome.retryable);
      expect(LabelPrintOutcome.fromNativeCode(99), LabelPrintOutcome.retryable);
    });

    test('canRetry 는 retryable 에서만 true', () {
      expect(LabelPrintOutcome.retryable.canRetry, isTrue);
      expect(LabelPrintOutcome.success.canRetry, isFalse);
      expect(LabelPrintOutcome.submittedNoAck.canRetry, isFalse,
          reason: 'ACK 미수신은 절대 재발사 금지');
    });

    test('isPrinted 는 retryable 에서만 false', () {
      expect(LabelPrintOutcome.success.isPrinted, isTrue);
      expect(LabelPrintOutcome.submittedNoAck.isPrinted, isTrue);
      expect(LabelPrintOutcome.retryable.isPrinted, isFalse);
    });
  });
}
