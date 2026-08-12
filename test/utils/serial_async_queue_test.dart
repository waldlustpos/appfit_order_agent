import 'dart:async';

import 'package:appfit_order_agent/utils/serial_async_queue.dart';
import 'package:flutter_test/flutter_test.dart';

/// 순수 동기 큐 테스트 — 타이머를 쓰지 않는다.
///
/// 처리를 시작하면 선두 항목이 즉시 큐에서 빠지므로, 삽입 위치만 검증하려면
/// **처리를 붙잡아 둔 상태**여야 한다. `onProcess` 를 완료되지 않는 Future 로
/// 두어 첫 항목에서 worker 를 멈춰 세우고, 나머지는 대기열에 그대로 남긴다.
class _HeldQueue {
  _HeldQueue({int maxSkips = 3}) {
    queue = SerialAsyncQueue<String>(
      maxSkips: maxSkips,
      onProcess: (item) {
        started.add(item);
        // 영원히 완료되지 않음 — 두 번째 항목 이후는 대기열에 남는다.
        return _never;
      },
    );
  }

  static final Future<void> _never = Completer<void>().future;

  late final SerialAsyncQueue<String> queue;
  final List<String> started = <String>[];

  /// 처리 중인 1건을 제외한 대기열 스냅샷.
  List<String> get pending => queue.pendingItems;
}

void main() {
  group('SerialAsyncQueue — FIFO 기본 동작 보존', () {
    test('add 는 도착 순서를 유지한다', () {
      final h = _HeldQueue();
      for (final item in ['A', 'B', 'C', 'D']) {
        h.queue.add(item);
      }
      expect(h.started, ['A']);
      expect(h.pending, ['B', 'C', 'D']);
    });

    test('addAll 도 도착 순서를 유지한다', () {
      final h = _HeldQueue();
      h.queue.addAll(['A', 'B', 'C']);
      expect(h.pending, ['B', 'C']);
    });

    test('clear 는 대기열을 비운다', () {
      final h = _HeldQueue();
      h.queue.addAll(['A', 'B', 'C']);
      h.queue.clear();
      expect(h.pending, isEmpty);
      expect(h.queue.length, 0);
    });
  });

  group('SerialAsyncQueue — addPriority 삽입 위치', () {
    test('대기 중인 일반 항목 앞에 들어간다', () {
      final h = _HeldQueue();
      h.queue.addAll(['HEAD', 'N1', 'N2']);
      h.queue.addPriority('P1');
      // HEAD 는 이미 처리 중이라 추월 대상이 아니다.
      expect(h.pending, ['P1', 'N1', 'N2']);
    });

    test('우선 항목끼리는 도착 순서(FIFO)를 지킨다', () {
      final h = _HeldQueue();
      h.queue.addAll(['HEAD', 'N1']);
      h.queue.addPriority('P1');
      h.queue.addPriority('P2');
      h.queue.addPriority('P3');
      expect(h.pending, ['P1', 'P2', 'P3', 'N1']);
    });

    test('큐가 비어 있으면 add 와 동일하게 뒤에 붙는다', () {
      final h = _HeldQueue();
      h.queue.add('HEAD');
      h.queue.addPriority('P1');
      expect(h.pending, ['P1']);
    });

    test('나중에 온 일반 항목은 기존 우선 항목을 앞지르지 않는다', () {
      final h = _HeldQueue();
      h.queue.add('HEAD');
      h.queue.addPriority('P1');
      h.queue.add('N1');
      expect(h.pending, ['P1', 'N1']);
    });
  });

  group('SerialAsyncQueue — 굶주림 가드', () {
    test('일반 항목은 maxSkips 회까지만 추월당한다', () {
      final h = _HeldQueue(maxSkips: 3);
      h.queue.addAll(['HEAD', 'SLOW']);
      for (var i = 1; i <= 5; i++) {
        h.queue.addPriority('P$i');
      }
      // P1~P3 가 SLOW 를 3회 추월 → SLOW 잠김. P4/P5 는 그 뒤로.
      expect(h.pending, ['P1', 'P2', 'P3', 'SLOW', 'P4', 'P5']);
    });

    test('잠긴 항목 뒤의 일반 항목은 여전히 추월당할 수 있다', () {
      final h = _HeldQueue(maxSkips: 1);
      h.queue.addAll(['HEAD', 'S1', 'S2']);
      h.queue.addPriority('P1'); // S1, S2 각 1회 추월 → 둘 다 잠김
      h.queue.addPriority('P2'); // 더는 못 지나감
      expect(h.pending, ['P1', 'S1', 'S2', 'P2']);
    });

    test('maxSkips=0 이면 추월이 아예 일어나지 않는다', () {
      final h = _HeldQueue(maxSkips: 0);
      h.queue.addAll(['HEAD', 'N1']);
      h.queue.addPriority('P1');
      expect(h.pending, ['N1', 'P1']);
    });
  });

  group('SerialAsyncQueue — 추월 면역 (protectedFromPriority)', () {
    test('FIFO 자리를 지키면서 우선 항목에게 밀리지 않는다', () {
      final h = _HeldQueue();
      h.queue.add('HEAD');
      h.queue.add('REPRINT', protectedFromPriority: true);
      h.queue.addPriority('P1');
      expect(h.pending, ['REPRINT', 'P1']);
    });

    test('면역 항목 뒤의 일반 항목도 함께 보호되지는 않는다', () {
      final h = _HeldQueue();
      h.queue.add('HEAD');
      h.queue.add('REPRINT', protectedFromPriority: true);
      h.queue.add('N1');
      h.queue.addPriority('P1');
      // REPRINT 는 못 지나가고, 그 바로 뒤(N1 앞)에 들어간다.
      expect(h.pending, ['REPRINT', 'P1', 'N1']);
    });
  });

  group('SerialAsyncQueue — 실제 처리 순서', () {
    test('삽입 순서가 아니라 큐 순서대로 처리된다', () async {
      final processed = <String>[];
      final queue = SerialAsyncQueue<String>(
        onProcess: (item) async {
          processed.add(item);
          // microtask 경계만 둔다 (타이머 없음).
          await Future<void>.microtask(() {});
        },
      );

      queue.add('HEAD');
      queue.add('N1');
      queue.add('N2');
      queue.addPriority('P1');
      await pumpEventQueue(times: 50);

      expect(processed, ['HEAD', 'P1', 'N1', 'N2']);
      expect(queue.isIdle, isTrue);
    });

    test('onProcess 예외는 onError 로 흡수되고 다음 항목이 계속된다', () async {
      final processed = <String>[];
      final errors = <String>[];
      final queue = SerialAsyncQueue<String>(
        onProcess: (item) async {
          processed.add(item);
          if (item == 'BOOM') throw StateError('boom');
        },
        onError: (item, e, _) => errors.add(item),
      );

      queue.addAll(['A', 'BOOM', 'B']);
      await pumpEventQueue(times: 50);

      expect(processed, ['A', 'BOOM', 'B']);
      expect(errors, ['BOOM']);
    });
  });
}
