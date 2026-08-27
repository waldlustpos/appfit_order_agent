---
name: project-order-force-done
description: "PREPARING→DONE 강제완료 — force/bulk-done 단건 호출로 구현 완료, 실기기 검증 대기"
metadata: 
  node_type: memory
  type: project
  originSessionId: 4fe773e2-1762-4a31-9c37-76d0b806c461
  modified: 2026-08-27T08:23:32.797Z
---

주문 상세창의 '주문 완료' 버튼이 PREPARING 에서 서버에 거부되던 문제(단계 강제:
READY→DONE 만 허용)를 `PUT /v0/orders/force/bulk-done`
(`{shopCode, orderNos[]≤100}` + 건별 `results[]`)을 **단건으로** 호출해 해결.
2026-08-27 구현 완료(analyze errors 0 / test 581 통과), **실기기 검증 대기·미배포**.
정본: `docs/ORDER_FORCE_DONE.md`. appfit_core v1.5.0 릴리즈 + 앱 ref 범프 완료.

**Why:** 초기 서버 판은 `bulk-done` 과 DTO 를 공유해 `{shopCode, from, to}` 기간
단위였고 주문 카드 버튼에 걸면 매장 전체가 완료되는 사고 경로였다. 재구현으로
해소됐지만 **기간 방식 `bulk-done` 은 그대로 남아 있고**(앱 '전체 완료' 버튼이
사용 중), 서버가 모르는 필드를 에러 없이 버리므로 경로를 헷갈리면 400 이 아니라
조용히 엉뚱한 대상이 완료된다. 그래서 core 에 경로 고정 테스트를 뒀다.

**How to apply:** 성공 판정은 `updateSuccessCount` 가 아니라 `isSuccessFor(orderNo)` —
카운터는 "대상에서 빠짐" 과 "처리 실패" 를 구분 못 한다. 성공 후처리는
`_applySuccessfulStatusTransition` 하나로 `updateOrderStatus` 와 공유(복사하면
`_recentRemovals.mark` 누락 같은 드리프트가 난다). 서버 미확인 3건: 건너뛴 READY 의
WebSocket 이벤트 발생 여부(확답 전까지 ORDER_DONE + ORDER_PICKUP_REQUESTED 둘 다
억제 중) / 대상 외 주문의 results 표현 / live·japanLive 배포 일정. live 는 swagger 를
안 내려주므로 **swagger 부재를 미배포 근거로 쓰지 말 것**. 관련:
[[project-order-intake-essential-complexity]], [[feedback-appfit-core-release]]
