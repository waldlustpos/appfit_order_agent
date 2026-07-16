---
name: project_sentry_alert_routing
description: "Sentry 매장/브랜드별 에러 알림 라우팅 — sentry_alerts/ 스크립트로 코드화, MCP는 규칙 생성 불가, 라이브 적용은 토큰 대기"
metadata: 
  node_type: memory
  type: project
  originSessionId: 0bc1b321-0c0b-48ed-9e40-f73903b4b7c7
---

**목표**: TPCP00001 에러 → Slack `appfit-alert-tpc`(C0B02RCJSJ0), 그 외 전부 → `appfit-alert-test`(C0AV9RDTTT7). 브랜드 추가 시 반복 가능하게(add-brand 통합).

**핵심 제약(비자명)**: Sentry MCP는 알림 규칙 **읽기만**(`find_alert_rules`/`get_alert_rule`) 가능, **생성/수정 도구 없음**. 그래서 규칙을 REST API 스크립트로 코드화함. `get_alert_rule` 콘덴스드 출력은 IF 필터 내용을 안 보여줌(raw 필요 시 `capture` 서브커맨드).

**판별 키**: `store_id` 태그(= 서버 strId, 예 TPCP00001). 브랜드는 prefix(TPCP/MHST/MATA/PAIK). **환경(japanLive/live/staging)은 브랜드 판별자 아님** — TPCP·PAIK 둘 다 japanLive라 env-only 필터는 PAIK를 tpc로 오배송. staging 노이즈 큼(MHST00001 353건). store_id 실측: TPCP00001·TPCP00002·PAIK00001·MHST00001/84/101·MATA00001/2.

**구현물**(2026-07-16 완료, main 미커밋):
- `sentry_alerts/sentry_alerts.py`(stdlib urllib, plane_sync 패턴) — check/list/capture/apply/delete-legacy
- `sentry_alerts/routes.json`(정본, 커밋대상): branded[TPCP00001 eq→tpc] + catchall(ne→test) + legacy(issue 3337240/3713739, metric 10007820672 삭제대상). metric 10007820672는 query `store_id:ContainsPAIK00001`로 깨져 영구 미발화였음.
- catch-all은 branded 부정필터(eq→ne, sw→nsw...) all 누적으로 자동구성. WHEN=FirstSeen+Regression(any), 모든환경, freq 30m.
- `docs/SENTRY_ALERTS.md`, `.claude/commands/add-brand.md` STEP5(Sentry 라우팅) 신설+STEP6 재번호, `.env` SENTRY_AUTH_TOKEN(빈값).

**라이브 적용 완료(2026-07-16)**: SENTRY_AUTH_TOKEN 받아 apply+delete-legacy 실행. 현재 규칙 2개만: `[auto] TPCP00001 -> #appfit-alert-tpc`(store_id eq), `[auto] catch-all -> #appfit-alert-test`(store_id ne). **WHEN=every**(routes.json `"when":"every"` → conditions 비움 = 모든 이벤트 발화 "빠짐없이", Sentry 문서 보증: 트리거 미지정=모든 이벤트 충족), 모든환경, freq 5m(같은 이슈 재알림 간격만 제한, 0=무제한). `"when":"new"` 로 바꾸면 새이슈+재발만. **구 tpc 규칙(16968728)은 filters:[] + env=japanLive 뿐이라 PAIK/TPCP00002/MHST(japanLive) 전부 tpc로 오배송 중이었음** — 삭제로 해소. 구 test·깨진 metric 삭제 완료.

**함정: Sentry 규칙 ID가 이중 체계**. MCP `find_alert_rules`/monitors-URL(`/monitors/alerts/{id}`)이 쓰는 ID(예 3337240, 3713896)와 REST `/projects/.../rules/` API가 쓰는 ID(예 16968728, 17301523)가 **서로 다름**. 스크립트(REST)용 legacy 삭제 ID는 `list`/`capture`가 보여주는 REST ID를 써야 함(MCP ID로 DELETE하면 404). metric은 org `/alert-rules/{id}` 단일 체계.

**Slack 메시지 매장코드·매장명 표시(2026-07-16)**: routes.json `slack_tags: "store_id, store_name, environment, level"` → Slack 액션 tags 필드. **store_id**(매장코드)는 기존 태그라 즉시 표시. **매장명은 원래 user.username/store_info 컨텍스트뿐이라 Slack tags 블록에 안 떴음** → appfit_core `MonitoringService` 에 `scope.setTag('store_name', storeName)` 추가(_applyScope+updateStoreInfo)로 해결. **appfit_core v1.0.16 릴리즈**(commit 589f812, 함께 릴리즈: ApiHttpException.isTransientNetworkError + SentryAppFitLogger 가 순단성 HTTP ? 오류를 issue 대신 breadcrumb 로 — 별개 WIP 였음). 앱 pubspec ref v1.0.15→v1.0.16. **store_name 태그는 앱 재빌드·기기 재배포 후 신규 이벤트부터 노출**(런타임 태그). DID 앱은 ref v1.0.16 미반영(별도).

**검증 남음**: Issue Alert 소급 발화 없음 → TPCP00001 새 에러로 tpc 도착·test 미도착 실증. WHEN=FirstSeen+Regression이라 기존 이슈의 반복 이벤트엔 재알림 안 함(모든 발생 원하면 metric alert `store_id:TPCP00001 count>0`가 더 확실). org=waldlust, project=appfit-order-agent, slack integration id=344607. 관련 [[project_remote_log_collection]].
