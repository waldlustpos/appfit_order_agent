# Sentry 에러 알림 라우팅

매장·브랜드별 에러를 `store_id` 태그로 판별해 서로 다른 Slack 채널로 보내는
Sentry Issue Alert 라우팅. 규칙은 대시보드 수동이 아니라
**[sentry_alerts/](../sentry_alerts/) 스크립트 + `routes.json` 정본**으로 관리한다.

## 배경 (왜 이렇게)

- `store_id` 태그는 appfit_core `MonitoringService._applyScope` / `updateStoreInfo`
  가 로그인 후 `scope.setTag('store_id', ...)` 로 심는다. 값 = 서버 응답
  `StoreModel.storeId`(예: `TPCP00001`). **앱 코드는 이미 정상 — 변경 없음.**
- 브랜드는 `store_id` **prefix**(TPCP/MHST/MATA/PAIK)로 갈린다(BrandRegistry 모델).
  환경(japanLive/live/staging)은 브랜드 판별자가 **아니다**(TPCP·PAIK 둘 다 japanLive).
  → 라우팅 판별 키는 **store_id 태그**.
- Sentry MCP 는 규칙을 읽기만 가능하고, 대시보드 수동은 브랜드 확장 시 반복이
  어렵다. 그래서 규칙을 `routes.json` 으로 버전관리하고 REST API 로 재현한다.

## 현재 라우팅 (routes.json)

| 규칙 | 필터 | 채널 |
|---|---|---|
| `[auto] TPCP00001 -> #appfit-alert-tpc` | `store_id == TPCP00001` | appfit-alert-tpc (C0B02RCJSJ0) |
| `[auto] PAIK -> #appfit-alert-paik` | `store_id sw PAIK` | appfit-alert-paik (C0BM48A7PUP) |
| `[auto] catch-all -> #appfit-alert-test` | `store_id != TPCP00001` | appfit-alert-test (C0AV9RDTTT7) |

- WHEN(트리거): `when: "every"` — 빈 conditions = **모든 이벤트마다 발화**(Sentry 사양상
  트리거 미지정 = 모든 이벤트 충족). `actionMatch=any`. 모든 환경. 액션 간격 5분.
  → "모든 발생을 빠짐없이". `frequency`(분)는 같은 이슈 재알림 간격만 제어. 다른 이슈는
  전부 알림. (반대로 스팸을 줄이려면 `when: "new"` = 새 이슈+재발만.)
- catch-all 은 branded 각 항목의 **부정 필터**(`eq→ne`, `sw→nsw`...)를 `all` 로 누적해
  "branded 제외 전부"를 표현 — 스크립트가 자동 구성한다.
- Slack 메시지 표시 태그(`slack_tags`): 기본 `store_id, user.username, environment, level`
  → **매장코드(`store_id`=MHST00084) + 매장명(`user.username`=익스프레스 본사 테스트)**
  이 메시지에 바로 노출. 앱은 이미 이 값들을 심으므로 **앱 변경 불필요**.

## 운영 방법

`SENTRY_AUTH_TOKEN`(스코프 `alerts:write`, `project:read`) 을 `.env` 에 넣고:

```bash
python3 sentry_alerts/sentry_alerts.py check         # 연결 확인
python3 sentry_alerts/sentry_alerts.py apply --dry-run # payload 미리보기(토큰 불필요)
python3 sentry_alerts/sentry_alerts.py apply         # routes.json 대로 규칙 생성/갱신
python3 sentry_alerts/sentry_alerts.py list          # 결과 확인
python3 sentry_alerts/sentry_alerts.py delete-legacy # 구 규칙 정리
```

토큰 발급·서브커맨드·필드 스키마 상세: [sentry_alerts/README.md](../sentry_alerts/README.md).

## 브랜드 추가 시

`add-brand` 스킬 STEP 5(선택)가 "브랜드 전용 채널 ID" 입력을 받으면
`routes.json` 의 `branded[]` 에 `{match:"sw", value:"<PREFIX>", channel_id}` 를 추가하고
`apply` 를 실행한다. 새 branded 규칙이 생기고 catch-all 제외 필터가 자동 갱신된다.

## 주의

- **소급 발화 없음**: Issue Alert 은 규칙 생성 이후 새로 유입되는 이벤트에만 발화.
  검증은 반드시 **새 에러를 유발**해서 한다(과거 이벤트로는 안 울림).
- `when: "every"` 는 이벤트마다 평가하지만, 한 이슈에 여러 매장 이벤트가 섞이면
  라우팅은 **그 이벤트의 store_id** 를 따른다(이슈 단위가 아님). `frequency`(분) 동안
  같은 이슈의 반복은 재알림되지 않으니, 완전 무제한이 필요하면 `frequency: 0`.
- 로그인 전(무 `store_id`) 이벤트는 catch-all 의 `ne` 필터에 걸려 test 채널로 간다
  (원하는 catch-all 동작). 만약 안 잡히면 catch-all 에 `store_id is-not-set(ns)` OR
  필터를 보강한다.
- 검증은 Sentry MCP `find_alert_rules` / `search_events(query='store_id:...')` 로 교차 확인.
