---
name: feedback_concurrent_session_git_state
description: 동시 세션의 git commit -a 가 내 미스테이징 변경분을 함께 쓸어갈 수 있음 — 커밋 전 항상 git status/log 재확인
metadata: 
  node_type: memory
  type: feedback
  originSessionId: fa93ecd7-a7df-4d91-b80b-b4eca5d6c88f
  modified: 2026-09-03T06:25:52.632Z
---

이 레포는 여러 Claude Code 세션이 동시에 작업하는 일이 잦다. 2026-08-05 알림음 TTS 교체 작업 중, `lib/services/preference_service.dart`에 넣어둔 내 수정(getSound() 레거시 파일명 매핑)이 unstaged 상태로 남아 있었는데, 그 사이 동시에 열려 있던 다른 세션(로그인 타임존 기능 작업)이 `git commit -a` 류로 커밋하면서 내 변경분까지 자기 커밋(6a838db)에 함께 실어갔다. 사용자가 "커밋하자"고 했을 때 습관적으로 바로 `git add <내가 만졌던 파일들>`을 했다면, 이미 커밋된 파일을 다시 add하려다 상태를 오인했을 것 — 실제로는 커밋 직전 `git status`를 다시 찍어봐서 preference_service.dart가 더 이상 modified 목록에 없는 것을 보고서야 알아챘다.

**Why:** 동시 세션 환경에서는 "방금 전에 내가 확인한 git 상태"가 다음 액션 시점까지 유효하다고 가정하면 안 된다. 이미 [[feedback_concurrent_deploy_version_race]](배포 버전 넘버가 다른 세션에 의해 계속 바뀌는 레이스)와 [[project_mhst_brand_image_2026_08]](동시 세션 git add/commit 레이스)에서 같은 계열의 문제를 겪었음 — 이번은 버전 넘버가 아니라 "내 미스테이징 변경분 자체가 남의 커밋에 편입"되는 변종.

**How to apply:**
1. 파일을 수정해두고 바로 커밋하지 않은 채 대화가 길어지거나 다른 작업이 끼어들었다면, 커밋을 실행하기 직전에 반드시 `git status` + `git log --oneline -3`으로 HEAD와 unstaged 목록을 재확인한다.
2. 내가 만졌던 파일이 예상과 달리 이미 clean(committed) 상태라면, `git show HEAD -- <file>`로 그 내용이 내가 만든 변경과 동일하게 온전히 들어갔는지만 확인하고 — 온전하면 중복 커밋하지 않는다. 다르면(일부만 반영됐거나 충돌 흔적이 있으면) 사용자에게 바로 보고.
3. `git add`는 항상 관련 파일만 명시적으로 지정한다(`-A`/`-a` 금지는 기존 지침에도 있음). 특히 동시 세션이 만들어둔 무관한 미완성 변경(예: 다른 기능의 memory 파일, 다른 서비스 파일)을 실수로 같이 스테이징하지 않도록 `git status`에 뜨는 각 파일이 내 작업 범위인지 하나씩 판단한다.
4. **`git add <내 파일>` + `git commit` 조합으로는 부족하다 — 반대 방향 사고를 2026-09-03 에 겪었다.** 내 파일만 add 했는데도, 다른 세션이 *이미 스테이징해 둔* 파일 5개(CLAUDE.md·docs/·login_screen.dart)가 같은 커밋에 실려 나갔다. `git commit`은 내가 add 한 것이 아니라 **인덱스 전체**를 커밋하기 때문이다. `git status`의 첫 칸이 `M `(스테이징됨)인 남의 파일이 하나라도 보이면 반드시 **pathspec 커밋** `git commit -m "..." -- <내 경로들>` 을 쓴다 — 워킹트리의 그 경로만 커밋하고 남의 스테이징 상태는 그대로 둔다. 이미 섞여 커밋했다면 `git reset --soft HEAD~1`(인덱스 상태가 커밋 직전 그대로 복원된다) 후 pathspec 으로 다시 커밋하면 복구된다.
