---
name: project_bixolon_beep_next_step
description: BIXOLON 비프음 작업 착수 전 확인사항 — XD5-40d 표준기는 필러 미장착이라 비프음 메커니즘 자체가 성립 안 함. 하드웨어 확인이 선행.
metadata: 
  node_type: memory
  type: project
  originSessionId: 3386bd7a-e00e-4391-9ed0-84a919ea04eb
  modified: 2026-08-07T04:23:17.023Z
---

2026-08-07 세션 말미 발견. Caysn/REXOD 비프음 작업(Android `3e700f6` / Windows `4f222b3`)을
BIXOLON 으로 이어가려 할 때 **가장 먼저 확인할 것**.

## ⚠️ 착수 전 확인 — 문제가 존재하지 않을 수 있다

[BixolonLabelDriver.java:46-47](android/app/src/main/java/co/kr/waldlust/order/receive/util/print/BixolonLabelDriver.java#L46) 주석:

> XD5-40d 표준기는 필러(peeler) 미장착 — Caysn 의 PAPERNOFETCH(떼기대기+buzzer) 등가물이
> 없고 라벨이 연속 배출된다. PAUSED_IN_PEELER_UNIT 비트는 필러 장착기 방어용.

지금까지 고친 메커니즘은 **"앞 라벨이 peel 에 남음 → 다음 PagePrint 를 펌웨어가 붙잡고
buzzer"** 다. 필러가 없으면 라벨이 그냥 연속 배출되므로 붙잡을 일도, 울릴 일도 없다.

**따라서 순서는: ① 현장 BIXOLON 이 필러 장착기인지 확인 → ② 아니면 이 작업 자체가 불필요.**
`PAUSED_IN_PEELER_UNIT` 분기가 실제로 걸리는지 로그로 보는 것이 가장 빠른 판별.

## 필러 장착기로 확인됐을 때의 착수점

Caysn 쪽에서 얻은 교훈이 그대로 적용된다 — [[project_windows_label_beep_restore]] 참조.

| | Android | Windows |
|---|---|---|
| 파일 | `BixolonLabelDriver.java` | `bixolon_windows_label_backend.dart` |
| 완료 대기 | `waitPrintCompleteLocked` (:549), timeout 30초 | `_waitPrintComplete` (:509) |
| 떼기 분기 | `PAUSED_IN_PEELER` (:590) | `BxlStatus.takenWait` (:535) |

**핵심 점검 포인트** (Caysn 에서 실제로 사고를 만든 지점들):

1. **떼기 대기가 성공 경로에 있는가?** 있으면 다음 인쇄가 펌웨어에 안 닿아 비프음이 안 난다.
   Windows Caysn 이 정확히 이 문제였다.
2. **떼기 상태를 레벨로 보는가, edge 로 보는가?** 레벨이면, 떼기 대기를 걷어내는 순간
   **아직 나오지도 않은 라벨을 완료로 판정**한다. 두 변경은 분리 불가.
3. `BxlStatus.takenWait` 분기는 deadline 을 리셋하며 무한 대기한다(:546-548) — Caysn 의
   `_waitPaperFetched` 와 같은 성질.

**How to apply:** 어떤 대기를 없앨 때는 **그 대기가 암묵적으로 보장하던 사전조건**을 먼저
찾아라. Windows Caysn 에서는 "인쇄 시작 시 peel 이 비어 있음" 이었고, 그게 완료 판정의
정확성을 떠받치고 있었다.

관련: [[project_windows_label_beep_restore]], [[project_label_completion_multi_signal]],
[[project_label_printer_platform_divergence]], [[project_bixolon_xd5_40d]]
