import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:appfit_order_agent/services/platform_service.dart';
import 'package:appfit_order_agent/services/printer_transport.dart';

typedef PrinterFinalFailureCallback = void Function(
    PrinterJob job, PrinterTransportResult lastResult);

/// 외부 영수증/주문서/알림 출력 한 건. 큐에 넣을 때 즉시 [future] 를 받아
/// 호출자가 최종 성공/실패를 await 할 수 있다.
class PrinterJob {
  PrinterJob({
    required this.bytes,
    required this.jobName,
    required this.kind,
  }) : id = _nextId++;

  /// 디버깅용 식별자. 큐 로그에서 동일 잡 추적에 사용.
  final int id;

  /// 송출할 ESC/POS 바이트. backoff 재시도 시 동일 바이트 재사용.
  final Uint8List bytes;

  /// 'RECEIPT_123' 등 운영 로깅용 라벨.
  final String jobName;

  /// 'order' | 'receipt' | 'alert' 등. transport 동작에는 영향 없고 로깅 분류용.
  final String kind;

  /// 현재 시도 회차 (1-based). 첫 호출 전 0.
  int attempt = 0;

  /// 마지막 transport 결과. final-failure 콜백에서 사유 분류에 사용.
  PrinterTransportResult? lastResult;

  final Completer<bool> _completer = Completer<bool>();
  Future<bool> get future => _completer.future;

  static int _nextId = 1;
}

/// 외부 프린터 출력 글로벌 직렬 큐. 점유 충돌(BUSY) / 일시 단선(NO_DEVICE) /
/// transport 오류를 지수 backoff 로 흡수한다.
///
/// - 인메모리 단일 큐. 앱 재시작 시 미완료 잡은 분실.
/// - 단일 worker -> 잡 사이 직렬화 보장. (호출 측이 동시에 enqueue 해도 안전)
/// - 최종 실패 시 [onFinalFailure] 가 1회 호출되고, 다음 잡 처리는 계속.
class PrinterJobQueue {
  PrinterJobQueue._();
  static final PrinterJobQueue instance = PrinterJobQueue._();

  /// 각 시도 시작 전 대기 시간. 인덱스 0 은 첫 시도(즉시 실행)라 실제 사용되지
  /// 않지만, 구조 일관성을 위해 자리만 차지한다. 인덱스 N(>0) 가 N->N+1 번째
  /// 시도 사이 대기.
  ///
  /// 정책: 0/2/5/10/20/40/60s -- 누적 ~137s, 총 7회 시도.
  /// 매장 시나리오별 풀리는 타이밍을 반영:
  ///   - 짧은 트랜잭션 점유(POS 1건 처리 ~2s) -> 2차에서 풀림
  ///   - 일반 점유 / 사용자 전원 켜는 중(~7s) -> 3차
  ///   - USB 재연결(~17s) -> 4차
  ///   - 부팅 느린 프린터(~37s) -> 5차
  ///   - 잠깐 자리 비운 사이 장애(~77s) -> 6차
  ///   - cap 60s -- 큐 적체 막기 위한 한계. 137s 까지 시도해도 실패면 final.
  /// 단일 worker 라 한 잡이 backoff 중이면 후속 영수증이 적체되므로 cap 둠.
  /// 테스트에서 [backoffsForTest] 로 길이/간격 자유 단축.
  static const List<Duration> defaultBackoffs = [
    Duration.zero,
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 20),
    Duration(seconds: 40),
    Duration(seconds: 60),
  ];

  List<Duration> _backoffs = defaultBackoffs;

  /// 한 잡당 최대 시도 횟수 (초기 1회 포함). [_backoffs] 길이에서 derive.
  int get maxAttempts => _backoffs.length;

  /// 테스트 전용. 프로덕션에서는 호출하지 않는다. 길이는 자유.
  @visibleForTesting
  set backoffsForTest(List<Duration> b) {
    assert(b.isNotEmpty, 'backoffs must not be empty');
    _backoffs = b;
  }

  PrinterTransport? _transport;

  /// 호출부(print_service) 에서 플랫폼에 맞는 transport 를 주입.
  /// 미주입 상태에서 enqueue 가 호출되면 잡은 즉시 noDevice 로 종료된다.
  void setTransport(PrinterTransport t) {
    _transport = t;
  }

  /// [maxAttempts] 회 시도 후에도 success 못 받은 잡에 대해 호출. print_service 가 등록.
  PrinterFinalFailureCallback? onFinalFailure;

  final List<PrinterJob> _queue = [];
  bool _running = false;

  /// 잡을 큐 끝에 추가하고 worker 가 idle 이면 깨운다.
  /// 반환 [Future]는 success 시 true, [maxAttempts] 회 실패/transport 없음 시 false.
  Future<bool> enqueue(PrinterJob job) {
    _queue.add(job);
    logToFile(
      tag: LogTag.PLATFORM,
      message:
          '[PrinterQueue] enqueue id=${job.id} kind=${job.kind} job=${job.jobName} qsize=${_queue.length}',
    );
    _kick();
    return job.future;
  }

  void _kick() {
    if (_running) return;
    _running = true;
    scheduleMicrotask(_runLoop);
  }

  Future<void> _runLoop() async {
    try {
      while (_queue.isNotEmpty) {
        final job = _queue.removeAt(0);
        await _processJob(job);
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _processJob(PrinterJob job) async {
    final transport = _transport;
    if (transport == null) {
      const r = PrinterNoDevice('transport not initialized');
      job.lastResult = r;
      logToFile(
        tag: LogTag.ERROR,
        message:
            '[PrinterQueue] transport 미주입 - 잡 즉시 종료 id=${job.id} job=${job.jobName}',
      );
      onFinalFailure?.call(job, r);
      if (!job._completer.isCompleted) job._completer.complete(false);
      return;
    }

    for (int i = 0; i < maxAttempts; i++) {
      job.attempt = i + 1;
      if (i > 0) {
        await Future.delayed(_backoffs[i]);
      }
      PrinterTransportResult result;
      try {
        result = await transport.send(job.bytes, job.jobName);
      } catch (e) {
        result = PrinterTransportError('transport.send threw: $e');
      }
      job.lastResult = result;
      if (result is PrinterSuccess) {
        logToFile(
          tag: LogTag.PLATFORM,
          message:
              '[PrinterQueue] success id=${job.id} job=${job.jobName} attempt=${job.attempt}',
        );
        if (!job._completer.isCompleted) job._completer.complete(true);
        return;
      }
      logToFile(
        tag: LogTag.WARNING,
        message:
            '[PrinterQueue] attempt=${job.attempt}/$maxAttempts 실패 id=${job.id} job=${job.jobName} result=$result',
      );
    }

    logToFile(
      tag: LogTag.ERROR,
      message:
          '[PrinterQueue] final-failure id=${job.id} job=${job.jobName} result=${job.lastResult}',
    );
    onFinalFailure?.call(job, job.lastResult!);
    if (!job._completer.isCompleted) job._completer.complete(false);
  }

  @visibleForTesting
  int get queueSize => _queue.length;

  @visibleForTesting
  bool get isRunning => _running;

  /// 테스트 격리용. 프로덕션 코드에서는 호출하지 않는다.
  @visibleForTesting
  void resetForTest() {
    _queue.clear();
    _transport = null;
    onFinalFailure = null;
    _running = false;
  }
}
