---
name: project_preparing_intake_output_gate
description: "생성시점 PREPARING 주문(NICE_KIOSK)이 일반 모드에서 무출력이던 문제 — KDS 게이트가 원인, 구현 완료·실기기 검증 대기 (2026-09-01)"
metadata: 
  node_type: memory
  type: project
  originSessionId: 1673892a-f0d2-4bbc-83c3-0f95e580fa42
  modified: 2026-08-31T23:47:50.109Z
---

`NICE_KIOSK` 처럼 결제와 동시에 `PREPARING` 으로 생성되는 주문이 **일반(주문접수) 모드에서 주문서·라벨·알림음이 전혀 안 나오던** 문제. 원인은 설정이 아니라 경로 부재였다 — `_processOrderByStatus` 의 PREPARING 분기 전체가 `ref.read(kdsModeProvider)` 에 갇혀 있어, 키오스크 출력·소리 설정을 ON 해도 **그 설정을 읽는 줄에 도달조차 못 했다.**

수정: 소켓 매니저의 기존 판정 `isExternallyAcceptedAtCreation`(=`ORDER_CREATED && PREPARING`)을 표식으로 삼아 게이트를 `KDS || 표식` 으로 완화. `notifyExternallyAcceptedOrder` → `ingestExternallyAcceptedOrder` 로 승격해 **표식→사운드그래프→큐 순서를 함수가 소유**하게 했다(호출부 순서 계약 제거). 테스트 (j) 그룹 5케이스 신설, 43개 전부 통과. **미커밋·실기기 검증 대기.**

**비자명한 판정 3가지:**

1. **출처 억제는 `isSourceNotifyEnabled` 로만.** `shouldNotifyForOrder` 는 `status == NEW` 일 때만 억제를 적용해서, PREPARING 주문은 설정을 OFF 해도 통과한다 — 쓰면 "OFF 인데 출력되는" 반대 버그가 난다.

2. **상태만 보고 게이트를 열면 안 된다.** 일반 모드에도 "다른 단말이 접수한 주문"의 `ORDER_ACCEPTED`(PREPARING) 가 들어와서, 매장에 깔린 단말 수만큼 같은 주문서가 중복 출력된다. `ORDER_CREATED` 한정이 구분의 전부다.

3. **1회성 소비는 `||` 우변에 두면 안 된다.** `(kdsMode || _set.remove(id))` 는 KDS 모드에서 단축평가로 `remove` 가 실행되지 않아 표식이 영구 잔류한다. 조건식 밖에서 먼저 평가할 것.

**폴링 경로는 서버 변경 없이는 불가** — 폴링 응답에 eventType 이 없고 `OrderModel` 에 `acceptedAt`/`acceptedBy`/`deviceId` 가 없어 "생성시점 PREPARING" 과 "다른 단말이 이미 출력한 주문" 을 원리적으로 구분할 수 없다. "나중에 하자" 가 아니라 "불가" 로 기록됨.

**별건 발견**: KDS 모드 + `getKdsAcceptOrders()==false` 면 `ORDER_CREATED` 가 `_shouldIgnoreByDomainPolicy` 에서 폐기되어 같은 증상이 KDS 에도 존재(사운드그래프 전송조차 안 됨). 미수정.

관련: [[project_order_intake_essential_complexity]] · [[project_order_output_audit_2026_07]] · [[project_membership_unregistered_intake]]
