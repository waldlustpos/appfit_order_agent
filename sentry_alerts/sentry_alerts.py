#!/usr/bin/env python3
"""sentry_alerts — Sentry Issue Alert 라우팅 규칙을 코드로 관리한다.

매장/브랜드별 에러를 store_id 태그로 판별해 서로 다른 Slack 채널로 보내는
Issue Alert 규칙을 routes.json 대로 **멱등** 생성/갱신한다. Claude 는 routes.json
정규화만, 이 스크립트는 결정론적 REST 호출만 담당한다. stdlib(urllib) 만 사용.

## 라우팅 모델 (routes.json)
- branded[]  : 각 항목이 규칙 1개. `IF store_id <match> <value>` 를 만족하는
               이벤트를 전용 채널로 보낸다. (예: TPCP00001 -> appfit-alert-tpc)
- catchall    : branded 어디에도 안 걸린 나머지 전부를 받는 규칙 1개.
               branded 각 항목의 **부정 필터**(eq→ne, sw→nsw ...)를 `all` 로
               누적해 "branded 제외 전부" 를 표현한다. (예: -> appfit-alert-test)
- legacy      : 정리 대상 구(舊) 규칙 id (delete-legacy 로 제거).

각 규칙 이름은 `"[auto] <label> -> #<channel>"` 규약으로, 재실행 시 이름으로
기존 규칙을 찾아 PUT(갱신), 없으면 POST(생성) 한다. 사람이 만든 규칙(`[auto]`
접두사 없음)은 절대 건드리지 않는다.

## 설정 (repo 루트 .env — gitignore 대상)
  SENTRY_AUTH_TOKEN   Sentry Auth Token (필수). 스코프: alerts:write, project:read, org:read
토큰 발급: Sentry -> Settings -> Auth Tokens -> Create New Token (또는 Internal Integration).
org/project/region/slack_workspace 는 routes.json 에 있다.

## 사용법
  python3 sentry_alerts/sentry_alerts.py check              # 연결/토큰/프로젝트 확인
  python3 sentry_alerts/sentry_alerts.py list               # 현재 프로젝트 규칙 나열
  python3 sentry_alerts/sentry_alerts.py capture 3337240    # 기존 규칙 raw JSON 덤프(스키마 확인용)
  python3 sentry_alerts/sentry_alerts.py apply --dry-run    # 생성/갱신 payload 미리보기(쓰기 없음)
  python3 sentry_alerts/sentry_alerts.py apply              # routes.json 대로 규칙 적용
  python3 sentry_alerts/sentry_alerts.py delete-legacy --dry-run   # 삭제 예정 확인
  python3 sentry_alerts/sentry_alerts.py delete-legacy      # legacy 규칙 삭제
"""
import os
import sys
import json
import time
import argparse
import urllib.request
import urllib.error

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(HERE)
ROUTES_PATH = os.path.join(HERE, "routes.json")

# 스크립트가 관리하는 규칙 식별 마커. 사람이 만든 규칙과 구분한다.
NAME_PREFIX = "[auto]"

# WHEN(트리거) 모드. routes.json "when" 으로 선택:
#   "every" — conditions 비움. Sentry 사양상 트리거 미지정 = 모든 이벤트가 조건 충족
#             (매칭 이벤트마다 발화 = 모든 발생 빠짐없이). frequency 로 이슈별 재알림 간격만 제한.
#   "new"   — 새 이슈 생성 + 재발(resolved->unresolved)에만 발화(스팸 억제, 반복은 누락).
# actionMatch=any.
WHEN_NEW = [
    {"id": "sentry.rules.conditions.first_seen_event.FirstSeenEventCondition"},
    {"id": "sentry.rules.conditions.regression_event.RegressionEventCondition"},
]


def when_conditions(cfg):
    return [] if cfg.get("when", "every") == "every" else list(WHEN_NEW)

TAGGED_FILTER = "sentry.rules.filters.tagged_event.TaggedEventFilter"
SLACK_ACTION = "sentry.integrations.slack.notify_action.SlackNotifyServiceAction"

# TaggedEventFilter match 코드와 그 부정(catch-all 제외용).
#   eq=equals ne=not-equals sw=starts-with nsw=not-starts-with
#   ew=ends-with new=not-ends-with co=contains nc=not-contains
NEGATE_MATCH = {"eq": "ne", "sw": "nsw", "ew": "new", "co": "nc"}


def die(msg):
    print("[sentry_alerts] 오류:", msg, file=sys.stderr)
    sys.exit(1)


def info(msg):
    print("[sentry_alerts]", msg)


