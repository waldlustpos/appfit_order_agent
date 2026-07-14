---
name: project-app-env-gitignored-variant
description: "lib/config/app_env.dart + .env 는 gitignore된 머신별 로컬 파일 — 브랜치가 새 AppEnv 멤버를 추가하면 stale 로컬 사본에서 빌드가 \"Member not found: <멤버>\" 로 실패"
metadata: 
  node_type: memory
  type: project
  originSessionId: 21823625-bf7e-4761-afbd-ba1abf7d5370
---

`lib/config/app_env.dart` 는 `.gitignore` 됨 — git 비추적, 머신별 로컬 수작업 파일(생성기 없음). `.env`(APPFIT_AES_KEY/SENTRY_DSN/SLACK_* 등 주입원) 도 마찬가지. 브랜치가 `AppEnv` 에 새 멤버(대개 `static const` + `String.fromEnvironment`)를 추가하고 커밋된 코드가 이를 참조하면, **구버전 로컬 `app_env.dart` 를 가진 머신에서 빌드가 CFE 컴파일 단계(`flutter_assemble`, Windows·Android 공통)에서 `Member not found: '<멤버>'` 로 실패**한다.

이력: 초기엔 듀얼 변형이 `variant`/`isStandalone` 을 추가해 이 트랩을 만들었으나, **그 둘은 커밋 61828a2 "빌드 변형 제거"에서 삭제됨**(단일 빌드 — APPFIT_VARIANT 없음). 2026-07 `feat/log-upload-slack` 기준 현재 참조되는 멤버는: `showInternalUi`(`= !kReleaseMode`), `slackBotToken`(`SLACK_BOT_TOKEN`), `slackChannelId`(`SLACK_CHANNEL_ID`). login_screen/settings_screen/settings_right_panel/slack_direct_sink 가 사용. 멤버 목록은 브랜치마다 계속 바뀌니 이름 자체보다 **패턴**(gitignored stale 로컬 → Member not found)을 기억할 것.

const 컨텍스트에서 쓰이는 멤버는 **getter 불가, 반드시 `static const`**.

**Why:** gitignored 라 git diff/history 에 안 보여 진단이 어렵고, 새 머신·재클론·구버전 로컬 보유 시마다 재발한다. 사용자가 로컬 `app_env.dart`+`.env` 를 갱신하면 해결.
**How to apply:** 이 에러를 보면 참조 코드(`grep <멤버>`)가 기대하는 멤버를 로컬 `app_env.dart` 에 추가하고 대응 `.env` 키를 채운다. 커밋되지 않으니 머신마다 반복. 이후 남은 `Building Windows application` 실패는 별개 원인([[project_windows_standalone_first_install_pass_fails]] MSB3073 첫 INSTALL 패스, ephemeral C1083→`flutter clean`) 일 수 있음.
