---
name: project_appfit_fleet_backend
description: appfit-fleet 백엔드(Fleet 관제 서버) 저장소 구조·스택·배포 상태
metadata: 
  node_type: memory
  type: project
  originSessionId: d1693d6b-f3bc-4c29-94f3-2087243849f8
  modified: 2026-08-20T01:33:42.545Z
---

Fleet(기기 관제) 기능의 백엔드는 별도 레포 `/Users/kimsungchun/Documents/GitHub/appfit-fleet` — Cloudflare Workers(raw fetch 핸들러, 프레임워크 없음) + D1(SQLite). `wrangler` CLI로 개발/배포. 2026-07-30 최초 커밋, 2026-08-03 최근 커밋, **이미 실운영 배포됨**(README/DEPLOYMENT.local.md에 배포 이력 기록). 앱 쪽 스펙은 `docs/DEVICE_MONITORING.md`([[project_device_monitoring_design]]), 앱 배선은 [[project_fleet_store_allowlist_gate]] 참고.

**구조**: `src/index.ts`(라우터+register/heartbeat/dashboard API 핸들러), `src/types.ts`(RegisterBody/HeartbeatBody/Ack 등 와이어 타입), `src/auth.ts`(기기 Bearer 인증 + 대시보드 세션 쿠키 분리), `src/dashboard.ts`(단일 페이지 대시보드), `schema.sql`(devices/commands 2테이블, PK `(app_type, device_id)` — Windows POS 한 대에서 order_agent/KIOSK가 MachineGuid 공유하므로 app_type을 키에 포함), `test/smoke.sh`(로컬 왕복 스모크 33 checks).

**함정**: 레포 루트 안에 `appfit-fleet/`라는 동일 내용의 하위 디렉터리가 통째로 중첩되어 있고 그 안에 별도 `.git`이 있음(untracked, `git status`에 잡힘) — 실수로 저장소 안에 한 번 더 clone한 상태로 보임. 작업 대상은 항상 레포 루트, 중첩 디렉터리는 사용자 확인 없이 건드리지 말 것.

**설계 원칙**: liveness는 서버 수신 시각(`last_seen_at`)만으로 판정(online 3분/stale 15분/offline 그 이상), 명령은 heartbeat 응답에 piggyback(WebSocket이 수신 전용이라 push 채널 신설 회피), `schema.sql`은 `CREATE TABLE IF NOT EXISTS`라 이미 배포된 운영 DB에는 재실행해도 컬럼이 안 늘어남 — 스키마 변경은 별도 `ALTER TABLE` + 로컬 검증 후 원격 적용 필요.

**Why**: appfit_order_agent 세션에서 처음 발견/조사(2026-08-20) — 이전까지 이 레포의 존재나 구조가 메모리에 없었음.
**How to apply**: Fleet 백엔드 관련 작업 전엔 항상 이 구조를 먼저 참고. 진행 중인 구체적 기능 설계는 [[project_fleet_resource_monitoring_plan]] 참고.
