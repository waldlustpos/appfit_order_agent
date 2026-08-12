---
name: project_sentry_alert_routing
description: "Sentry 매장/브랜드별 에러 알림 라우팅 — sentry_alerts/ 스크립트로 코드화, MCP는 규칙 생성 불가, 라이브 적용은 토큰 대기"
metadata: 
  node_type: memory
  type: project
  originSessionId: 0bc1b321-0c0b-48ed-9e40-f73903b4b7c7
  modified: 2026-08-03T23:41:57.702Z
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

**PAIK 채널 추가 완료(2026-08-03, commit 87867d3)**: `branded[]`에 `{label:PAIK, match:sw, value:PAIK, channel:appfit-alert-paik, channel_id:C0BM48A7PUP}` 추가(브랜드 전체 prefix, TPCP00001과 달리 단일 매장 eq가 아님). `apply` 실행 → PAIK 규칙 생성(REST id 17375865) + catch-all 필터에 `store_id nsw PAIK` 자동 추가, 실 트래픽 검증 완료. `sentry_alerts.py list` 서브커맨드는 legacy `/rules/` GET 엔드포인트가 Sentry에서 폐기되어(`410 This API no longer exists`) 항상 실패함 — 규칙 확인은 `list` 대신 Sentry MCP `find_alert_rules`로 교차 확인할 것(`apply`의 POST/PUT 자체는 정상 동작, GET listing만 깨짐).

**함정: "Slack: Channel not found. Invalid ID provided." = 대부분 봇 초대 누락**. 비공개 채널 추가 시 이 400 에러가 나면 workspace 불일치나 OAuth 스코프(`groups:read`) 문제로 오인하기 쉬우나(기존 tpc/test 채널도 비공개인데 정상 동작 중이라 스코프 문제가 아님이 힌트), 실제 원인은 대개 **Sentry Slack 봇이 그 채널에 초대 안 됨**(또는 초대했다고 착각·재초대 시 실제로는 빠짐)이었음. Slack 채널 멤버 목록에서 봇 존재를 재확인하고 재초대하면 즉시 해결. 워크스페이스 재설치(OAuth reinstall)는 조직 전체 영향이 크므로 이 가능성부터 소거한 뒤 최후 수단으로.

**정정(2026-08-04)**: 위 "`list` 서브커맨드 GET 410 상시실패" 기록은 더 이상 사실이 아님 — TLJP 추가 작업 중 `list` 정상 동작 확인(4개 규칙 전부 조회됨). Sentry 측 엔드포인트가 복구됐거나 일시적 문제였던 것으로 보임. `list`부터 시도하고, 실패할 때만 MCP `find_alert_rules`로 우회할 것.

**TLJP 채널 추가 완료(2026-08-04)**: `branded[]`에 `{label:TLJP, match:sw, value:TLJP, channel:appfit-alert-tljp, channel_id:C0BMQCJMB62}` 추가(PAIK와 동일하게 브랜드 전체 prefix). `apply` 실행 → TLJP 규칙 생성(REST id 17378728) + catch-all 필터에 `store_id nsw TLJP` 자동 추가. `docs/SENTRY_ALERTS.md` 라우팅 표 갱신. 채널 ID는 사용자가 이미 만들어둔 채널에서 직접 제공(봇 초대 여부는 미확인 — 실 트래픽 검증 시 위 "Channel not found" 함정 참고). **미커밋**.

**버그 발견+수정(2026-08-04): environment 태그가 부팅 시 1회 스냅샷이라 로그인 후 서버 전환 반영 안 됨**. TLJP 검증 중 Slack 알림에 `environment: staging`이 찍힘(실제론 japanLive 운영 중) — 원인: `main.dart _buildMonitoringContext()`가 부팅 시 `AppFitConfig.environment`(그 기기에 저장된 마지막 값)로 `MonitoringService.instance.init()`을 1회만 호출하고, 로그인 화면 매장ID 프리픽스 자동전환(`login_screen.dart _applyEnvironment`)이나 설정 화면 수동전환(`settings_screen.dart _onEnvChanged`)이 `AppFitConfig.configure()`로 환경을 바꿔도 Sentry 쪽엔 반영 안 됨. appfit_core에 이미 있는 `MonitoringService.updateContext()`(주석: "로그인 후 매장정보 업데이트 시 호출")를 앱에서 **한 번도 호출한 적 없었음**(`updateStoreInfo`만 호출 — store_id/store_name만 갱신). 라우팅 자체는 무관(`routes.json` `"environment": null`=전체환경 발화라 영향 없음, 표시값만 부정확했음).

