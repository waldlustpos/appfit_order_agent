---
name: reference_store_id_is_getid
description: 매장 ID 정본은 PreferenceService.getId() — getStoreId()/KEY_STORE_ID 는 쓰는 코드가 없는 죽은 API
metadata: 
  node_type: memory
  type: reference
  originSessionId: 6533b9fb-864e-4ce6-bf7e-7fd77589eb30
  modified: 2026-08-12T04:48:43.662Z
---

`PreferenceService` 에 매장 ID 처럼 보이는 게 둘 있는데 **하나는 죽어 있다.**

- **정본**: `getId()` / `saveId()` (`KOKONUT_M_ID`). 로그인 시 저장, 대문자 정규화. 브랜드 해석(`BrandRegistry.resolveOrNull` → `storeIdPrefix`)도 이 값을 쓴다.
- **죽음**: `getStoreId()` (`KOKONUT_STORE_ID`) — **쓰는 코드가 리포 전체에 없어 항상 null.** 이름만 보고 고르면 조용히 null 을 받는다.

2026-08-12 빠른 메뉴 지정 저장이 이 함정으로 통째로 실패했다. 키가 null 이라 저장이 스킵됐고, 화면·로그 어디에도 흔적이 없어 사용자 제보로만 발견됨.

**교훈 두 개**:
- 매장 단위 저장 키를 만들 땐 `getId()` 를 쓰고, 이름이 그럴듯한 getter 는 grep 으로 writer 존재를 먼저 확인할 것.
- "저장 못 했음" 을 `void` + 로그로 흘리면 안 된다. bool 을 돌려주고 UI 가 알리게 할 것 — 회귀 테스트는 `test/services/fast_menu_prefs_test.dart`.

관련: [[project_fast_menu_priority]]
