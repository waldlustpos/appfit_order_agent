---
name: project_standalone_ota_channel
description: standalone 배포 변형의 인앱 OTA를 별도 채널로 분기 (APPFIT_VARIANT dart-define)
metadata: 
  node_type: memory
  type: project
  originSessionId: af9f49bb-17b1-45de-b7d5-5ebbcbd1fd65
---

dual-variant 빌드(update/standalone)에서 인앱 OTA가 항상 update 채널만 받던 갭을 메움 (2026-06-25 작업).

**구조**: 빌드 타임 `--dart-define=APPFIT_VARIANT=<update|standalone>` 주입 → `AppEnv.variant`/`AppEnv.isStandalone`(`lib/config/app_env.dart`)으로 읽음 → `OtaConfig`(Android, `lib/config/ota_config.dart`)·`UpdateConfig`(Windows, `lib/config/update_config.dart`)가 `isStandalone`으로 채널 URL을 **컴파일 타임 const 분기**. standalone은 임시 작업 파일명(extract/bat/vbs/log)도 분리해 병존 설치 시 동시 업데이트 충돌 방지.

**채널 파일명**: standalone은 update 파일명에 `standalone` 세그먼트 삽입 (Android: `appfit_order_agent_standalone_version.json`/`_standalone.apk`, Windows: `appfit_order_agent_standalone_windows_version.json`/`_standalone_windows.zip`).

**스크립트**: build_main.sh / deploy_apk.sh(인자 `update|standalone`), build_windows.ps1 / deploy_windows.ps1 / build_installer.ps1(`-Variant`)에 dart-define 주입 추가. 인자 생략 시 update.

**주의**: Windows OTA 설치 시 kill/restart할 exe명은 런타임 `Platform.resolvedExecutable`에서 추출 → standalone exe도 자동 처리 (`UpdateConfig.exeName` 상수는 런타임 install 경로 미사용). `build_windows.sh`는 -Variant 없는 보조 스크립트라 미수정(항상 update).

`/deploy` 커맨드는 `/deploy-android`로 개명(Android 명시) + 실행 시 update/standalone/둘다 선택. 문서: docs/BUILD.md "배포 변형 (update / standalone) 과 OTA 채널" 섹션.
