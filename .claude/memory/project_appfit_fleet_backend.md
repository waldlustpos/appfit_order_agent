---
name: project_appfit_fleet_backend
description: appfit-fleet 백엔드(Fleet 관제 서버) 저장소 구조·스택·배포 상태
metadata: 
  node_type: memory
  type: project
  originSessionId: d1693d6b-f3bc-4c29-94f3-2087243849f8
  modified: 2026-09-01T00:27:57.718Z
---

Fleet(기기 관제) 기능의 백엔드는 별도 레포 `/Users/kimsungchun/Documents/GitHub/appfit-fleet` — Cloudflare Workers(raw fetch 핸들러, 프레임워크 없음) + D1(SQLite). `wrangler` CLI로 개발/배포. 2026-07-30 최초 커밋, 2026-08-03 최근 커밋, **이미 실운영 배포됨**(README/DEPLOYMENT.local.md에 배포 이력 기록). 앱 쪽 스펙은 `docs/DEVICE_MONITORING.md`([[project_device_monitoring_design]]), 앱 배선은 [[project_fleet_store_allowlist_gate]] 참고.

**구조**: `src/index.ts`(라우터+register/heartbeat/dashboard API 핸들러), `src/types.ts`(RegisterBody/HeartbeatBody/Ack 등 와이어 타입), `src/auth.ts`(기기 Bearer 인증 + 대시보드 세션 쿠키 분리), `src/dashboard.ts`(단일 페이지 대시보드), `schema.sql`(devices/commands 2테이블, PK `(app_type, device_id)` — Windows POS 한 대에서 order_agent/KIOSK가 MachineGuid 공유하므로 app_type을 키에 포함), `test/smoke.sh`(로컬 왕복 스모크 33 checks).

**함정**: 레포 루트 안에 `appfit-fleet/`라는 동일 내용의 하위 디렉터리가 통째로 중첩되어 있고 그 안에 별도 `.git`이 있음(untracked, `git status`에 잡힘) — 실수로 저장소 안에 한 번 더 clone한 상태로 보임. 작업 대상은 항상 레포 루트, 중첩 디렉터리는 사용자 확인 없이 건드리지 말 것.

**설계 원칙**: liveness는 서버 수신 시각(`last_seen_at`)만으로 판정(online 3분/stale 15분/offline 그 이상), 명령은 heartbeat 응답에 piggyback(WebSocket이 수신 전용이라 push 채널 신설 회피), `schema.sql`은 `CREATE TABLE IF NOT EXISTS`라 이미 배포된 운영 DB에는 재실행해도 컬럼이 안 늘어남 — 스키마 변경은 별도 `ALTER TABLE` + 로컬 검증 후 원격 적용 필요.

**서버 배포 버전 표기 + OS 필터 구현 완료(2026-08-24, 미배포)**: `GET /api/deployed-versions` 신설 — DB/시크릿 전혀 안 늘리고 Worker가 OTA 정적 호스트(Lightsail)를 **pull**로 직접 읽음(RELEASE_ARTIFACTS 5개: android/windows × common/mammoth + android_sunmi_mammoth, `src/types.ts`). 배포 스크립트 push 방식은 기각 — "배포는 됐는데 보고 실패로 표기만 옛날 값"이라는 새 실패모드를 만들어서. Sunmi만 조회 지점이 없어 `/store-upload` 스킬(appfit_order_agent)이 `fleet_sunmi_mammoth_version.json`을 같은 호스트에 별도 게시(채널 아님, `fleet_stores.json`과 같은 수동 자산 취급). 실측 확인: https도 200, Windows 2채널 응답에 BOM 있음(`deploy_windows.ps1`의 `Out-File -Encoding utf8` 때문, JSON.parse 전 스트립 필수), `Last-Modified` 헤더로 배포시각 확보. 기기 목록 OS 필터(`#os` select)는 완전히 클라이언트사이드, 기존 `platform` 필드(`android`/`windows`) 그대로 재사용. `npm run typecheck` + `wrangler dev` 로컬 실측(실제 프로덕션 4채널 fetch 성공) + smoke.sh 40/40 통과. **`wrangler deploy` 미실행 — 사용자 수동 배포 필요**(시크릿 불필요, 스키마 변경 없음).

**다운로드 페이지 개편(2026-09-01, 미배포)**: `/download*` 는 이제 **공개가 아니라 대시보드와 같은 세션 쿠키** 뒤에 있다(새 시크릿 없음, 페이지는 LOGIN_HTML / 데이터·파일은 401). `GET /api/deployed-versions` 는 **제거** — 대시보드 상단의 "서버 배포 버전" 바를 없애 호출부가 사라졌고 `/download/versions` 와 인증 경계까지 같아졌다. 그 바에 붙어 있던 링크는 헤더의 `a.hbtn` 버튼으로 이동. Windows 카드의 `fileUrl` 은 OTA ZIP → **설치본 exe**(`appfit_order_agent[_mammoth]_windows_setup.exe`)로 교체 — 그 파일은 `deploy_windows.ps1` 이 `dist\` 의 Inno 산출물을 고정명으로 함께 올려야 존재하므로(`1-0b` 가드), **설치본 시딩 → Worker 배포** 순서를 지키지 않으면 다운로드가 502 다. typecheck + smoke 60/60 통과, `wrangler deploy` 미실행.

**Why**: appfit_order_agent 세션에서 처음 발견/조사(2026-08-20) — 이전까지 이 레포의 존재나 구조가 메모리에 없었음.
**How to apply**: Fleet 백엔드 관련 작업 전엔 항상 이 구조를 먼저 참고. 진행 중인 구체적 기능 설계는 [[project_fleet_resource_monitoring_plan]] 참고. `FleetConfig.enabled`는 [[project_device_monitoring_design]]의 기록과 달리 현재 `true`(커밋 9483998, Windows 한정 활성화) — 그 메모리의 "구현 미착수"는 낡은 서술이니 최신 상태는 코드로 재확인할 것.
