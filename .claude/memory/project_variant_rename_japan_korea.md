---
name: variant-rename-japan-korea
description: 변형 완전 폐기 → 단일 빌드 + 런타임 서버선택(live/japanLive) 전환 (2026-07-09 최종)
metadata: 
  node_type: memory
  type: project
  originSessionId: 18e983c7-54ce-45c0-a7cf-f76041047780
---

**+2026-07-09(2차) 단일 빌드 + 런타임 서버선택 (현재 정본)**: 같은 날 진행한 dart-define 통합을 사용자 결정으로 폐기하고 더 단순한 모델로 전환. 빌드 변형(`APPFIT_VARIANT`)·변형 인자 전부 제거, **하나의 APK/exe가 한국/일본 서빙**.
- **서버 결정(런타임)**: 저장값(`appfit_environment`, 기본 live) + 로그인 배지(KR/JP, 릴리즈 항상 노출, 릴리즈 목록 live/japanLive 2종·debug 4종) + **매장 ID 프리픽스 자동 전환**(`BrandRegistry.serverEnvironment`: TPCP·PAIK→japanLive, MHST·MATA→live, live/japanLive 세션에서만 동작). 미등록 프리픽스는 `appfit_environment_manual_override` 미설정 시 로그인에서 다이얼로그 1회 강제(사용자 지정 방식). release는 dev/staging 잔존값을 main.dart에서 live로 클램프+저장 정정.
- **전환 시퀀스**: `login_screen.dart _applyEnvironment()` 로 추출(다이얼로그·프리픽스 공용) — unauthenticate→setEnvironment+override→configure→토큰/자격증명 정리→tokenManager/dio invalidate. NotifierService invalidate 금지(late final) 불변. [[서버 전환 재로그인 크래시 (2026-04-23 조사)]] 방어(dddcc33) 그대로 재사용.
- **OTA 채널**: Android `_appfit` 단일 신설(`appfit_order_agent_appfit.apk/_version.json`), 구 `_japan`/`_korea` 폐기. **무접미 레거시 동결 유지**(구 패키지 일본 매장 1곳, 수동 재설치 시까지 — 재설치 후엔 프리픽스 자동 전환이 japanLive 지정). Windows는 레거시 무접미 채널이 곧 단일 채널(기존 설치본 자연 업데이트). 단일 채널=한/일 동시 롤아웃(시차 배포 불가) 인지 수용.
- **스크립트**: build_main.sh/deploy_apk.sh/build_windows.ps1/deploy_windows.ps1/build_installer.ps1/archive_* 전부 인자 제거, installer 산출물 `AppfitOrderAgent-Setup-*.exe` 단일(iss `#ifdef Korea` 삭제). deploy/release 커맨드 md에서 변형 질문 삭제.
- **주의**: `lib/config/app_env.dart`는 gitignore 로컬 파일 — region/isKorea 삭제를 **다른 빌드 머신에도 수동 반영 필요**. HEAD 트랙 코드가 참조하던 isStandalone/isKorea 정의가 리포에 없어 과거 커밋 단독 체크아웃은 컴파일 불가.
- 이력: 통합(dart-define) 작업은 c3f226d로 보존 커밋 후 그 위에 전환. analyze 0 err/test +201 통과. 계획 `~/.claude/plans/appfit-jaunty-hamming.md`.

---
아래는 이전 단계 기록(같은 날 오전, dart-define 통합 — 위 전환으로 대체됨):

**단일 패키지 통합**: applicationId·Windows exe(`appfit_order_agent.exe`)·mutex·설치 GUID를 `co.kr.waldlust.order.receive.appfit` 하나로 통일, Android flavor 완전 제거, 아이콘 그라데이션 main 병합. 국가는 `--dart-define=APPFIT_VARIANT=japan|korea`로 구분(release 서버·OTA 채널 `_japan`/`_korea`·KR/JP 배지 분기) — **이 분기 축이 2차에서 제거됨**. korea GUID `{E448C213...}`는 폐기·재사용 금지(iss 주석). 그 이전의 update/standalone→japan/korea 개명 이력 포함.

연관: [[standalone-ota-channel]] (OTA 채널 분기 도입 이력 — 현재는 단일 채널로 대체).

**+2026-07-13 릴리즈 서버선택에 staging 추가**: 사용자 결정으로 위 "릴리즈는 live/japanLive 2종" 정책을 일부 완화. `login_screen.dart _showEnvSelectDialog()` envOptions를 릴리즈에서 `['staging', 'live', 'japanLive']`로 변경(dev는 여전히 showInternalUi 뒤에 숨김). `main.dart` 시작 시 클램프도 `environment == AppFitEnvironment.dev`일 때만 live로 강제하도록 좁혀 staging 선택이 앱 재시작 후에도 유지되게 함(기존엔 kReleaseMode + live/japanLive 아님 전부 클램프 → staging도 재시작마다 live로 되돌아갔음). `app_env.dart`의 `showInternalUi` 자체는 유지(dev 서버선택·개발계정 자동입력·로컬서버·로그전송·개발자옵션은 계속 릴리즈에서 숨김) — staging만 예외적으로 운영 배지 목록에 합류.
