import 'dart:async';

/// 앱 시작 시 1회성 연결 확인이 실패했을 때, **유한 횟수**의 백오프 재확인을
/// 스케줄한다.
///
/// 매장 PC 는 부팅 직후 다른 POS / 배달 프로그램이 장치를 먼저 점유하거나
/// 드라이버가 아직 준비되지 않아 첫 확인이 실패하는 경우가 있다. 사용자가 설정
/// 화면에서 재연결을 누르지 않아도 점유가 풀리면 스스로 복구되도록 하는 것이
/// 목적이며, **주기 폴링이 아니다** — 시작 창에서만 유한 횟수 재확인한다.
///
/// 순수 Dart + 순수 [Timer] 로만 구성한다. 경과 판정을 `DateTime.now()` 로 하면
/// fakeAsync 가상시계를 따르지 않아 단위 테스트가 불가능해진다 (프로젝트 규약).
class StartupProbeScheduler {
  StartupProbeScheduler({
    required this.backoffs,
    required this.probe,
    this.shouldContinue,
    this.onRetryScheduled,
    this.onRecovered,
    this.onExhausted,
  }) : assert(backoffs.isNotEmpty, 'backoffs must not be empty');

  /// 재확인 간격. 길이가 곧 재시도 횟수다 (초기 1회 확인은 포함하지 않는다).
  final List<Duration> backoffs;

  /// 재확인 1회. 연결 확인되면 true.
  final Future<bool> Function() probe;

  /// false 를 반환하면 로그 없이 조용히 종료한다 (예: 사용자가 해당 프린터
  /// 토글을 꺼서 더 이상 확인할 이유가 없어진 경우).
  final bool Function()? shouldContinue;

  /// 재시도 예약 시 호출. (몇 번째 시도인지 1-based, 전체 시도 수, 대기 시간)
  final void Function(int attempt, int total, Duration delay)? onRetryScheduled;

  /// 재시도 끝에 연결이 확인됐을 때 1회 호출.
  final void Function(int attempt, int total)? onRecovered;

  /// 백오프를 모두 소진했을 때 1회 호출.
  final void Function(int total)? onExhausted;

  Timer? _timer;
  int _retry = 0;
  bool _done = false;

  /// 성공 복구 또는 전량 소진으로 끝났는지. true 면 다시 예약하지 않는다.
  bool get isDone => _done;

  /// 초기 1회 확인을 포함한 전체 시도 수.
  int get totalAttempts => backoffs.length + 1;

  /// 지금까지 소비한 재시도 회차 (초기 1회 확인 제외).
  int get retryCount => _retry;

  /// 초기 1회 확인이 **실패한 직후** 호출한다.
  void startAfterInitialFailure() => _schedule();

  /// 예약을 취소하고 종료 상태로 만든다. 재호출은 무해하다.
  void stop() {
    _done = true;
    _timer?.cancel();
    _timer = null;
  }

  void _schedule() {
    if (_done) return;
    if (_retry >= backoffs.length) {
      _done = true;
      onExhausted?.call(totalAttempts);
      return;
    }
    final delay = backoffs[_retry];
    _retry += 1;
    // 초기 확인이 1번째이므로 이번에 예약하는 재시도는 (_retry + 1) 번째.
    onRetryScheduled?.call(_retry + 1, totalAttempts, delay);
    _timer?.cancel();
    _timer = Timer(delay, _runRetry);
  }

  Future<void> _runRetry() async {
    if (_done) return;
    final cont = shouldContinue;
    if (cont != null && !cont()) {
      stop();
      return;
    }

    final ok = await probe();

    // probe 를 await 하는 사이 stop() 이 불렸을 수 있다.
    if (_done) return;
    if (ok) {
      _done = true;
      onRecovered?.call(_retry + 1, totalAttempts);
      return;
    }
    _schedule();
  }
}
