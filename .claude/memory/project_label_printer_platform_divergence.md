---
name: project_label_printer_platform_divergence
description: Android/Windows 라벨 동작 차이 5건 + 비프음 비대칭 원인. 통일은 Android 방향(Windows로 맞추면 비프음이 사라짐).
metadata: 
  node_type: memory
  type: project
  originSessionId: 3386bd7a-e00e-4391-9ed0-84a919ea04eb
  modified: 2026-08-07T00:12:14.419Z
---

2026-08-07 전수 대조. 정본은 [docs/PRINTER_FLOW.md §3.1](docs/PRINTER_FLOW.md) — 여기엔
**판단 근거와 함정만** 남긴다.

## 비프음 비대칭의 원인 (②)

**Android 는 라벨을 안 뗀 채 다음 출력 요청 시 비프음이 울리는데 Windows 는 안 울린다.**

- Android: `QueryPrintResult` 성공 시 **떼기를 안 기다리고 반환** → 다음 `PagePrint` 가 펌웨어에
  도달 → 펌웨어가 buzzer + 보류. `INFO_PAPERNOFETCH` 를 진입 게이트에서 **의도적 제외**한 결과.
- Windows: `_waitPaperFetched` 로 현재 인쇄 호출 안에서 떼기까지 블로킹 → 다음 `PagePrint` 가
  애초에 펌웨어에 안 닿음 → 울릴 계기 없음.

실기기 확인(D2s_KDS_STGL + REXOD): `#2 출력시작` → `#2 떼기대기 (PAPERNOFETCH, buzzer 활성)`.

## ⚠️ 통일 방향 — Android 쪽으로

②를 *Windows 기준*으로 맞추면(= Android 에 PAPERNOFETCH 선행 게이트 추가) **비프음이 조용히
사라진다.** 비프음은 버그가 아니라 점주 알림 기능이다. 두 플랫폼을 harmonize 하려는 리팩토링에서
가장 빠지기 쉬운 함정. 불변식: **"떼지 않은 상태에서 다음 `PagePrint` 가 펌웨어에 도달한다."**

③(ACK 획득 방식)은 **통일하지 않는다** — D2s_KDS_STGL 에서 printed 콜백이 fire 0건(2026-05-04
부하 테스트)이라 기기 제약에서 온 정당한 divergence. 계약(3분류)은 이미 같으므로 상위 계층 동일.

## 가설 신뢰도 관리

"Windows 에는 ACK timeout 증상이 없다" 를 ①(feedToTear 가 ACK 대기 창 안에 있음)의 근거로 쓰면
**②·③에 교란된다.** 특히 ③은 Windows 가 독립 신호(printed 콜백)를 갖고 있어 `QueryPrintResult`
응답 하나가 유실돼도 티가 안 났을 구조다. ①은 가장 싸게 시험해 볼 후보일 뿐 유력 후보가 아니다.

**Why:** 플랫폼 비교를 근거로 쓸 때 차이가 하나뿐이라고 가정하면 오판한다. 전수 대조가 먼저다.

**How to apply:** 라벨 흐름을 양 OS에서 손댈 때 이 메모 → PRINTER_FLOW.md §3.1 표 확인.
관련: [[project_label_ack_timeout_duplicate]], [[reference_rexod_label_printer_signals]]
