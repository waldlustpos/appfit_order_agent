# sentry_alerts — 매장/브랜드별 에러 알림 라우팅 (코드화)

Sentry Issue Alert 규칙을 **`routes.json` 정본**으로 멱등 관리하는 재사용 스크립트.
매장·브랜드를 `store_id` 태그로 판별해 서로 다른 Slack 채널로 에러를 보낸다.
stdlib(`urllib`)만 사용 — 추가 의존성 없음. (anchor: `plane_sync/plane_sync.py`)

## 왜 스크립트인가

Sentry MCP 는 알림 규칙을 **읽기만** 가능(생성/수정 도구 없음)하고, 대시보드 수동
설정은 브랜드가 늘 때마다 반복이 어렵다. 규칙을 `routes.json` 으로 버전관리하고
API 로 재현 가능하게 만든다. `add-brand` 스킬이 이 스크립트를 호출한다.

## 라우팅 모델

- **branded[]** — 각 항목 = 규칙 1개. `IF store_id <match> <value>` 이면 전용 채널로.
  선택 필드 `environment`(`live`/`japanLive`/`staging`)로 그 서버 환경만 좁힐 수 있다.
- **catchall** — branded 어디에도 안 걸린 나머지 전부. 스크립트가 branded 각 항목의
  **부정 필터**(`eq→ne`, `sw→nsw`, `ew→new`, `co→nc`)를 `all` 로 누적해 자동 구성.
- **spillover**(자동) — `environment` 로 좁힌 branded 항목의 **나머지 환경**을 catchall
  채널로 보내는 파생 규칙. catchall 은 `store_id` 로 브랜드를 통째 제외하므로, 이게
  없으면 그 이벤트가 어느 규칙에도 안 걸려 **무음 폐기**된다. 규칙명 `<LABEL>(non-<env>)`.
- **legacy** — 정리 대상 구 규칙 id(`delete-legacy` 로 제거).

규칙 이름은 `"[auto] <label> -> #<channel>"` 규약. 재실행 시 이름으로 기존 규칙을
찾아 갱신(PUT)하거나 생성(POST)한다. **`[auto]` 접두사가 없는(사람이 만든) 규칙은
절대 건드리지 않는다.**

현재 정본(`routes.json`) 요약:

| 규칙 | 필터 | 환경 | 채널 |
|---|---|---|---|
| branded | `store_id == TPCP00001` | 전체 | appfit-alert-tpc (C0B02RCJSJ0) |
| branded | `store_id sw PAIK` | 전체 | appfit-alert-paik (C0BM48A7PUP) |
| branded | `store_id sw TLJP` | 전체 | appfit-alert-tljp (C0BMQCJMB62) |
| branded | `store_id sw MMTH` | **live** | appfit-alert-mmth (C0BTUPM420Y) |
| spillover(자동) | `store_id sw MMTH` + `environment ne live` | 전체 | appfit-alert-test (C0AV9RDTTT7) |
| catch-all | 위 branded 4개를 `store_id` 로 전부 제외 | 전체 | appfit-alert-test (C0AV9RDTTT7) |

