---
name: reference-shop-catalog-display-order
description: GET /v0/shops/{shopCode}/categories 응답에 정렬 전용 displayOrder 필드가 있고, 클라이언트가 이를 파싱하지 않은 채 가나다순으로 재정렬해왔던 문제와 수정 내역
metadata:
  type: reference
---

`GET /v0/shops/{shopCode}/categories`(Swagger: `core-stgapi.waldplatform.com/swagger-ui`, `1. 외부 API - item` 그룹) 응답 스키마에는 카테고리(`ShopItemCategoryWithItemsDto`)와 카테고리 내 상품(`items[]`, `ShopItemSummaryDto`) 양쪽에 `displayOrder`(int32) 필드가 있고, "각 카테고리 및 상품은 displayOrder로 정렬"이라고 명시되어 있다. 최상위 `options[]`(`ShopOptionSummaryDto`)에는 이 필드가 없다.

2026-08-05 이전에는 `ShopCategoryModel`/`ProductModel` 모두 이 필드를 파싱조차 하지 않았고, `product_management_screen.dart`의 `_getCategoryNames`는 `Set<String>` + `.sort()`로 강제 가나다순 재정렬해 서버 의도와 무관한 순서로 좌측 카테고리 목록을 보여주고 있었다.

수정: `ShopCategoryModel`/`ProductModel`에 `displayOrder` 필드 추가 후 `api_service.dart`의 `getShopCatalog`에서 채움. `_getCategoryNames`(카테고리 정렬)와 `_productsFor`(상품 정렬, 우측 그리드)를 이 필드 기준으로 정렬하도록 변경. options는 서버 필드가 없어 로컬 인덱스에 `1000000` 오프셋을 더해 "아이템 뒤에 옵션"만 보장(옵션끼리의 순서는 서버 의도 보장 없음 — 향후 서버가 옵션에도 displayOrder를 추가하면 갱신 필요).

교훈: 코드베이스에 필드가 없다고 서버 계약에도 없는 건 아니다 — `docs/`에 API 스키마 문서가 없는 프로젝트에서는 실제 Swagger 문서를 직접 확인해야 정확한 정렬/식별 필드를 놓치지 않는다.
