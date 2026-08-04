---
name: project_label_qr_cupidx_collision
description: "신규 라벨 QR 포맷(표시번호-컵순번)에서 서로 다른 메뉴가 전부 \"-0\"으로 충돌하던 버그와 수정"
metadata: 
  node_type: memory
  type: project
  originSessionId: 58f6ecef-cc2d-437e-a105-d6ef9fb31685
  modified: 2026-08-04T03:37:53.511Z
---

신규 라벨 QR 페이로드 전략(`DisplayNumIndexQrPayloadStrategy`, `lib/services/label_printer/qr_payload_strategy.dart`)이 컵순번(cupIdx)을 `menuInfo.labelSeq - 1`(같은 메뉴=shopItemId 안에서만 1부터 리셋)로 계산해, 같은 주문 안에서 메뉴가 다르면(각각 qty=1이면) 전부 "표시번호-0"으로 충돌하는 버그가 있었음. 2026-08-04 아침 커밋(3365362)이 이 신규 포맷을 기본값(0→1)으로 바꾸면서 바로 노출됨.

기존(레거시) 포맷 `DefaultQrPayloadStrategy`는 페이로드에 ShopItemId 가 포함돼 있어 같은 버그가 없음 — cupIdx 는 "같은 메뉴 반복분(qty>1)"만 구분하면 되고 메뉴 간 유일성은 ShopItemId 가 보장. 신규 포맷은 ShopItemId 를 안 담기 때문에 cupIdx 자체가 주문 전체에서 유일해야 함.

`buildPayload(orderInfo, menuInfo, labelIndex, labelTotal)`의 `labelIndex` 파라미터가 이미 주문 전체를 관통하는 1-based 누적 인덱스([label_print_data.dart](../../../Documents/GitHub/appfit_order_agent/lib/services/label_printer/label_print_data.dart)의 `menuStartIndex` 기반 계산, output_service.dart 가 라벨에 실제 인쇄하는 "주문번호-순번" 접미사(`data.orderIndex`)와 동일 값)로 전달되고 있었는데, 신규 전략이 이걸 안 쓰고 메뉴별 리셋값을 잘못 참조한 게 원인. 수정: cupIdx = `labelIndex - 1` 로 교체(같은 세션에서 완료, 미커밋).

**Why:** 인쇄되는 라벨 텍스트("0029-1", "0029-2"...)와 QR 내용이 서로 다른 카운터를 쓰면서 어긋났음. 이 전략류에 대한 단위 테스트가 없어 회귀로 재발 가능.

**How to apply:** [[project_order_output_audit_2026_07]]·라벨 QR 관련 요청 시 참고. QR 포맷을 브랜드/전역 전략으로 새로 만들 때 payload 에 ShopItemId 가 빠지면 cupIdx 는 반드시 order-wide `labelIndex` 를 써야 함(메뉴별 `labelSeq` 아님). 향후 `qr_payload_strategy_test.dart` 같은 단위 테스트 추가를 고려.