# ---------------------------------------------------------------- .env
def load_env():
    env = {}
    p = os.path.join(REPO_ROOT, ".env")
    if os.path.exists(p):
        for line in open(p, encoding="utf-8"):
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            env[k.strip()] = v.strip().strip('"').strip("'")
    return env


def get_token(env):
    tok = os.environ.get("SENTRY_AUTH_TOKEN") or env.get("SENTRY_AUTH_TOKEN")
    if not tok:
        die("SENTRY_AUTH_TOKEN 이 .env 또는 환경변수에 없습니다. "
            "Sentry -> Settings -> Auth Tokens 에서 alerts:write/project:read "
            "스코프로 발급해 .env 에 추가하세요.")
    return tok


# ---------------------------------------------------------------- routes.json
def load_routes():
    if not os.path.exists(ROUTES_PATH):
        die(f"routes.json 없음: {ROUTES_PATH}")
    try:
        cfg = json.load(open(ROUTES_PATH, encoding="utf-8"))
    except json.JSONDecodeError as e:
        die(f"routes.json 파싱 실패: {e}")
    for k in ("org", "project", "region", "slack_workspace"):
        if not cfg.get(k):
            die(f"routes.json 에 '{k}' 필수.")
    cfg.setdefault("frequency", 30)
    cfg.setdefault("branded", [])
    cfg.setdefault("legacy", {})
    if not cfg.get("catchall"):
        die("routes.json 에 'catchall' 필수.")
    for i, r in enumerate(cfg["branded"]):
        for k in ("label", "match", "value", "channel", "channel_id"):
            if not r.get(k):
                die(f"branded[{i}] 에 '{k}' 필수.")
        if r["match"] not in NEGATE_MATCH:
            die(f"branded[{i}] match '{r['match']}' 미지원 "
                f"(허용: {sorted(NEGATE_MATCH)}).")
    return cfg


# ---------------------------------------------------------------- HTTP
class Api:
    """Sentry REST API(v0) 클라이언트 — Bearer 토큰, stdlib urllib."""

    def __init__(self, region, token, org, project):
        self.api = f"{region.rstrip('/')}/api/0"
        self.token = token
        self.org = org
        self.project = project

    def _request(self, method, path, body=None, retries=3):
        url = f"{self.api}{path}"
        data = None
        headers = {"Authorization": f"Bearer {self.token}",
                   "Accept": "application/json"}
        if body is not None:
            data = json.dumps(body).encode("utf-8")
            headers["Content-Type"] = "application/json"
        req = urllib.request.Request(url, data=data, headers=headers,
                                     method=method)
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                raw = resp.read().decode("utf-8", "replace")
                parsed = json.loads(raw) if raw.strip() else None
                return resp.status, parsed, raw
        except urllib.error.HTTPError as e:
            raw = e.read().decode("utf-8", "replace")
            if e.code == 429 and retries > 0:
                wait = 5.0
                try:
                    wait = max(1.0, float(e.headers.get("Retry-After") or 5))
                except (TypeError, ValueError):
                    pass
                info(f"rate limit(429) — {wait:.0f}s 대기 후 재시도")
                time.sleep(min(wait, 65))
                return self._request(method, path, body, retries - 1)
            try:
                parsed = json.loads(raw) if raw.strip() else None
            except json.JSONDecodeError:
                parsed = None
            return e.code, parsed, raw
        except urllib.error.URLError as e:
            die(f"네트워크 오류: {e.reason} ({url})")

    def _proj(self):
        return f"/projects/{self.org}/{self.project}"

    def get_project(self):
        return self._request("GET", f"{self._proj()}/")

    def list_rules(self):
        rules, url = [], f"{self._proj()}/rules/?per_page=100"
        # rules 엔드포인트는 Link 헤더 페이지네이션이나, 규칙 수가 적어 1페이지로 충분.
        status, parsed, raw = self._request("GET", url)
        if status != 200:
            die(f"규칙 조회 실패(status {status}): {raw[:300]}")
        return parsed or []

    def create_rule(self, payload):
        return self._request("POST", f"{self._proj()}/rules/", payload)

    def update_rule(self, rule_id, payload):
        return self._request("PUT", f"{self._proj()}/rules/{rule_id}/", payload)

    def delete_issue_rule(self, rule_id):
        return self._request("DELETE", f"{self._proj()}/rules/{rule_id}/")

    def delete_metric_rule(self, rule_id):
        return self._request(
            "DELETE", f"/organizations/{self.org}/alert-rules/{rule_id}/")

    def poll_rule_task(self, task_uuid, tries=10):
        """Slack 채널 비동기 검증(202 응답) 시 rule-task 를 폴링해 완료를 기다린다."""
        for _ in range(tries):
            time.sleep(1.5)
            status, parsed, raw = self._request(
                "GET", f"{self._proj()}/rule-task/{task_uuid}/")
            if status != 200 or not isinstance(parsed, dict):
                continue
            st = parsed.get("status")
            if st == "success":
                return True, parsed.get("rule")
            if st == "failed":
                return False, parsed.get("error") or raw
        return False, "rule-task 폴링 타임아웃"


