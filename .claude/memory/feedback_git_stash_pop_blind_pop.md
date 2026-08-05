---
name: feedback-git-stash-pop-blind-pop
description: git stash pop을 git stash list 확인 없이 실행하면 이 저장소에 이미 있던 무관한 stash를 잘못 적용할 수 있음
metadata:
  type: feedback
---

"내 워크트리가 clean한지" 확인할 목적으로 `git stash && <검증 명령> && git stash pop`을 체이닝했다가, `git stash`가 "No local changes to save"(내가 스태시할 게 없었음)를 반환했는데도 뒤의 `git stash pop`이 그대로 실행되어 **이 저장소에 이미 존재하던 다른 stash 항목**(`stash@{0}: wip: qr cupidx fix + pubspec 175 + memory notes`, 사용자의 별도 미커밋 작업)을 적용해버렸다. MEMORY.md/pubspec.yaml에 충돌 마커가 생기고 untracked 파일 충돌까지 발생했다(다행히 pop이 실패해 stash 자체는 드롭되지 않고 보존됨 — `git restore --source=HEAD --staged --worktree`로 복구).

**Why:** `.git`은 워크트리 전체가 공유하므로, 지금 세션이 만들지 않은 stash가 이미 리스트에 있을 수 있다. `git stash`가 "no local changes"를 반환했다는 건 "이번에 새로 stash할 게 없었다"는 뜻이지 "stash 리스트가 비어 있다"는 뜻이 아니다.

**How to apply:** `git stash pop`을 실행하기 전에는 반드시 `git stash list`로 무엇을 pop하게 되는지 먼저 확인한다. "임시로 워킹트리를 원복해서 뭔가 확인하고 싶다"는 목적이면 stash보다 [[reference_windows_toolchain_quirks]] 류 격리 수단(별도 worktree, 또는 `git show <ref>:<path>`로 특정 파일만 비교)이 더 안전하다 — 이번 작업에서도 결국 `git show 7441ffb:lib/services/api_service.dart`로 워킹트리를 건드리지 않고 확인하는 방식으로 전환해 해결했다.
