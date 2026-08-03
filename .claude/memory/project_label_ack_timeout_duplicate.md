---
name: project_label_ack_timeout_duplicate
description: "라벨 2장 인쇄 사고(2026-08-03 아오야마점) — ACK timeout을 인쇄 실패로 오판해 재전송. printBitmap 반환 3분류로 수정. 브랜치 미커밋."
metadata:
  type: project
---

2026-08-03 아오야마점(TPCP00001, REXOD RXLA-561) 주문 **#956 라벨 2장** 출력. 일일 로그 258건 중 2건(09:35 #0906, 13:08 #0956, **0.8%**).

## 원인

`CP_Pos_QueryPrintResult`의 30초 timeout을 "인쇄 실패"로 단정 → `_printLabelWithRetry`가 1.5초 뒤 **같은 페이지를 재전송** → 2장.

`PageBegin → DrawImage → PagePrint`는 QueryPrintResult **이전에** 이미 펌웨어로 나간다. 그래서 `printed=false`는 "종이가 안 나왔다"가 아니라 **"결과를 모른다"**일 뿐인데 실패로 단정했다.

**보류가 아니라 응답 유실이었다.** 근거: timeout 시점 `lastInfoPaperNoFetch == false`였고, 그 비트가 정상 동작함이 실측으로 확인됐다([[reference_rexod_label_printer_signals]]). 30초 내내 보류였다면 ~2초 주기 비콘이 열댓 번 오는 동안 true로 유지됐어야 한다. 재시도가 1070ms로 즉시 성공한 것도 부합. 유실 지점은 SDK/펌웨어 USB bulk-in 응답 경로 추정 — **앱에서 없앨 수 있는 성질이 아니다**.

**기존 `떼기대기` 가드는 고장이 아니었다.** 그 상황이 보류가 아니어서 안 걸린 것. 빠져 있던 건 "보류도 아닌데 응답이 없는" 케이스 하나뿐.

## 수정 (브랜치 `fix/label-duplicate-on-ack-timeout`, main 분기, **미커밋**)

`LabelPrinter.printBitmap` 반환을 `boolean` → `int` 3분류. `PagePrint` 성공 직후 `submitted=true` 플래그를 세워 발사 후 무응답·예외를 전부 재시도 금지로 분류.

| 반환 | 의미 | 재시도 |
|---|---|---|
| `RESULT_SUCCESS` | 인쇄 완료 확인 | — |
| `RESULT_RETRYABLE` | 발사 **전** 실패(연결오류·펌웨어 ERROR·NoPaperCanceled) | O |
| `RESULT_SUBMITTED_NO_ACK` | 발사 **후** 무응답 | **X** |

- `LabelPrintOutcome` enum으로 Dart 배선. Windows는 이미 submit-wins가 있어 매핑만(로직 무변경)
- 재시도 정책을 `lib/core/orders/label_print_retry.dart`로 분리 — 불변식 **"submittedNoAck ⇒ dispatch 정확히 1회"**를 `test/core/label_print_retry_test.dart` 9개로 고정
- `LabelAckTimeoutException` Sentry 집계(전용 타입 = 5분 쿨다운 키 분리). **누락으로 카운트하거나 `markPendingReprint`에 넣지 말 것 — 재발행이 곧 중복**
- 실패 로그에 판정 근거 첨부: `실패 [ACK timeout 30000ms — 재시도 금지] pg=… 비콘[…] 동기[…] portOk=…`

검증: analyze 변경파일 0건, test 267 통과, 실기기 cold-restart 2회차 정상. 문서 [docs/INCIDENT_2026-08-03_LABEL_DUPLICATE.md](docs/INCIDENT_2026-08-03_LABEL_DUPLICATE.md).

**Why:** 분석 중 가설을 두 번 뒤집었다. 최종 결론은 첫 방향(응답 유실)과 같지만, 중간 근거였던 "PAPERNOFETCH가 안 뜬다"와 "소요시간 분포에 8.5~30초 공백"은 **둘 다 틀렸다** — 전자는 실측으로 반증, 후자는 19.2초 보류가 재현되며 무너졌다. 258건 표본의 분포 공백을 메커니즘 근거로 쓴 것이 성급했다.

**How to apply:** "라벨 2장", "중복 인쇄", "ACK timeout", "submittedNoAck" 나오면 이 메모. **남은 것**: ① 커밋(작업트리에 mammoth 브랜드 작업이 섞여 있어 경로 지정 필요) ② Sentry로 0.8%의 기기·매장 분포 관측 ③ 보류 중 큐 30초 정지는 미해결(정상 동작이라 현행 유지 판단, `QUERY_PRINT_RESULT_TIMEOUT_MS` 30초 유지 권장 — 줄이면 미인쇄 페이지를 넘겨 펌웨어 버퍼에 쌓임)

관련: [[reference_rexod_label_printer_signals]], [[project_label_ack_patch]], [[project_label_inter_label_delay]], [[project_order_output_audit_2026_07]]
