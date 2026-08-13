---
name: project-product-group-bulk-soldout
description: "상품관리 동일 상품명 그룹 일괄 품절 구현 완료 — 코드/테스트/analyze 통과, 실기기 검증 미완 (2026-08-13)"
metadata: 
  node_type: memory
  type: project
  originSessionId: 30c102d8-e958-4830-b663-406629a7881f
  modified: 2026-08-13T13:04:32.676Z
---

상품관리에서 **이름이 같고 가격만 다른 레코드**(주로 옵션. '샷 추가' 500/700/1000원)를 카드 1장으로 묶어 일괄 품절/판매 전환하는 기능. 2026-08-13 구현 완료, **미커밋**.

**확정 정책** (사용자 결정이므로 임의 변경 금지):
- 그룹 키 = `productName` + `type`(ITEM/OPTION). 카테고리는 넘나들어 묶는다
- 그룹은 **all-or-nothing 이 운영 전제**. 전원 품절일 때만 품절로 표시하고, 일부만 품절이면 판매중으로 본다('일부 품절' 배지 없음). 그래야 '전체 품절' 조작으로 정합을 되돌릴 수 있다
- 다이얼로그는 일괄 전용(가격별 개별 토글 없음). 단, **멤버 1개면 기존처럼 반대편 버튼 1개, 2개 이상이면 전체판매/전체품절 2개 항상 노출**

**설계상 되돌리면 안 되는 것**:
- 그룹핑은 **UI 계층 파생만**. `productProvider` 의 `List<ProductModel>` 계약을 출력·라벨·로컬서버 등 7곳이 소비한다
- 낙관적 갱신은 **internalId 매칭**(productId 아님). 그룹 멤버는 POS ID 가 다르고, 같은 상품이 여러 카테고리에 있으면 사본이 여러 개다. `test/providers/product_group_status_test.dart` 의 "카테고리 사본 둘 다 갱신"이 이 회귀를 잡는다

**부수로 제거한 것**: 상태변경 API 가 호출마다 카탈로그 전체를 GET 하던 중복 왕복(구 `updateItemStatus`). 서버는 원래 `itemIds` 배열 벌크 스키마였고 앱만 1건씩 보내고 있었다.

**남은 것 — 실기기(Sunmi/Android 가로) 검증**:
- 다중가격 카드 `500 ~ 1,000원` 이 5열 그리드에서 안 잘리는지
- 전체 품절 → 1회 요청으로 전원 반영, 새로고침 후에도 서버 상태 일치하는지
- **벌크 PUT 이 200 이면서 일부만 반영될 여지** (서버 계약 미확인 — 비200 응답 본문은 로깅해 둠)

관련: [[reference_shop_catalog_display_order]] · [[reference_raw_control_char_breaks_grep]]
