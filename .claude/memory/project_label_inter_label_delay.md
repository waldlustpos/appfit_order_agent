---
name: project_label_inter_label_delay
description: "intra-order 라벨 사이 300ms 고정 딜레이 추가 — firmware '종이 안 뗌' 감지가 연속 라벨에서 안 걸리는 장비 편차 대응. Android 한정, 실기 검증 완료(300ms 정상동작)."
metadata: 
  node_type: memory
  type: project
  originSessionId: 637be48f-f7cd-4c33-a668-56aa539b4032
  modified: 2026-07-21T01:48:01.887Z
---

일부 Sunmi 라벨 프린터에서 firmware 설정 `Set unprintable when paper not taked out`(종이 안 뗐을 때 멈춤+비프)이 **주문↔주문 사이에는 걸리는데 동일 주문의 라벨↔라벨 사이에는 안 걸리고 연속 출력**되는 현상. 장비마다 편차(되는 프린터/안 되는 프린터).

**진단**: 감지는 Caysn SDK `INFO_PAPERNOFETCH` 비트를 STATUS 비콘 콜백으로 읽는 데 의존. 라벨을 촘촘히 연달아 보내면 비콘 갱신 전에 다음 PagePrint 가 도착 → firmware 가 연속 인쇄로 처리. 주문 사이엔 상위 `OrderQueueManager` 방출 throttle(_emitInterval 500ms, [[project_order_sort_tiebreak_burst]])+상세조회 왕복으로 우연히 idle 윈도우가 생겨 걸림. intra-order 루프([output_service.dart] printOrderLabels, line~186)엔 명시적 딜레이 0이라 윈도우 없음 → 장비 편차의 정체. Android 정상경로(`printed==true`)는 물리적 떼기를 명시적으로 안 기다리고 다음 라벨 idle 게이트로 암묵 흡수하는데 비콘 stale 이면 즉시 통과.

**수정 (2026-07-21, feat/show-empty-categories, 미커밋)**: `OutputService.printOrderLabels` 라벨 루프를 `labels.indexed` 로 바꾸고 `if (index > 0 && Platform.isAndroid) await Future.delayed(_kInterLabelDelay)` 삽입. `_kInterLabelDelay = 300ms` 상수. index 0(주문 첫 라벨) 제외 → 단일메뉴 주문 영향 0, 다잔 주문만 (N-1)×300ms. 단일 파일 변경, analyze 클린, output_queue 테스트 통과(딜레이는 Android 게이트라 호스트 테스트 미발동).

**실기 검증 (2026-07-21)**: 연결된 Sunmi 단말 재출력(3장) 테스트로 **300ms 정상동작 확인** — intra-order 라벨에서 firmware 비프+멈춤 걸림. ⚠️ 함정: 첫 시도 "안 걸리네" 는 Dart 변경이 **hot-reload 로 미반영**된 구(舊) 빌드였기 때문. 새 APK 재빌드 후 정상. (라벨/네이티브 영역은 cold-restart/재빌드로만 검증 — [[feedback_hot_reload_cold_restart]]) 로그상 정상경로는 3장 모두 `출력끝`(printed=true)이고 앱 `떼기대기(PAPERNOFETCH)` 경로는 미진입(비프+떼기대기가 있어도 QueryPrintResult 30s 안에서 펌웨어가 흡수·true 리턴하므로 앱 로그엔 긴 print=ms 로만 보임 — 로그만으론 비프 발생 판별 불가, 실물 관찰 필요).

**Why:** 사용자가 "타이밍 조정으로 해소 가능?" 물음 → 코드상 타당 확인. 딜레이 형태는 사용자가 "고정 상수" 선택(설정형/네이티브게이트 아님).

**How to apply:** "라벨 연속출력", "종이 안 뗌 감지 안 됨", "intra-order 라벨 딜레이", "300ms 라벨" 등 나오면 이 메모. **남은 것**: ① ✅ 실기 Sunmi 300ms 검증 완료(위 실기 검증 참조) ② 다른 프린터 개체가 300ms 로 부족하면 그때만 400~500ms 상향 튜닝 ③ Windows 는 미확인이라 현재 미적용(`Platform.isAndroid` 게이트), 확인되면 게이트 확대 ④ 딜레이로도 한계인 개체는 "네이티브 게이트 강화(PagePrint 후 idle 캐시 무효화로 fresh 비콘 강제 대기)"가 차선책.

## ⚠️ 2026-08-03 실측 정정

위 **진단** 문단의 "감지는 `INFO_PAPERNOFETCH` 비트에 의존" 은 맞지만, 이를 근거로 **"이 비트가 기기에 따라 안 뜬다"** 고 읽으면 안 된다. REXOD RXLA-561 실측에서 **비트는 매 인쇄마다 정상 전이한다** ([[reference_rexod_label_printer_signals]]).

정정 후 그림:
- 비트는 살아 있고, **펌웨어 보류도 실재**한다(앞 라벨 미제거 시 다음 페이지를 물고 있다가 떼면 인쇄, 19.2초까지 관측).
- 다만 **intra-order 연속 라벨에서는 보류가 안 걸리는 경우가 많다** — 프로덕션 로그상 0.45초 간격 2/2 라벨 다수가 ~1.05초에 완료(보류 없음). 이 memo 가 기록한 현상 자체는 유효하다.
- 즉 "장비 편차" 라기보다 **타이밍 의존**(비콘 갱신 전에 다음 PagePrint 가 도착)에 가깝고, 300ms 딜레이가 듣는 이유도 그것이다.

이 오해가 2026-08-03 라벨 2장 사고 분석에서 오판을 유발했다 → [[project_label_ack_timeout_duplicate]]

관련: [[project_label_ack_patch]](구 ACK 패치 — 현재 Android 는 PrintedEvent 미등록·StatusEvent 비콘+QueryPrintResult 30s 로 진화, 그 메모의 비트값 0x10/0x20 은 stale, 현재 0x20/0x40), 계획 파일 plans/replicated-stirring-treasure.md.
