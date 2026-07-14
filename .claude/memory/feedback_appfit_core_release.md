---
name: feedback-appfit-core-release
description: appfit_core 패키지 새 버전 배포 시 반드시 tool/release.sh 사용. 직접 git commit/tag/push 금지.
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 888b3b68-f9c7-4473-8b1b-3bc7f622bc1e
---

appfit_core 패키지(`/Users/kimsungchun/Documents/GitHub/appifit_agent_core/appfit_core/`)
새 버전 배포는 **`cd appfit_core && bash tool/release.sh`** 만 사용. `pubspec.yaml`의
`version:` 라인만 수정한 뒤 release.sh를 돌리면 그 안의 `dart tool/sync_version.dart`가
`AppFitConfig.packageVersion` 상수를 자동 동기화한 뒤 커밋·태그·푸시까지 수행한다.

**Why:** v1.0.10 최초 배포 시 가이드를 우회해 직접 `git commit` + `git tag v1.0.10`
+ `git push`로 단축한 결과 `AppFitConfig.packageVersion = '1.0.9'`가 남아 강제
정정(amend + force push + force tag)으로 복구해야 했다. 런타임 진단/로그가 잘못된
버전을 출력해 디버깅 혼선을 야기한다. 동일 함정에 다시 빠지지 말 것.

**How to apply:** 사용자가 "appfit_core 버전 올려서 배포" 같은 요청을 하면 반드시
다음 순서를 따른다.
1. `appfit_core/pubspec.yaml`의 `version:` 라인만 수정 (예: `1.0.10` → `1.0.11`).
2. `appfit_core/CHANGELOG.md`에 새 버전 항목 추가.
3. `cd appfit_core && bash tool/release.sh --dry-run` 으로 검증.
4. 이상 없으면 `cd appfit_core && bash tool/release.sh` 실행.
5. `AppFitConfig.packageVersion`을 직접 편집하지 말 것 — release.sh가 자동 동기화한다.
6. 직접 `git commit -m "chore: release ..."` / `git tag v...` / `git push` 호출 금지.

소비자 앱(appfit_order_agent, did 등)의 pubspec.yaml `ref:` 갱신은 release.sh
완료 후 별도 작업으로 처리. `flutter pub upgrade appfit_core`로 resolved-ref가
새 해시로 갱신되는지 확인.

자세한 가이드: [appifit_agent_core/docs/RELEASE.md](../../../../Documents/GitHub/appifit_agent_core/docs/RELEASE.md)
및 [appifit_agent_core/CLAUDE.md](../../../../Documents/GitHub/appifit_agent_core/CLAUDE.md).
