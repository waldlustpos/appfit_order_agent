---
name: 서버 전환 재로그인 크래시 (2026-04-23 조사)
description: 로그아웃 → 로그인 화면에서 서버(환경) 변경 → 재로그인 시 앱이 크래시. 원인 4종 확인, 수정 보류 상태
type: project
originSessionId: 79ed1839-7d0d-4029-a5d7-1b30b0158c00
modified: 2026-07-22T05:30:59.161Z
---
## 상태
- 조사일: 2026-04-23
- 사용자 지시: "확인해둬" (원인 파악만, 수정 보류)
- 재현 시나리오: 로그아웃 → login_screen에서 서버 설정 변경 → 재로그인 → 크래시

## 확인된 크래시 원인 후보 (4개)

### 1. appFitNotifierServiceProvider invalidate 누락 (가장 유력)
- [lib/screens/login_screen.dart:946-947](lib/screens/login_screen.dart#L946-L947) 환경 변경 시 `appFitTokenManagerProvider`, `appFitDioProvider`만 invalidate.
- [lib/services/appfit/appfit_providers.dart:38-40](lib/services/appfit/appfit_providers.dart#L38-L40) `appFitNotifierServiceProvider`는 NotifierProvider — invalidate 안 됨.
- 로그인 시 [lib/providers/auth_provider.dart:143-148](lib/providers/auth_provider.dart#L143-L148)에서 `notifier.connect()` 호출 시 이전 환경 WebSocket 상태가 남아있어 충돌 가능.

### 2. logout() 실질 정리 누락
- [lib/providers/auth_provider.dart:191-196](lib/providers/auth_provider.dart#L191-L196) `logout()` 메서드가 주석만 있고 비어있음. TokenManager 상태/SecureStorage 정리 없음.
- home_screen에서는 `cleanupOnLogout()`만 호출(OrderProvider 정리), WebSocket disconnect는 불명확.

### 3. SecureStorage의 projectId/apiKey 환경별 미구분
- [lib/providers/auth_provider.dart:132-138](lib/providers/auth_provider.dart#L132-L138) WebSocket connect 직전에 SecureStorage의 `appFitProjectId`, `appFitProjectApiKey` 읽음.
- 로그아웃 시 이 값들이 정리되지 않아 새 환경 로그인 순간에 **이전 환경의 projectId/apiKey로 새 환경 WebSocket 연결 시도** 가능.

### 4. keepAlive Provider 이전 상태 잔존
- [lib/providers/order_provider.dart:44](lib/providers/order_provider.dart#L44) `@Riverpod(keepAlive: true)`
- 환경 변경 시 invalidate 되지 않음. `ProviderScope`도 재생성되지 않아(main.dart:132) 전역 상태가 이전 환경 컨텍스트를 유지.

## 핵심 참조 지점
- 환경 변경 핸들러: [lib/screens/login_screen.dart:929-950](lib/screens/login_screen.dart#L929-L950)
- 로그인 흐름: [lib/providers/auth_provider.dart:75-189](lib/providers/auth_provider.dart#L75-L189)
- 로그아웃 지점: [lib/screens/home_screen.dart:307](lib/screens/home_screen.dart#L307), [home_screen.dart:386](lib/screens/home_screen.dart#L386), [settings_screen.dart:272](lib/screens/settings_screen.dart#L272)
- AppFitConfig.configure는 [lib/main.dart:61-64](lib/main.dart#L61-L64)에서 앱 시작 시 1회 호출 + login_screen.dart:941에서 재호출

## Why
서버 환경 다중 지원(live/dev/staging/japanLive) 앱이지만, 런타임 환경 전환 시 상태 리셋이 불완전. ProviderScope 재생성 없이 환경만 바꾸는 구조라 엣지 케이스 많음.

## How to apply
차후 수정 요청 시 우선순위:
1. login_screen 환경 변경 핸들러에서 `appFitNotifierServiceProvider` 및 `orderProvider` invalidate 추가
2. `auth_provider.logout()`에 SecureStorage의 projectId/apiKey/token 명시적 삭제 추가
3. 환경 변경 시 WebSocket `disconnect()` 선행 호출 보장
4. 이상적으로는 환경 변경 후 `Phoenix.rebirth()` 수준의 전체 재시작 고려

## +2026-07-22 원인 #4(keepAlive 잔존) 구체 사례 진단·수정
- **Sentry 62c783657cbe4d2c977d5928aaa9a514**: PAIK00001 로그아웃 → TPCP00001(둘 다 japanLive, **서버 전환 아님·매장 전환**) 로그인 후 `HTTP 404 GET /v0/shops/PAIK00001/categories · NOT_FOUND_SHOP`. stack: `shopCatalog`(product_provider.dart) → `getShopCatalog`(api_service.dart) → dio. 이전 매장 PAIK00001 로 카탈로그 조회.
- **원인**: `storeProvider`·`shopCatalogProvider`(둘 다 keepAlive) 가 로그아웃 경로(`home_screen._handleLogout`)에서 초기화되지 않아 이전 매장 식별자 잔존 → TPCP 로그인 전환 중 리빌드가 stale PAIK 로 조회.
- **핵심 함정**: Riverpod `AsyncLoading` 은 이전 매장을 `.value` 로 유지할 수 있고, 그 상태의 `storeProvider.future` 는 **이전 값으로 즉시 완료**될 수 있어 `await future` 만으로는 stale 을 못 거른다. 근본 해결은 **로그아웃 시 매장 스코프 keepAlive 초기화**.
- **수정(미커밋·워킹트리, 브랜치 chore/deps-tier1-upgrade — 별개 사안이라 미커밋)**:
  1. `home_screen._handleLogout`: `cleanupOnLogout()` 직후 `ref.invalidate(shopCatalogProvider)` + `ref.invalidate(storeProvider)`. (shopCatalog 무효화는 productProvider/shopCategoryList 로 전파)
  2. `product_provider.shopCatalog` 하드닝: `storeProvider.isLoading` 이면 `await future` 후 **여전히 로딩이면 조회 보류(빈 카탈로그 반환)** — settle 시 watch 재빌드로 올바른 매장 조회. 최초 로딩(이전 값 없음)은 future 가 첫 settled 까지 대기하므로 정상.
  3. 테스트: `test/providers/shop_catalog_store_switch_test.dart`(전환 + 로딩 가드 2건, `_FakeApiService`/`_FakeStore` 시드는 order_cache_manager_test 미러). 전체 224 pass, analyze 클린.
- 계획서: `~/.claude/plans/sentry-62c783657cbe4d2c977d5928aaa9a514-streamed-dolphin.md`.
- **동반 토큰 404 2건(e0eaaa…/edf6af…)도 같은 뿌리 → 이 수정으로 함께 해결**: appfit_core Dio 인터셉터(`dio_provider._getShopCodeFromOptions`)는 **요청 경로/쿼리에서 shopCode를 추출**해 그 shopCode로 `getValidToken`을 호출한다. stale `GET /shops/PAIK00001/categories`·`/migration/options?shopCode=PAIK00001` 요청이 각각 shopCode=PAIK00001 을 인터셉터에 넘김 → 현재 캐시 토큰(TPCP)과 mismatch → **`issueToken(PAIK00001, password=현재 TPCP 비번)` → `POST /v0/auth/sign-in` → 404 NOT_FOUND_OWNER**(`[Token] 로그인 요청 오류`) → 인터셉터 catch 가 `reject(type:cancel,'토큰 발급 실패')` → `DioException [request cancelled]`. 즉 토큰 404는 categories 404의 **자식(파생)**. stale 요청이 안 나가면(=storeProvider 리셋+settled-guard) 인터셉터 shopCode 도 없어 sign-in 자체가 사라진다. **교훈: 인터셉터가 요청별 shopCode 로 매장별 토큰을 재발급하므로, 잘못된 매장 ID 로 나가는 요청 1건이 데이터 404 + 토큰 sign-in 404 를 동시에 유발한다.**
