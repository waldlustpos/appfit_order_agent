import 'package:appfit_order_agent/services/label_printer/label_print_outcome.dart';
import 'package:appfit_order_agent/services/platform_service.dart';

/// 라벨 한 장에 대한 재시도 정책.
///
/// OutputService 인스턴스 상태에 의존하지 않는 순수 흐름이라 별도 함수로 분리했다.
/// 이 분리의 실질적 이유는 **"[LabelPrintOutcome.submittedNoAck] 이면 dispatch 가
/// 정확히 1회"** 라는 불변식을 테스트로 고정하기 위함이다 — 이 불변식이 깨지면
/// 같은 라벨이 2장 인쇄된다 (2026-08-03 아오야마점 #0906/#0956).
///
/// 재시도 대상은 [LabelPrintOutcome.retryable] 뿐이다:
///   • USB 포트 단절 / 좀비 (다음 시도 시 재연결 자동 회복)
///   • 펌웨어 일시 ERROR (engine/voltage/cutter 등)
///   • PagePrint 도중 NoPaper race (다음 시도 시 진입 게이트가 무한 대기로 흡수)
///
/// Java 측이 자체 무한 대기로 흡수하는 케이스(PAPERNOFETCH, paper-out, cover-up)는
/// 애초에 여기로 오지 않는다.
///
/// [logPrefix] 는 `[Label] 0956 1/1` 형태의 운영자 식별자.
/// [onAckTimeout] 은 ACK 미수신 집계 훅 — 시도 회차(1 또는 2)를 받는다.
///
/// [onAckTimeout] 은 **await 한다.** 이 훅이 네이티브에서 진단 스냅샷을 가져오는데,
/// fire-and-forget 으로 두면 다음 라벨의 `printBitmap` 이 그 스냅샷을 덮어쓸 수 있다.
/// 직렬 큐 + 라벨 간 300ms 덕에 실제로 겹칠 확률은 낮지만, 관측 수단을 확률에 맡기지 않는다.
///
/// @return 종이가 나갔다고 볼 수 있으면 true. false 는 누락(운영자 재출력 필요).
Future<bool> runLabelPrintWithRetry({
  required Future<LabelPrintOutcome> Function() dispatch,
  required Future<void> Function(int attempt) onAckTimeout,
  required String logPrefix,
  Duration retryDelay = const Duration(milliseconds: 1500),
}) async {
  final first = await dispatch();
  if (first == LabelPrintOutcome.success) return true;
  if (first == LabelPrintOutcome.submittedNoAck) {
    // PagePrint 가 이미 펌웨어로 나갔다. 재발사하면 중복 인쇄다.
    await onAckTimeout(1);
    return true;
  }

  logToFile(
      tag: LogTag.WARNING,
      message: '$logPrefix 1차실패 (paper/cover 외 일시적)'
          ' → ${retryDelay.inMilliseconds / 1000}초 후 재시도');
  await Future<void>.delayed(retryDelay);

  final second = await dispatch();
  if (second == LabelPrintOutcome.submittedNoAck) {
    await onAckTimeout(2);
    return true;
  }
  if (second != LabelPrintOutcome.success) {
    logToFile(tag: LogTag.ERROR, message: '$logPrefix 재시도실패 — 누락');
    return false;
  }
  return true;
}
