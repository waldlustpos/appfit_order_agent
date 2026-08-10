import 'package:appfit_order_agent/services/startup_probe_scheduler.dart';

/// 라벨 warm-up 재확인 간격. 초기 1회 + 4회 = 총 5회 / 누적 약 91초.
///
/// 외부 COM(`PrintService.defaultStartupProbeBackoffs`, 누적 170초)보다 짧게
/// 잡았다 — 라벨 프린터는 전용 VID/PID 라 다른 프로그램과 포트를 다투지 않고,
/// 실패 원인이 "커널 enumerate 지연" 이나 "권한 승인 대기" 라면 분 단위로 늘어질
/// 성질이 아니다.
///
/// ★ 주기 폴링으로 승격하지 말 것 — **시작 창 한정 · 유한 횟수**. 인쇄 경로
/// 내부에 재시도를 더하는 것도 금지다 (상위 `runLabelPrintWithRetry` 가 이미
/// "retryable 일 때 정확히 1회" 재시도를 갖고 있고, 그 아래에 대기를 더하면
/// 인쇄 큐가 막힌다).
const List<Duration> kDefaultLabelWarmupBackoffs = [
  Duration(seconds: 3),
  Duration(seconds: 8),
  Duration(seconds: 20),
  Duration(seconds: 60),
];

/// 라벨 프린터 포트를 시작 시점에 1회 열고, 실패하면 백오프 재확인을 예약한다.
///
/// 재시도 대상은 **포트 open 뿐이며 인쇄를 하지 않는다.** 그래서 이 스케줄러가
/// 도는 동안 주문이 들어와도 출력과 간섭하지 않는다.
///
/// [autoReplyMode] 는 값이 아니라 **콜백**이다 — 매 시도마다 다시 읽어야 한다.
/// 재시도 대기 중 사용자가 설정 화면에서 모드를 바꿨는데 옛 값으로 포트를 열면,
/// 첫 인쇄가 모드 불일치로 포트를 닫고 다시 열어 warm-up 이 통째로 무효가 된다.
///
/// 반환값: 재시도가 예약됐으면 스케줄러(호출자가 dispose 시 `stop()`), 초기
/// 시도에서 성공했거나 라벨 프린터를 쓰지 않으면 null.
Future<StartupProbeScheduler?> startLabelWarmup({
  required bool useLabelPrinter,
  required int Function() autoReplyMode,
  required Future<bool> Function(int autoReplyMode) warmup,
  required bool Function() shouldContinue,
  List<Duration> backoffs = kDefaultLabelWarmupBackoffs,
  void Function(String message)? onInfo,
  void Function(String message)? onWarning,
}) async {
  if (!useLabelPrinter) return null;

  if (await warmup(autoReplyMode())) {
    onInfo?.call('라벨 warm-up 완료');
    return null;
  }

  return StartupProbeScheduler(
    backoffs: backoffs,
    probe: () => warmup(autoReplyMode()),
    shouldContinue: shouldContinue,
    onRetryScheduled: (attempt, total, delay) => onInfo?.call(
        '라벨 warm-up 실패 — 재시도 예약 ($attempt/$total, ${delay.inSeconds}초 후)'),
    onRecovered: (attempt, total) =>
        onInfo?.call('라벨 warm-up 성공 (재시도 $attempt/$total 에서 복구)'),
    onExhausted: (total) =>
        onWarning?.call('라벨 warm-up 최종 실패 ($total회) — 첫 인쇄 시 lazy 연결로 폴백'),
  )..startAfterInitialFailure();
}
