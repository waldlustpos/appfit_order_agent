---
name: feedback-queue-enqueue-timing
description: 큐 분리만으로는 병렬화 부족 — 같은 NewOrderJob 안에서 두 큐로 가는 sub-job 의 enqueue 시점을 await 전으로 옮겨야 진짜 병렬. UI 트리거는 큐 결과를 await 하지 말 것.
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 0c886ff3-b720-401a-be8a-01949f9ab18b
---

OutputQueueService 처럼 영수증/라벨 두 직렬 큐로 분리한 구조에서, 같은 `NewOrderJob` 안의 라벨 부분을 영수증 await **이후** 에 enqueue 하면 큐 분리에도 불구하고 사실상 직렬화된다. 영수증 PrinterJobQueue 의 backoff(최대 137s) 동안 라벨이 안 나옴. **라벨 sub-job 은 영수증 await 이전에 enqueue** 해야 진짜 병렬.

또한 UI 트리거(다이얼로그/버튼) 가 큐의 결과(`add()` 의 future) 를 `await` 하면 backoff 가 끝날 때까지 UI 가 묶인다. `PrinterJobQueue` 처럼 backoff + `onFinalFailure` 콜백을 자체 책임지는 큐는 호출자가 **fire-and-forget** 으로 enqueue 만 하고 즉시 리턴해야 함.

**Why:** 2026-05-19 매장 환경에서 외부 영수증 USB 분리 + 외부/라벨 둘 다 ON 상태에서 주문 수신 → 외부 backoff 137s 동안 라벨 출력 안 됨 사고 + 주문 취소 다이얼로그가 137s 동안 안 닫힘 사고. 큐는 [[project-store-printer-topology]] 의 두 본체 가정대로 독립이지만 enqueue 타이밍과 호출자 await 가 그 가정을 깼음.

**How to apply:**
- 새 큐 sub-job 추가 시 enqueue 시점이 다른 큐 sub-job 의 await 보다 **앞** 에 있는지 확인.
- 새 UI 트리거 추가 시 `await ref.read(outputQueueServiceProvider).add*()` 같은 패턴 금지. `unawaited` 또는 호출 후 즉시 리턴.
- 결과 표시가 필요하면 `Future.timeout(Duration(seconds: 8))` + 시간 초과 시 백그라운드 진행 안내 (설정 화면 "외부 프린터 테스트 출력" reference).
- 회귀 grep: `await ref.read(outputAppServiceProvider).printCancelReceiptById`, `await ref.read(printServiceProvider).printOrderReceipt` (큐 외부 호출만 — 큐 worker 내부의 await 는 의도된 직렬화).
- 관련: [[project-store-printer-topology]], [[feedback-ffi-isolate-boxing]]