**수정 내용**: `main.dart`의 private `_buildMonitoringContext()`를 `lib/services/monitoring/monitoring_context_builder.dart`의 공개 `buildOrderAgentMonitoringContext()`로 추출(device_info_plus+package_info_plus 수집, `environment`는 호출 시점 `AppFitConfig.environment` 반영). `_applyEnvironment`(login_screen, 자동+수동 전환 공통 경로)와 `_onEnvChanged`(settings_screen)의 `AppFitConfig.configure()` 직후에 `if (AppEnv.hasSentryDsn) MonitoringService.instance.updateContext(await buildOrderAgentMonitoringContext())` 추가. **storeId/storeName은 항상 빈 문자열로 재구성됨 — 안전한 이유**: 두 호출부 모두 환경 전환 직후 로그아웃 수준 정리(토큰/세션 clear, `resetStoreScopedProviders`)가 뒤따르므로 이 시점엔 이미 매장 정보가 없거나 곧 없어짐(`_applyScope`가 `ctx.storeId` 빈 값이면 `scope.setUser(id:null)`을 호출하는데, 이게 실행돼도 잃을 store 정보가 없음). `flutter analyze` 확인(내 변경 파일들엔 신규 issue 없음, 기존 baseline 이슈만 잔존). **commit 912e87f 로 커밋됨**(pubspec 3.0.0+174 시점).

**MHST 채널 추가 + environment 스코프 기능 신설(2026-08-12, 라이브 적용 완료)**: `#appfit-alert-mhst`(C0BPSFVEM9S). **PAIK/TLJP 와 달리 전체 환경이 아니라 `"environment": "live"` 로 좁힘** — 실측상 MHST 는 사내 QA 브랜드라 30일 staging 404 / live 40 / japanLive 19 로 **staging 이 91%**(프로젝트 전체 staging 540건 중 404건이 MHST 하나. MHST00084 본사테스트, MHST01070~01073 온보딩). `sw MHST` 전체환경으로 열면 브랜드 채널이 사실상 staging 채널이 됨. **브랜드별 노이즈 프로파일을 먼저 재는 게 라우팅 설계의 선행 단계** — `search_events(query='store_id:<PREFIX>*', fields=['store_id','environment','count()'])`. (MCP 가 `OR` 를 넣은 쿼리는 `message:` 로 재작성해버려 결과가 무의미해짐 — 단일 조건으로 나눠 질의할 것.)

**비자명한 함정 — env 로 좁히면 나머지가 무음 폐기됨**: catch-all 은 branded 각 항목의 **`store_id` 부정 필터**로 구성된다(`nsw MHST`). branded 를 `environment=live` 로 좁혀도 catch-all 은 여전히 MHST **전체**를 제외하므로, MHST staging/japanLive 이벤트가 branded 에도 catch-all 에도 안 걸려 **어느 채널에도 안 감**(기존엔 test 채널로 갔음 → QA 가시성 상실). Sentry 규칙 필터는 `all`/`any` 뿐이라 `NOT(A AND B)` 를 한 규칙에 못 담는 게 근본 원인. 해결: `sentry_alerts.py` 에 **spillover 규칙 자동 생성** 추가 — `spillover_payload()` 가 `store_id sw MHST` + `environment ne live` 태그필터로 잔여 환경을 catchall 채널에 보낸다. 규칙 레벨 `environment` 는 부정을 표현할 수 없어 **environment 를 태그 필터로** 씀(`_applyScope` 가 `options.environment` 와 동명 태그를 둘 다 심어서 가능). `desired_payloads()` 는 env 가 있는 branded 마다 spillover 를 끼워넣고 `catchall_payload()` 는 무변경. 결과 규칙 4→6개(#17408554 MHST, #17408555 MHST(non-live)), 재실행 멱등 확인.

**Slack MCP 로는 alert 채널 검증 불가**: 알림 채널들이 전부 비공개라 `slack_search_channels`/`slack_read_channel` 이 `channel_not_found`(워크스페이스는 맞음 — 다른 appfit-* 채널은 조회됨). 채널명 검증 수단은 `apply` 뿐(이름이 틀리면 Sentry 가 거부하므로 **잘못 라우팅될 위험은 없음**). 단 **branded POST 만 실패하고 spillover+catch-all 이 성공하면 그 브랜드 운영 이벤트가 무음 폐기**되므로 apply 출력을 반드시 확인할 것.
