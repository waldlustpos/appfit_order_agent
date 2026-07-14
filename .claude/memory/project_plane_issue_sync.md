---
name: project_plane_issue_sync
description: Plane(waldsupport.com) 이슈 벌크 생성 도구 plane_sync + /plane 슬래시 명령
metadata: 
  node_type: memory
  type: project
  originSessionId: 79248c63-6e93-4ecd-90fb-c5695793ba9c
---

waldsupport.com = self-hosted **Plane** 인스턴스. 프로젝트 `SX(KIOSK/AGENT)`
(workspace `main`, project id `353cefb5-7bb2-426f-8ec5-88702fb0a7e3`). 작업(이슈)을
REST API 로 벌크 생성하는 도구를 2026-07-09 구축·검증 완료.

- **엔진**: `plane_sync/plane_sync.py` (stdlib only, `publish_outline.py` 관례 차용).
  서브커맨드 `check` / `create <tasks.json>` / `states` / `labels [--create ...]`.
  인증 `X-API-Key`, 토큰은 `.env` 의 `PLANE_API_TOKEN` (WALDSUPPORT_API_KEY 도 허용).
  이슈 엔드포인트 자동탐지 `/work-items/`(신) → `/issues/`(구). rate limit 60/min.
- **래퍼**: `/plane` 슬래시 명령 (`.claude/commands/plane.md`). 형식
  `제목 / 설명 / 우선순위 / 라벨 / 상태(선택)`. Claude 가 tasks.json 정규화 → dry-run → 생성.
- **필드**: name(필수)/description(평문→HTML)/priority(en+한글 매핑)/labels(이름→uuid)/
  state(이름→uuid). 상태·라벨 목록은 `check`/`states`/`labels` 로 조회(변동 가능).
- **멱등**: external_source=`claude-plane-sync` + external_id(제목 sha1), 사이드카
  `plane_sync/.plane_sync_state.json`. 재실행 skip, 강제는 `--force`.
- **gitignore**: `plane_sync/.plane_sync_state.json`, `plane_sync/tasks.json` 제외.
  커밋 대상은 plane_sync.py·README.md·tasks.example.json + plane.md + .gitignore.
- CLAUDE.md "API 우회 금지" 는 앱 내부 AppFit 백엔드 호출 규칙이라 이 개발 툴링과 무관.
