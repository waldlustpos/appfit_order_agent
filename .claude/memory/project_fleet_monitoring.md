---
name: project-fleet-monitoring
description: "기기 관제(Fleet) 플랫폼 — 구현·배포·appfit_core 승격 완료, 실기기 파일럿 대기"
metadata: 
  node_type: memory
  type: project
  originSessionId: 3a0dadcc-6e12-434f-905b-9125df444d34
  modified: 2026-08-03T00:57:27.355Z
---

앱 실행상태·기기정보·원격 로그 요청을 다루는 최소 관제 플랫폼. 2026-07-31 배포 완료, 2026-08-03 appfit_core 승격 완료. 실기기 파일럿만 남음.

- 백엔드: **별도 레포** `~/Documents/GitHub/appfit-fleet` (Cloudflare Workers + D1). 대시보드 https://appfit-fleet.sckim.workers.dev, 자격정보는 그 레포의 `DEPLOYMENT.local.md`(gitignore).
- 공통 리포터: `appfit_core/lib/src/fleet/`(레포 `appifit_agent_core`, 로컬 `~/Documents/GitHub/appifit_agent_core` — `~/Documents/GitHub/packages/appfit_core` 는 stale clone, 건드리지 말 것). v1.0.18 이상. `package:appfit_core/appfit_core.dart` barrel export.
- 앱: 브랜치 `feat/fleet-monitoring` (**미푸시**). 앱 전용 파일만 `lib/services/fleet/`(snapshot builder·command handler·provider). 설계 정본은 `docs/DEVICE_MONITORING.md`.

**Why:** 매장 기기가 살아있는지 볼 방법이 없었고, 로그 전송 버튼은 `showInternalUi = !kReleaseMode` 뒤라 매장 출고본에서 아예 안 보여 원격으로 로그를 받아낼 경로가 없었다.

**How to apply:**
- 원래 사용자가 **"앱 안에 먼저, 검증 후 core 승격"** 으로 결정했었으나(`fleet_core_isolation_test.dart` 로 격리 강제), 2026-08-03 에 실기기 파일럿을 기다리지 않고 앞당겨 승격을 진행하기로 재결정했다. 승격 절차: appfit_core 에 `lib/src/fleet/` 4파일 이식(import 를 `package:appfit_core/src/...` 내부 참조로 치환) → barrel export 추가 → 테스트 4개 `appfit_core/test/` 로 이식 → `pubspec.yaml` 버전만 올리고 `bash tool/release.sh`(직접 git tag/push 금지, [[feedback-appfit-core-release]]) → 소비 앱 `pubspec.yaml` ref 범프. 격리 테스트(`fleet_core_isolation_test.dart`)는 승격 완료로 폐기.
- **appfit_core 는 3앱(order_agent·did·kiosk) 공유지만 git ref 로 핀 고정**이라, main 에 새 태그를 푸시해도 각 앱이 `pubspec.yaml` ref 를 명시적으로 올리기 전까지는 영향이 없다. order_agent 도 이번 ref 범프는 `feat/fleet-monitoring` 브랜치에서만 했고 `main`(운영 배포 기준)은 기존 버전 그대로다.
- DID/KIOSK 배선은 여전히 파일럿 안정화 이후. core 승격이 끝나 이제 `package:appfit_core/appfit_core.dart` 하나만 import 하면 된다. DID 는 `commandHandler` 를 주입하지 **않는다**(로그 수집 기능이 없어 UNSUPPORTED 자동 응답이 정답).
- 남은 실기기 검증 3종: 강제종료 후 3분 stale/15분 offline, Windows 창 닫기 → closing, **릴리즈 APK 에서 설정 로그카드는 숨겨진 채 원격 명령은 동작**. 마지막 건 개발 기기에서 절대 안 드러나는 종류다.
- fleet 경로(`lib/services/fleet/`, `fleet_provider.dart`)에 `kReleaseMode` 가드를 넣지 말 것. 넣으면 매장 기기에서만 정확히 동작하지 않는다.

관련: [[reference-cloudflare-worker-traps]], [[feedback-appfit-core-release]], [[project_appfit_core_dual_repo]]
