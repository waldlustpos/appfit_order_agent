---
name: project-fleet-monitoring-branch-strategy
description: "feat/fleet-monitoring는 main+fleet 파일럿 기능 구성으로 유지, main 최신화분을 주기적으로 병합해야 함"
metadata: 
  node_type: memory
  type: project
  originSessionId: 21b54abd-447a-40ba-ae2d-2f63ec989fdd
  modified: 2026-08-05T00:27:29.441Z
---

`feat/fleet-monitoring` 브랜치는 "main의 모든 수정사항 + fleet 관제 파일럿 기능"으로 유지되는 전략. main에서 다른 브랜치들이 계속 머지되며 앞서가므로, fleet-monitoring은 주기적으로 main을 병합해 따라잡아야 함 (리베이스 아님 — 이미 origin에 푸시된 공유 브랜치라 히스토리 재작성 피함).

2026-08-05 기준: main의 11개 커밋(라벨 QR cupIdx 충돌 수정, Sentry 라우팅, MHST 브랜드 이미지, ACK timeout 라벨 중복 수정 등)을 병합 커밋(5f02d5d)으로 반영. 충돌은 `.claude/memory/MEMORY.md` 1건뿐(양쪽 신규 항목 단순 병기로 해결) — `lib/main.dart`(monitoring context 리팩터 vs fleet 배선), `pubspec.yaml`(버전 vs appfit_core ref)은 텍스트 레벨 비충돌로 자동 병합됐고 의미상으로도 정상 결합됨. `flutter analyze` 에러 0건, `flutter test` 303건 전체 통과 확인 후 push.

**Why:** fleet 관제는 아직 파일럿 단계([[project_fleet_monitoring]] 참조 — 별도 repo 메모리에 있다면)라 main에 직접 머지하지 않고 격리된 상태를 유지하되, 다른 수정사항(버그 픽스 등)은 실기기 파일럿에도 반영되어야 하는 요구.

**How to apply:** 앞으로 "main 최신화를 fleet-monitoring에도 반영해달라"는 요청이 오면 rebase가 아니라 `git merge main`(merge commit)으로 처리. 병합 후 반드시 flutter analyze + flutter test로 검증하고 push 전 사용자 확인.
