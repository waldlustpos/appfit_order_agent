---
name: project_appfit_core_dual_repo
description: appfit_core는 별도 git 레포(appifit_agent_core)이며 앱은 git ref로 소비 — 수정은 태그+푸시+ref 범프 필요
metadata: 
  node_type: memory
  type: project
  originSessionId: 715cfe73-37de-43d5-a270-42669d46302d
---

`appfit_core`(공통 패키지)는 이 앱 레포 안이 아니라 **별도 레포**에 있다:
- 소스 위치(로컬): `C:\Users\Administrator\Documents\GitHub\appifit_agent_core` (패키지는 `appfit_core/` 하위, 레포 루트는 `appifit_agent_core/`).
- 원격: `https://github.com/ratm10/appifit_agent_core.git`, 브랜치 `main`, 태그 `vX.Y.Z`.
- 앱의 `pubspec.yaml`은 `git: { url, path: appfit_core, ref: vX.Y.Z }`로 **특정 태그를 핀**한다 (path 의존성 아님).

**core 수정 반영 절차** (한 번에 끝까지 해야 앱에 반영됨):
1. core 레포에서 코드 수정 + `appfit_core/pubspec.yaml` version 범프.
2. 커밋 → `git tag vX.Y.Z` → `git push origin main` + `git push origin vX.Y.Z`.
3. 앱 `pubspec.yaml`의 `ref:`를 새 태그로 변경 → `flutter pub get` (lock의 resolved-ref가 새 커밋 해시인지 확인).

주의: core 레포는 `safe.directory` 예외 등록 필요(소유자 BUILTIN/Administrators). 로컬 main이 원격보다 뒤처져 push rejected 가능 → fetch 후 rebase, 충돌은 보통 `pubspec.yaml` version 줄 하나. rebase 후 `git tag -f`로 태그를 새 커밋에 재배치.

연관: [[project_store_printer_topology]]
