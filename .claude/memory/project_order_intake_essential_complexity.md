---
name: project_order_intake_essential_complexity
description: 주문 접수 흐름은 과도설계가 아니라 본질적 복잡도 — 아키텍처 통합 3안 모두 복잡도 이동 착시로 반증됨 (2026-06-01 적대검증 결론)
metadata: 
  node_type: memory
  type: project
  originSessionId: 181e02d9-e41e-4f1d-a05a-8783a2b14d94
---

2026-06-01 멀티에이전트 적대검증(정찰→반증→judge panel)으로 주문 접수(intake) 흐름의 과도설계 여부를 평가한 결론: **essential_complexity (과도설계 아님).** 복잡도는 외부 조건이 강제한 본질적인 것 — 소켓·폴링·새로고침 3개 비동기 진입 × 서버 PUT 반영지연 × 재부팅 × 멀티디바이스 echo × 별개 프린터 2본체.

검증해본 "더 단순한 설계" 3안(이벤트 리듀서 단일화 / 명시적 상태머신 / 통합 dedup 원장) **모두 not_worth_it** — 라인수는 줄지만 복잡도를 함수본체·호출규약·배치경계로 옮기는 착시(relocated)이고, 옮긴 새 표면에서 race·비대칭 의미손실·타입안전 후퇴를 새로 들임. LoC 감소분 대부분은 죽은 코드라 청소만으로도 회수됨.

**건드리면 안 되는 본질적 복잡도 6선** (각각 특정 불변식의 유일한 방어선):
- `_processedOrderCache.add(NEW)` 가 updateStatus microtask **이전 동기 시점** (자동접수 1회 race window 최소화)
- `_selfAcceptedOrderIds`(소켓·KDS만 등록)와 `_processedOrderCache` 키공간 분리 비대칭 (자가/외부 PREPARING false-positive 방지)
- CANCELLED>DONE 터미널 우선 분기
- 폴링 배치단위 1회 갭복구 + latencyDetected
- `Future.microtask` sync-first 즉시반환 (ANR 방지)
- 라벨 tail 을 영수증 await **전** enqueue (137s backoff 격리)

**Why:** 분할된 10 manager / 캐시·Set 5종 / 3진입경로가 표면상 과해 보여 "통합하자"는 유혹이 반복될 수 있으나, 7개 통합주장이 justified_complexity 로 반증됨. 10 manager 분할은 2,250줄 god-provider 분해로 정당.

**How to apply:** 접수 흐름 "단순화/통합" 요청이 오면 먼저 이 결론과 6선을 제시. 진짜 가치는 죽은코드 청소 + 불변식 테스트지 아키텍처 통합이 아님. 실제 수행한 것: 죽은코드 ~442줄 제거(커밋 ec1d404) + 불변식 회귀테스트 17케이스(커밋 59c1e62). 관련: [[feedback_queue_enqueue_timing]] [[project_order_flow_simplification]]