> **매머드 프리픽스 2종**: `MMTH`=운영(live), `MHST`=스테이징(staging). 브랜드 채널로는
> **MMTH 만** 라우팅한다. `MHST` 는 규칙을 두지 않아 catch-all(appfit-alert-test)로
> 떨어지는데, 이게 원래 `environment: live` 로 좁혔던 의도("사내 QA 노이즈를 브랜드
> 채널에서 뺀다")를 그대로 실현한다 — 이제 MHST 가 곧 그 QA 프리픽스다.
> `appfit-alert-mmth`(C0BTUPM420Y)는 옛 `appfit-alert-mhst` 채널을 재사용하지 않고
> 2026-08-27 신규로 만든 전용 채널이다.

> WHEN(트리거)=`when: "every"`(빈 conditions = **모든 이벤트마다 발화**, Sentry 사양),
> 모든 환경, 액션 간격 5분.
> ⚠️ 한 이슈에 여러 매장 이벤트가 섞이면 라우팅은 **트리거된 이벤트의 store_id** 를 따른다.

### WHEN 모드 (`routes.json` 최상위 `"when"`)

| 값 | 동작 |
|---|---|
| `"every"`(기본) | 트리거 미지정 = 매칭 이벤트 **모두** 발화(모든 발생 빠짐없이). 서로 다른 이슈는 전부 알림, 같은 이슈 반복은 `frequency`(분) 간격으로만 재알림. |
| `"new"` | 새 이슈 생성 + 재발(resolved→unresolved)에만 발화. 스팸 억제되나 기존 이슈의 반복 에러는 누락. |

> `frequency`(분)는 **같은 이슈**의 재알림 최소 간격. 낮출수록 놓침이 줄지만 고빈도
> 에러 시 Slack 폭주 위험. `0`=무제한(매 이벤트), 기본 `5`.

### Slack 메시지에 매장코드·매장명 표시 (`slack_tags`)

`routes.json` 최상위 `"slack_tags"`(쉼표 구분 태그 키)를 Slack 액션의 tags 로 넣어
메시지에 함께 표시한다. 앱(appfit_core `MonitoringService`)이 이미 심는 값:

| 키 | 값 | 예 |
|---|---|---|
| `store_id` | 매장코드(태그) | `MHST00084` |
| `store_name` | 매장명(태그) | `익스프레스 본사 테스트` |
| `user.username` / `user.id` | 매장명 / 매장코드(user context) | 〃 |
| `environment` / `level` | 서버 / 심각도 | `staging` / `error` |

현재 정본 `"store_id, store_name, environment, level"` → 매장코드+매장명이 바로 노출.
**앱 변경 불필요** — `store_name` 태그는 appfit_core v1.0.16 `MonitoringService`
(`_applyScope` / `updateStoreInfo`)에서 이미 심는다. 태그가 없던 시절 이벤트는
`user.username` 으로만 보이므로, 과거 이벤트를 볼 땐 그쪽을 참고.

## 준비 (1회) — Sentry Auth Token

repo 루트 `.env`(gitignore 됨)에 토큰을 추가:

```
SENTRY_AUTH_TOKEN=<Sentry Auth Token>
```

발급: **Sentry → Settings → Developer Settings → Auth Tokens → Create New Token**
(또는 조직 Internal Integration). 필요한 스코프:

- `alerts:write` — 규칙 생성/수정/삭제
- `project:read`, `org:read` — 연결/목록 조회

> `org`/`project`/`region`/`slack_workspace`(Slack integration id) 는 `routes.json` 에 있다.

## 사용

```bash
# 조회/검증 (쓰기 없음)
python3 sentry_alerts/sentry_alerts.py check           # 연결/토큰/프로젝트 확인
python3 sentry_alerts/sentry_alerts.py list            # 현재 프로젝트 규칙 나열
python3 sentry_alerts/sentry_alerts.py capture 3337240 3713739   # 기존 규칙 raw JSON 덤프

# 적용
python3 sentry_alerts/sentry_alerts.py apply --dry-run  # payload 미리보기(토큰/네트워크 불필요)
python3 sentry_alerts/sentry_alerts.py apply            # routes.json 대로 규칙 생성/갱신

# 정리
python3 sentry_alerts/sentry_alerts.py delete-legacy --dry-run
python3 sentry_alerts/sentry_alerts.py delete-legacy    # legacy 규칙 삭제
```

### 최초 셋업 권장 순서

1. `.env` 에 `SENTRY_AUTH_TOKEN` 추가.
2. `capture 3337240 3713739` — 이미 동작하는 Slack 액션 payload 를 확인해
   `sentry_alerts.py` 상단 상수(WHEN/필터/액션 필드)가 실제와 맞는지 대조.
   (다르면 상수만 수정 후 재실행. 대개 표준 ID 라 그대로 맞는다.)
3. `apply --dry-run` 으로 payload 확인 → `apply` 로 `[auto]` 규칙 2개 생성.
4. `list` 로 확인 후 `delete-legacy` 로 중복·깨진 구 규칙 정리.
5. **실 트래픽으로만 검증**(소급 발화 없음): TPCP00001 새 에러 → tpc 채널,
   타 매장 새 에러 → test 채널 도착 확인.

## 브랜드 추가 시 (add-brand 연동)

`add-brand` 스킬이 "브랜드 전용 Slack 채널 ID" 입력을 받으면 이 스크립트를 호출한다.
수동으로 추가하려면 `routes.json` 의 `branded[]` 에 항목을 넣고 `apply`:

```jsonc
{ "label": "MATA", "match": "sw", "value": "MATA",   // 브랜드 전체(prefix)
  "environment": "live",                             // 선택 — 생략하면 전체 환경
  "channel": "appfit-alert-mata", "channel_id": "C0XXXXXXXXX" }
```

- 단일 매장이면 `"match": "eq"` + 정확한 store_id.
- 브랜드 전체면 `"match": "sw"` + 4자 prefix(TPCP/MHST/MATA/PAIK...).
- `environment` 를 주면 운영 서버 이벤트만 브랜드 채널로 가고, 나머지 환경은
  spillover 규칙이 catchall 채널로 보낸다. staging 노이즈가 큰 브랜드에 유용
  (MHST 실측: 30일 staging 404 / live 40).

`apply` 가 새 branded 규칙(+필요 시 spillover)을 만들고
**catch-all 의 제외 필터를 자동 갱신**한다.

## 주의

- `routes.json` 은 라우팅 정본이라 **커밋 대상**(시크릿 없음, 채널 id 는 공개값).
- `SENTRY_AUTH_TOKEN` 은 `.env` 로컬 전용 — 절대 커밋 금지.
- 검증은 Sentry MCP(`find_alert_rules`/`search_events`)로 교차 확인 가능.
