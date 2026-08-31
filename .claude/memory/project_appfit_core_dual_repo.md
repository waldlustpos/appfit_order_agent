---
name: project_appfit_core_dual_repo
description: appfit_core는 별도 git 레포(appifit_agent_core)이며 앱은 git ref로 소비 — 수정은 태그+푸시+ref 범프 필요
metadata: 
  node_type: memory
  type: project
  originSessionId: 715cfe73-37de-43d5-a270-42669d46302d
  modified: 2026-08-31T05:36:28.791Z
---

`appfit_core`(공통 패키지)는 이 앱 레포 안이 아니라 **별도 레포**에 있다:
- 소스 위치(로컬): `C:\Users\Administrator\Documents\GitHub\appifit_agent_core` (패키지는 `appfit_core/` 하위, 레포 루트는 `appifit_agent_core/`).
- 원격: `https://github.com/ratm10/appifit_agent_core.git`, 브랜치 `main`, 태그 `vX.Y.Z`.
- 앱의 `pubspec.yaml`은 `git: { url, path: appfit_core, ref: vX.Y.Z }`로 **특정 태그를 핀**한다 (path 의존성 아님).

**core 수정 반영 절차** (한 번에 끝까지 해야 앱에 반영됨):
1. core 레포에서 코드 수정 + `appfit_core/pubspec.yaml` version 범프.
2. 커밋 → `git tag vX.Y.Z` → `git push origin main` + `git push origin vX.Y.Z`.
3. 앱 `pubspec.yaml`의 `ref:`를 새 태그로 변경 → `flutter pub get` (lock의 resolved-ref가 새 커밋 해시인지 확인).

**⚠️ stale 사본 함정 — core 코드를 읽을 때 경로를 반드시 확인할 것.**
`~/Documents/GitHub/packages/appfit_core` 는 **오래된 사본**(version 1.0.10)이며 실제 의존성이 아니다. 이름이 `appfit_core` 라서 grep/탐색이 먼저 여기에 걸린다. 실효 정본은 두 곳뿐:
- pub cache: `~/.pub-cache/git/appifit_agent_core-<hash>/appfit_core/` ← **핀된 태그의 실제 코드**
- 소스 레포: `~/Documents/GitHub/appifit_agent_core/appfit_core/` (로컬 체크아웃이 태그보다 뒤처져 있을 수 있음)

실제로 stale 사본이 오판을 만든 사례(2026-08-31): 쿠폰 사용 경로가 `/coupon/{no}/use`(구) vs `/coupon/{no}/use-without-item`(현) 로 다르고, `SentryAppFitLogger` 의 쿨다운 키가 구버전은 `exception.runtimeType` 이지만 현행은 `'http:${status}:${path}'` 이며, 현행에만 있는 `benignServerCodes` 화이트리스트를 구버전 기준으로 "없다"고 판단했다. 서브에이전트에 core 조사를 시킬 때는 읽을 경로를 지정해줄 것.

주의: core 레포는 `safe.directory` 예외 등록 필요(소유자 BUILTIN/Administrators). 로컬 main이 원격보다 뒤처져 push rejected 가능 → fetch 후 rebase, 충돌은 보통 `pubspec.yaml` version 줄 하나. rebase 후 `git tag -f`로 태그를 새 커밋에 재배치.

연관: [[project_store_printer_topology]]
