---
name: project_label_ack_timeout_duplicate
description: 라벨 2장 사고(2026-08-03) 수정 + 후속 계측(Phase A). 수정은 커밋 852ac44(3.0.0+173)로 운영 반영·검증 완료. 계측은 미커밋.
metadata: 
  node_type: memory
  type: project
  originSessionId: 3386bd7a-e00e-4391-9ed0-84a919ea04eb
  modified: 2026-08-07T00:11:50.654Z
---

2026-08-03 아오야마점(TPCP00001, REXOD RXLA-561) 주문 **#956 라벨 2장** 출력.
`CP_Pos_QueryPrintResult` 30초 timeout 을 "인쇄 실패"로 단정 → 같은 페이지 재전송.
`PageBegin → DrawImage → PagePrint` 는 ACK 조회 **이전에** 이미 펌웨어로 나가므로,
`printed=false` 는 "종이가 안 나왔다"가 아니라 **"결과를 모른다"** 일 뿐이었다.

## 수정 (커밋 852ac44, `3.0.0+173` 부터 — main 반영 완료)

`printBitmap` 반환을 `boolean` → `int` 3분류. `PagePrint` 성공 직후 `submitted=true`.

| 반환 | 의미 | 재시도 |
|---|---|---|
| `RESULT_SUCCESS` | 인쇄 완료 확인 | — |
| `RESULT_RETRYABLE` | 발사 **전** 실패 | O |
| `RESULT_SUBMITTED_NO_ACK` | 발사 **후** 무응답 | **X** |

불변식 **"submittedNoAck ⇒ dispatch 정확히 1회"** 를 `test/core/label_print_retry_test.dart` 로 고정.
**`LabelAckTimeoutException` 을 누락으로 카운트하거나 `markPendingReprint` 에 넣지 말 것 — 재발행이 곧 중복.**

## 운영 검증 (Sentry, 2026-08-04~06)

16건 / 2개 매장(TPCP00001 8 · PAIK00002 8) **전부 `attempt=1`** = 재발사 0.
불변식이 실운영에서 실증됐고 중복 인쇄 재발 보고 없음. **정상 운영 중.**

## 계측 Phase A (2026-08-07, **미커밋**)

사고 문서가 남긴 "Sentry 집계로 기기 한정인지 확인" 숙제가 **현 구성으로는 답할 수 없음**을 확인:

- **대조군 부재** — 실 운영 매장 2곳이 전부이고 둘 다 D2s_KDS_STGL + REXOD. "16/16 이 기종,
  다른 기종 0건" 은 기기 특이성 근거가 **아니다**(다른 기종은 라벨을 안 찍는 선택 효과).
- **분모 부재 + 쿨다운** — `MonitoringService.captureError` 가 `runtimeType` 기준 5분 쿨다운을
  걸어 버스트가 breadcrumb 으로만 남는다. 이벤트 수는 **하한선**. 0.8% 는 기기 로그를 사람이
  하루치 센 값이었고 Sentry 로 재현 불가였다.

그래서 넣은 것:
1. `LabelPrinter.consumeLastAckDiagnostic()` + MethodChannel `getLastLabelAckDiagnostic`
   → `extras['diagnostic']`. **`printLabel` 의 int 반환 계약은 건드리지 않음** (Map 으로 바꾸면
   `invokeMethod<int>` 타입 캐스트 실패가 `on PlatformException` 에 안 잡혀 3분류를 흔든다).
2. `OutputService` static `_labelsAttempted` / `_ackTimeouts` → 비율을 이벤트 하나에서 산출,
   연속 이벤트의 `ackTimeouts` 차이로 쿨다운에 먹힌 건수 복원. 별도 억제 카운터 불필요.
3. `onAckTimeout` 을 `Future<void> Function(int)` 로 바꿔 **await** — 안 기다리면 다음 라벨의
   `printBitmap` 이 스냅샷을 덮어쓴다.

**비콘 `age` 가 핵심 판별자**: timeout 순간 비콘이 살아 있으면 print-result 응답 하나만 유실,
함께 끊겼으면 IN 엔드포인트 전체가 멎은 것 → 원인이 다르다.

### 강제 재현 기법 (재사용 가치 있음)

`QUERY_PRINT_RESULT_TIMEOUT_MS` 를 임시 300ms 로 낮춘 디버그 빌드면 **라벨 2~3장으로**
`submittedNoAck` 경로를 재현할 수 있다(자연 재현은 0.8% 라 수백 장 필요). 원복 필수.
실측(D2s_KDS_STGL `DK1925AJ40349` + REXOD, 2026-08-07): `출력시작` 1회 → ACK timeout →
**0.09초 뒤 `PAPERNOFETCH → 안뗌`** = 라벨은 실제로 나왔다. 전제 재확인 + 중복 없음 확인.
⚠️ 라벨을 **바로 떼야** ACK timeout 경로가 나온다. 안 떼면 떼기대기(보류) 경로로 빠진다.

**Why:** 관측 수단이 없는 집계는 "몇 번 났다"만 알려주고 "왜"는 답하지 못한다. 판정 근거를
Java 가 이미 만들고 있었는데 기기 로그로만 흘리고 있었다.

**How to apply:** "라벨 2장", "중복 인쇄", "ACK timeout", "submittedNoAck" → 이 메모.
**남은 것**: ① Phase A 커밋(작업트리에 타 세션 변경 섞여 있어 경로 지정 필요) ② 1~2주 기준선
확보 후 Phase B(feedToTear 순서 교정) ③ 30초 큐 정지는 현행 유지 결정.

관련: [[reference_rexod_label_printer_signals]], [[project_label_printer_platform_divergence]],
[[project_label_ack_patch]], [[project_label_inter_label_delay]], [[feedback_concurrent_session_git_state]]
