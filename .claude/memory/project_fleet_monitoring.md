---
name: project-fleet-monitoring
description: 기기 관제(Fleet) 플랫폼 — 구현·배포 완료, 실기기 파일럿 대기. core 승격은 검증 후로 미룸
metadata:
  type: project
---

앱 실행상태·기기정보·원격 로그 요청을 다루는 최소 관제 플랫폼. 2026-07-31 배포 완료, 실기기 파일럿만 남음.

- 백엔드: **별도 레포** `~/Documents/GitHub/appfit-fleet` (Cloudflare Workers + D1). 대시보드 https://appfit-fleet.sckim.workers.dev, 자격정보는 그 레포의 `DEPLOYMENT.local.md`(gitignore).
- 앱: 브랜치 `feat/fleet-monitoring` (**미푸시**), 커밋 4개. 설계 정본은 `docs/DEVICE_MONITORING.md`.

**Why:** 매장 기기가 살아있는지 볼 방법이 없었고, 로그 전송 버튼은 `showInternalUi = !kReleaseMode` 뒤라 매장 출고본에서 아예 안 보여 원격으로 로그를 받아낼 경로가 없었다.

**How to apply:**
- 원 요구는 "appfit_core 에 공통 구현"이었지만, 사용자가 **"앱 안에 먼저, 검증 후 core 승격"** 으로 결정했다. 그래서 `lib/services/fleet/core/` 4파일은 승격 대상이고 core 바깥 앱 코드를 import 하지 않는다 — `fleet_core_isolation_test.dart` 가 강제한다. 이 테스트가 빨개지면 승격이 재설계가 된 것이니 고쳐서 통과시킬 것.
- DID/KIOSK 배선과 core 승격은 파일럿 안정화 이후. DID 는 `commandHandler` 를 주입하지 **않는다**(로그 수집 기능이 없어 UNSUPPORTED 자동 응답이 정답).
- 남은 실기기 검증 3종: 강제종료 후 3분 stale/15분 offline, Windows 창 닫기 → closing, **릴리즈 APK 에서 설정 로그카드는 숨겨진 채 원격 명령은 동작**. 마지막 건 개발 기기에서 절대 안 드러나는 종류다.
- fleet 경로(`lib/services/fleet/`, `fleet_provider.dart`)에 `kReleaseMode` 가드를 넣지 말 것. 넣으면 매장 기기에서만 정확히 동작하지 않는다.

관련: [[reference-cloudflare-worker-traps]], [[feedback-appfit-core-release]]