# ---------------------------------------------------------------- payload
def slack_action(cfg, route):
    # tags: Slack 메시지에 함께 표시할 태그 키(쉼표 구분). routes.json "slack_tags".
    # 예 "store_id, user.username" -> 매장코드 + 매장명이 메시지에 노출.
    return {
        "id": SLACK_ACTION,
        "workspace": str(cfg["slack_workspace"]),
        "channel": f"#{route['channel']}",
        "channel_id": route["channel_id"],
        "tags": cfg.get("slack_tags", ""),
    }


def branded_payload(cfg, route):
    """전용 채널 규칙: store_id <match> value 를 만족하면 해당 채널로."""
    return {
        "name": f"{NAME_PREFIX} {route['label']} -> #{route['channel']}",
        "actionMatch": "any",
        "filterMatch": "all",
        "frequency": int(cfg["frequency"]),
        "environment": None,
        "conditions": when_conditions(cfg),
        "filters": [{
            "id": TAGGED_FILTER, "key": "store_id",
            "match": route["match"], "value": route["value"],
        }],
        "actions": [slack_action(cfg, route)],
    }


def catchall_payload(cfg):
    """나머지 전부: branded 각 항목의 부정 필터를 all 로 누적해 제외."""
    ca = cfg["catchall"]
    filters = [{
        "id": TAGGED_FILTER, "key": "store_id",
        "match": NEGATE_MATCH[r["match"]], "value": r["value"],
    } for r in cfg["branded"]]
    label = ca.get("label", "catch-all")
    return {
        "name": f"{NAME_PREFIX} {label} -> #{ca['channel']}",
        "actionMatch": "any",
        "filterMatch": "all",   # 모든 부정 필터 동시 만족 = branded 어디에도 안 걸림
        "frequency": int(cfg.get("frequency", 30)),
        "environment": None,
        "conditions": when_conditions(cfg),
        "filters": filters,
        "actions": [slack_action(cfg, ca)],
    }


def desired_payloads(cfg):
    return [branded_payload(cfg, r) for r in cfg["branded"]] + \
        [catchall_payload(cfg)]


# ---------------------------------------------------------------- 연결
def connect(check=True):
    cfg = load_routes()
    api = Api(cfg["region"], get_token(load_env()), cfg["org"], cfg["project"])
    if check:
        status, proj, raw = api.get_project()
        if status in (401, 403):
            die("인증 실패(401/403). SENTRY_AUTH_TOKEN/스코프를 확인하세요.")
        if status == 404:
            die(f"프로젝트 없음(404): {cfg['org']}/{cfg['project']}")
        if status != 200:
            die(f"프로젝트 조회 실패(status {status}): {raw[:300]}")
        name = proj.get("name") if isinstance(proj, dict) else "?"
        info(f"연결 OK — 프로젝트 '{name}' ({cfg['org']}/{cfg['project']})")
    return api, cfg


# ---------------------------------------------------------------- 서브커맨드
def cmd_check(args):
    connect(check=True)
    info("검증 완료(check).")


def cmd_list(args):
    api, _ = connect(check=False)
    rules = api.list_rules()
    if not isinstance(rules, list):
        die(f"예상치 못한 응답: {str(rules)[:300]}")
    if not rules:
        info("규칙 없음.")
        return
    for r in rules:
        managed = " [auto]" if str(r.get("name", "")).startswith(NAME_PREFIX) \
            else ""
        env = r.get("environment") or "all-env"
        info(f"#{r.get('id')}  {r.get('name')}  ({env}){managed}")
    info(f"총 {len(rules)}개")


def cmd_capture(args):
    """기존 규칙의 raw JSON 을 그대로 덤프 — payload 스키마 정합화용."""
    api, _ = connect(check=False)
    rules = {str(r.get("id")): r for r in api.list_rules()}
    for rid in args.rule_ids:
        r = rules.get(str(rid))
        if not r:
            info(f"#{rid}: 프로젝트 rules 목록에 없음(메트릭 규칙이거나 다른 프로젝트).")
            continue
        print(f"\n===== rule #{rid} =====")
        print(json.dumps(r, ensure_ascii=False, indent=2))


