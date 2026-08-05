---
name: project-login-timezone-env-hint
description: "로그인화면 서버(live/japanLive) 초기 선택값을 기기 타임존으로 유도하는 기능 — 구현 완료, 미커밋·미검증."
metadata: 
  node_type: memory
  type: project
  originSessionId: 74594566-8476-4a14-ad1a-6837e8a4f3f9
  modified: 2026-08-05T07:15:47.452Z
---

완전 신규 설치(매장 ID·KEY_ENVIRONMENT 둘 다 없음) 기기에서 로그인화면 서버선택 초기값이 무조건 `'live'`(한국)로 고정되던 것을, 기기 타임존으로 국가를 추정해 유도하도록 구현 완료(2026-08-05, main 브랜치 커밋 6a838db).

**핵심 제약**: 한국(Asia/Seoul)·일본(Asia/Tokyo)은 UTC 오프셋이 둘 다 +9로 동일해 `DateTime.timeZoneOffset`으로는 구분 불가. 타임존 "ID"가 필요해 네이티브로 조회함 — Android는 `TimeZone.getDefault().getID()`(IANA, `"Asia/Seoul"`), Windows는 레지스트리 `TimeZoneKeyName`(`"Korea Standard Time"`) — 포맷이 서로 다르므로 매핑 함수가 양쪽 문자열 패턴을 모두 검사.

**변경 파일**: `NativeMethodHandler.java`(`getTimezoneId` case) / `lib/services/windows_timezone_service.dart`(신규, win32 레지스트리 읽기 — [[reference-win32-deferred-import]] 패턴 적용) / `platform_service.dart`(`getDeviceTimezoneId()`) / `preference_service.dart`(`_ensureEnvironmentIsSet()` 확장 + `_environmentFromTimezoneId()`).

**적용 범위**: 완전 신규 설치 1회만 개입(`KEY_ENVIRONMENT`가 한 번이라도 저장되면 재평가 안 함). 추정 실패 시 기존과 동일하게 `'live'` 폴백이라 회귀 없음. 매장 ID가 이미 있는 기존 기기 경로(브랜드 레지스트리 기반)는 무변경.

**남은 것**: `flutter analyze` 통과만 확인, 실기기(Android 타임존 변경 + 완전 초기화, Windows 제어판 타임존 변경) 검증 미실시.
