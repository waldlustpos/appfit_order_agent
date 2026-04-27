import 'dart:async';
import 'dart:collection';

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
/// ## 주의
/// - [clear] 호출 시 현재 진행 중인 [onProcess] 는 중단되지 않으며, 끝난 뒤
///   다음 처리가 호출되지 않을 뿐입니다.
/// - 단일 isolate 내 동시 호출은 안전하지만, 멀티 isolate 환경은 지원하지 않습니다.
class SerialAsyncQueue<T> {
  final Queue<T> _queue = Queue();
  bool _isProcessing = false;

  /// 작업 처리 콜백.
  final Future<void> Function(T item) onProcess;

  /// 에러 처리 콜백 (optional). 호출 후 큐는 다음 항목으로 진행합니다.
  final void Function(T item, Object error, StackTrace stack)? onError;

  SerialAsyncQueue({required this.onProcess, this.onError});

  /// 큐에 아이템 추가 후 처리 시작.
  void add(T item) {
    _queue.add(item);
    _processNext();
  }

  /// 여러 아이템을 큐에 추가.
  void addAll(Iterable<T> items) {
    _queue.addAll(items);
    _processNext();
  }

  /// 큐 내 대기 아이템 수.
  int get length => _queue.length;

  /// 처리 중인지 여부.
  bool get isProcessing => _isProcessing;

  /// 큐가 비어있고 처리 중이 아닌지.
  bool get isIdle => _queue.isEmpty && !_isProcessing;

  /// 큐 전체 비우기.
  void clear() {
    _queue.clear();
    _isProcessing = false;
  }

  Future<void> _processNext() async {
    if (_isProcessing) return;
    if (_queue.isEmpty) return;

    _isProcessing = true;
    final item = _queue.removeFirst();

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
