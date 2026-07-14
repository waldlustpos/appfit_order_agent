---
name: 서버 전환 재로그인 크래시 (2026-04-23 조사)
description: 로그아웃 → 로그인 화면에서 서버(환경) 변경 → 재로그인 시 앱이 크래시. 원인 4종 확인, 수정 보류 상태
type: project
originSessionId: 79ed1839-7d0d-4029-a5d7-1b30b0158c00
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
