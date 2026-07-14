---
name: project_order_sort_tiebreak_burst
description: 버스트 주문 순서 정본 = compareForDisplay(orderedAt 우선 + 동일시각 displayNo tiebreak). displayNo 는 채널마다 대역이 달라 단독 정렬 불가. 2026-07-13 3차 완료.
metadata: 
  node_type: memory
  type: project
  originSessionId: 6fba2735-4ee5-4cd1-931f-ef0298454aa9
---

**최종 정본 (2026-07-13, 3차):** 표시·출력 모두 `lib/utils/order_comparators.dart` 의 **`compareForDisplay` = orderedAt primary + 동일시각 시 displayNo tiebreak**. 카드 순서 = 주문서 순서.

**왜 orderedAt primary (displayNo 아님):** displayNo(displayOrderNo, 화면/영수증/라벨이 표시하는 번호)는 **주문 채널마다 대역이 다르다** — 모바일 1번대, 키오스크 700번대, 키오스크 1000번대. 대역을 가로질러 번호로 정렬하면 동시 주문 시 `#3,#4,…,#701,#1001`처럼 대역별로 뭉쳐 시간 역전. 채널을 가로지르는 유일하게 유효한 순서는 **orderedAt(시간)**. displayNo 는 완전 동일 시각(순간 버스트)의 tiebreak 로만(같은 대역이면 번호순 복원). **가정: 서버가 채널 내 orderedAt 을 생성순서와 일치하게 내려줌**(0.5초 간격 테스트 정상이 방증). 실측 로그: 서버가 shopNo(ordrSimpleId)와 displayNo 를 상충 발번(shopNo=8→#700, shopNo=1→#701).

**2·3차 통합 결과:** (1) `compareByDisplayNo`(int.tryParse 3-way 전순서 — 비추이성·throw 없음)는 **tiebreak 전용**, 단독 정렬 금지. `compareForDisplay` 가 표시·출력 정본. (2) NEW 버퍼 디바운스 400ms+cap 1.2s, 상태버퍼 디바운스 200ms+cap 1s — 순수 Timer 2개([[reference_fakeasync_pure_timer]]), flush 에서 정렬(SSOT=큐매니저). (3) emit `_isEmitting` 재진입 가드. (4) `OrderStatus.statusCode` extension 통합. (5) 재현 도구 `generateBurstOrders`(단일대역 동일시각=번호 tiebreak) + `generateMultiChannelBurst`(3대역 인터리브, 시간≠번호대역순 → 시간순 방출 검증). 주입 지터는 버퍼 창보다 작게. C4 갱신은 후순위(사용자 지시).

**증상(2026-07-10 T2mini_s 실기기 버스트 테스트에서 사용자 확인):** 주문 대량 유입 시 화면의 주문번호가 순차적으로 표시되지 않음.

**원인 (order-flow-inspector 조사 확정):**
- UI 정렬은 **번호가 아니라 시각 `orderedAt` 단일 키**. `order_computed_providers.dart` NEW/PREPARING/READY = `..sort((a,b)=>a.orderedAt.compareTo(b.orderedAt))` ASC(DONE만 DESC), KDS는 `kds_utils.dart` `sortOrders`, `state.orders` 유지도 `order_provider.dart:1012/1632/1662` 모두 orderedAt. **tie-break 2차 키 전무.**
- `order_model.dart:246` 직렬화가 `'yyyy-MM-dd HH:mm:ss'` **초 단위** → 버스트에서 동일초 동률 흔함.
- Dart `List.sort`는 non-stable(32+ quicksort). 입력순서가 경로별 상이(폴링=서버 `CreatedAtDesc` 후 ASC 재정렬, 소켓=prepend 후 재정렬) → 동일초 주문 상대순서 **비결정적**, 소켓푸시↔다음폴링 사이 카드 재배치(ValueKey라 가시적 점프).
- **핵심 비대칭:** 화면=`orderedAt`(시간) 정렬인데 **출력/인쇄 enqueue 는 `shopOrderNo`(번호)** 정렬(`order_queue_manager.dart:49`, `order_provider.dart:767`). 인쇄물=번호순, 화면=시간순이라 갈라져 보임. (shopOrderNo 인쇄정렬은 의도된 불변식 — orderedAt 으로 바꾸면 회귀.)
- `order_history_provider.dart:20-23` enum 주석 "주문번호 낮은순" vs 구현 `orderedAt` **불일치**(개발 의도가 번호≈시간 동일시). UI 정렬은 `order_provider.dart:1010` 주석대로 `shopOrderNo`를 영업일 리셋 비단조성 때문에 **의도적 배제**.

**Why:** 번호 비순차 자체는 (a)시간정렬의 정상 귀결이 1차 원인, (b)tie-break 부재 불안정이 2차 악화 원인. 버그는 (b).

**How to apply:** 결정성 원하면 UI 비교자에 2차 키 추가 — orderedAt 동률 시 `int.parse(shopOrderNo)`(동률=같은 초라 영업일 경계 안 넘어 안전) 또는 displayNum 소스 비교. 운영자 기대가 "번호 오름차순"이면 정렬 키 재검토(단 shopOrderNo 비단조 트레이드오프). [[project_order_intake_essential_complexity]] 의 불변식 존중 — 인쇄 shopOrderNo 정렬은 건드리지 말 것.
