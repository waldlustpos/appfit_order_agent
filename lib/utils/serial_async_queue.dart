import 'dart:async';

import 'package:flutter/foundation.dart';

/// 큐에 담긴 한 항목 + 추월 회계 정보.
class _QueueEntry<T> {
  _QueueEntry(this.item, {required this.isPriority, this.skipCount = 0});

  final T item;

  /// 우선 항목으로 삽입되었는지. 우선 항목끼리는 서로 추월하지 않는다.
  final bool isPriority;

  /// 나중에 도착한 우선 항목에게 추월당한 횟수.
  /// [SerialAsyncQueue.maxSkips] 에 도달하면 '잠겨' 더는 추월당하지 않는다.
  ///
  /// 처음부터 한도로 시작하면(= 추월 면역) FIFO 자리를 지키면서도 절대
  /// 밀리지 않는다. `add(protectedFromPriority: true)` 가 이 경로다.
  int skipCount;
}

/// 범용 순차 비동기 큐.
///
/// 비동기 작업을 한 번에 하나씩 직렬로 처리합니다. 이전 작업이 완료(또는 에러
/// 처리)되어야 다음 작업이 시작되므로 USB 프린터·TTS 등 공유 자원 경쟁 방지에
/// 적합합니다.
///
/// 본 클래스는 `appfit_core` 의 `SerialAsyncQueue` (v1.0.6 deprecated, 향후 제거
/// 예정) 에서 자체 구현으로 이전된 버전입니다. 동작은 동일하며, 의존성을 줄이고
/// 앱 라이프사이클 수준에서 직접 통제하기 위해 로컬화했습니다.
///
/// ## 우선순위 ([addPriority])
/// [add] 는 종전 그대로 FIFO 입니다. [addPriority] 로 넣은 항목만 대기 중인
/// 일반 항목을 추월합니다 (빠른 제조 메뉴 우선 출력용).
///
/// **굶주림 방지**: 일반 항목이 [maxSkips] 회 추월당하면 잠기고, 이후 어떤 우선
/// 항목도 그 앞으로 가지 못합니다. 시각이 아니라 **횟수** 기준이라 가상 시계
/// 없이도 결정론적으로 테스트됩니다.
///
/// ## 주의
/// - [clear] 호출 시 현재 진행 중인 [onProcess] 는 중단되지 않으며, 끝난 뒤
///   다음 처리가 호출되지 않을 뿐입니다.
/// - **이미 꺼내서 처리 중인 항목은 추월 대상이 아닙니다.** 선두 작업이 오래
///   걸리면(예: 라벨 떼기 대기) 우선순위와 무관하게 전체가 대기합니다.
/// - 단일 isolate 내 동시 호출은 안전하지만, 멀티 isolate 환경은 지원하지 않습니다.
class SerialAsyncQueue<T> {
  final List<_QueueEntry<T>> _queue = [];
  bool _isProcessing = false;

  /// 작업 처리 콜백.
  final Future<void> Function(T item) onProcess;

  /// 에러 처리 콜백 (optional). 호출 후 큐는 다음 항목으로 진행합니다.
  final void Function(T item, Object error, StackTrace stack)? onError;

  /// 일반 항목 하나가 최대 몇 번까지 추월당할 수 있는지. 기본 3.
  ///
  /// 버스트가 계속되는 동안 느린 주문이 무한정 밀리는 것을 막는 유일한 가드다.
  /// 낮추면 공정하지만 우선순위 효과가 줄고, 높이면 반대다.
  final int maxSkips;

  SerialAsyncQueue({
    required this.onProcess,
    this.onError,
    this.maxSkips = 3,
  }) : assert(maxSkips >= 0, 'maxSkips must not be negative');

  /// 큐 끝에 아이템 추가 후 처리 시작 (FIFO).
  ///
  /// [protectedFromPriority] 가 true 면 FIFO 자리는 그대로 유지하면서 이후
  /// [addPriority] 항목에게 **절대 추월당하지 않는다**. 운영자가 방금 요청해
  /// 프린터 앞에서 결과를 기다리는 작업(재출력 등)에 쓴다.
  void add(T item, {bool protectedFromPriority = false}) {
    _queue.add(_QueueEntry(
      item,
      isPriority: false,
      skipCount: protectedFromPriority ? maxSkips : 0,
    ));
    _processNext();
  }

  /// 여러 아이템을 큐에 추가 (FIFO).
  void addAll(Iterable<T> items) {
    _queue.addAll(items.map((e) => _QueueEntry(e, isPriority: false)));
    _processNext();
  }

  /// 대기 중인 일반 항목을 추월해 앞쪽에 삽입한다.
  ///
  /// 삽입 위치는 선두에서부터 "이미 우선인 항목" 과 "추월 한도([maxSkips])에
  /// 도달해 잠긴 일반 항목" 을 지나친 첫 지점이다. 그 결과:
  /// - 우선 항목끼리는 도착 순서(FIFO)를 유지한다.
  /// - 한 일반 항목이 [maxSkips] 회를 넘겨 밀리는 일이 없다.
  ///
  /// 큐가 비어 있으면 [add] 와 동일하게 동작한다.
  void addPriority(T item) {
    var index = 0;
    while (index < _queue.length &&
        (_queue[index].isPriority || _queue[index].skipCount >= maxSkips)) {
      index++;
    }
    _queue.insert(index, _QueueEntry(item, isPriority: true));
    // 이 삽입으로 뒤로 밀린 일반 항목들의 추월 횟수를 기록한다.
    for (var i = index + 1; i < _queue.length; i++) {
      final entry = _queue[i];
      if (!entry.isPriority) entry.skipCount++;
    }
    _processNext();
  }

  /// 큐 내 대기 아이템 수.
  int get length => _queue.length;

  /// 처리 중인지 여부.
  bool get isProcessing => _isProcessing;

  /// 큐가 비어있고 처리 중이 아닌지.
  bool get isIdle => _queue.isEmpty && !_isProcessing;

  /// 대기 중인 아이템 스냅샷 (처리 순서). 테스트에서 삽입 위치 검증용.
  @visibleForTesting
  List<T> get pendingItems => _queue.map((e) => e.item).toList(growable: false);

  /// 큐 전체 비우기.
  void clear() {
    _queue.clear();
    _isProcessing = false;
  }

  Future<void> _processNext() async {
    if (_isProcessing) return;
    if (_queue.isEmpty) return;

    _isProcessing = true;
    final item = _queue.removeAt(0).item;

    try {
      await onProcess(item);
    } catch (e, stack) {
      onError?.call(item, e, stack);
    } finally {
      _isProcessing = false;
      if (_queue.isNotEmpty) {
        // 스택 오버플로우 방지를 위해 microtask 로 다음 처리 예약
        Future.microtask(() => _processNext());
      }
    }
  }
}