def _index_by_name(rules):
    return {r.get("name"): r for r in rules if isinstance(r, dict)}


def _apply_one(api, payload, by_name, dry):
    name = payload["name"]
    existing = by_name.get(name)
    if dry:
        action = "PUT(갱신)" if existing else "POST(생성)"
        info(f"(dry-run) {action}: {name}")
        print("        " + json.dumps(payload, ensure_ascii=False))
        return True
    if existing:
        status, parsed, raw = api.update_rule(existing["id"], payload)
        verb = "갱신"
    else:
        status, parsed, raw = api.create_rule(payload)
        verb = "생성"
    # Slack 채널 비동기 검증: 202 + uuid 면 rule-task 폴링.
    if status == 202 and isinstance(parsed, dict) and parsed.get("uuid"):
        ok, res = api.poll_rule_task(parsed["uuid"])
        if not ok:
            info(f"FAILED({verb}, async): {name}\n        {str(res)[:300]}")
            return False
        info(f"{verb} OK(async): {name}")
        return True
    if status in (200, 201) and isinstance(parsed, dict) and parsed.get("id"):
        info(f"{verb} OK: {name} -> #{parsed['id']}")
        return True
    info(f"FAILED({verb}, status {status}): {name}\n        {raw[:400]}")
    return False


def cmd_apply(args):
    if args.dry_run:
        # DRY RUN 은 토큰/네트워크 없이 routes.json -> payload 만 검증한다.
        cfg = load_routes()
        payloads = desired_payloads(cfg)
        info(f"{len(payloads)}개 규칙 (branded {len(cfg['branded'])} "
             f"+ catch-all 1) — DRY RUN")
        for p in payloads:
            _apply_one(None, p, {}, True)
        return
    api, cfg = connect(check=True)
    by_name = _index_by_name(api.list_rules())
    payloads = desired_payloads(cfg)
    info(f"{len(payloads)}개 규칙 적용 "
         f"(branded {len(cfg['branded'])} + catch-all 1)")
    ok = sum(_apply_one(api, p, by_name, False) for p in payloads)
    info(f"완료 — 성공 {ok}/{len(payloads)}")
    if ok != len(payloads):
        sys.exit(1)


def cmd_delete_legacy(args):
    api, cfg = connect(check=not args.dry_run)
    legacy = cfg.get("legacy", {})
    issue_ids = [str(i) for i in legacy.get("issue", [])]
    metric_ids = [str(i) for i in legacy.get("metric", [])]
    if not issue_ids and not metric_ids:
        info("routes.json 에 legacy 규칙이 없습니다.")
        return
    for rid in issue_ids:
        if args.dry_run:
            info(f"(dry-run) DELETE issue rule #{rid}")
            continue
        status, _, raw = api.delete_issue_rule(rid)
        info(f"issue #{rid}: "
             + ("삭제됨" if status in (200, 202, 204) else f"실패({status}) {raw[:200]}"))
    for rid in metric_ids:
        if args.dry_run:
            info(f"(dry-run) DELETE metric rule #{rid}")
            continue
        status, _, raw = api.delete_metric_rule(rid)
        info(f"metric #{rid}: "
             + ("삭제됨" if status in (200, 202, 204) else f"실패({status}) {raw[:200]}"))


# ---------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser(
        description="Sentry Issue Alert 라우팅 규칙 관리 CLI (routes.json 기반)")
    sub = ap.add_subparsers(dest="cmd")

    sub.add_parser("check", help="연결/토큰/프로젝트 확인").set_defaults(func=cmd_check)
    sub.add_parser("list", help="현재 프로젝트 규칙 나열").set_defaults(func=cmd_list)

    pc = sub.add_parser("capture", help="기존 규칙 raw JSON 덤프(스키마 확인용)")
    pc.add_argument("rule_ids", nargs="+", metavar="RULE_ID")
    pc.set_defaults(func=cmd_capture)

    pa = sub.add_parser("apply", help="routes.json 대로 규칙 멱등 생성/갱신")
    pa.add_argument("--dry-run", action="store_true", help="payload 미리보기(쓰기 없음)")
    pa.set_defaults(func=cmd_apply)

    pd = sub.add_parser("delete-legacy", help="routes.json 의 legacy 규칙 삭제")
    pd.add_argument("--dry-run", action="store_true", help="삭제 예정만 표시")
    pd.set_defaults(func=cmd_delete_legacy)

    args = ap.parse_args()
    if not getattr(args, "func", None):
        ap.print_help()
        return
    args.func(args)


if __name__ == "__main__":
    main()
