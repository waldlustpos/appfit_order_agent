#!/usr/bin/env python3
"""Plane(waldsupport.com) 프로젝트에 작업(이슈)을 벌크 생성한다.

사용자가 직접 제공한 작업 목록(JSON) 을 Plane REST API 로 생성한다.
Claude 는 자연어 목록 -> tasks.json 정규화만, 이 스크립트는 결정론적 POST 만 담당한다.

설정은 repo 루트 .env 에서 읽는다 (모두 gitignore 대상):
  PLANE_API_TOKEN       Plane Personal Access Token (필수, WALDSUPPORT_API_KEY 도 허용)
  PLANE_BASE_URL        기본 https://waldsupport.com
  PLANE_WORKSPACE       기본 main
  PLANE_PROJECT_ID      기본 353cefb5-7bb2-426f-8ec5-88702fb0a7e3
토큰 발급: Plane -> Profile Settings -> Personal Access Tokens -> Add.

입력(tasks.json): JSON 배열. 각 원소:
  {
    "name":            "제목 (필수)",
    "description":      "평문 설명 (선택)",       # 또는 아래 html
    "description_html": "<p>HTML 설명</p> (선택)",  # 있으면 description 보다 우선
    "priority":         "urgent|high|medium|low|none (선택)",
    "labels":           ["라벨이름1", "라벨이름2"],   # 이름 -> uuid 자동 해석
    "state":            "state-uuid (선택)",
    "external_id":      "안정적 고유키 (선택, 없으면 name 해시)"
  }

사용법 (서브커맨드):
  python3 plane_sync/plane_sync.py check                   # 연결/토큰/엔드포인트/상태/라벨
  python3 plane_sync/plane_sync.py states                  # 상태(state) 목록 + uuid
  python3 plane_sync/plane_sync.py labels                  # 라벨 목록 + uuid
  python3 plane_sync/plane_sync.py labels --create foo bar # 라벨 생성
  python3 plane_sync/plane_sync.py create tasks.json --dry-run     # 생성 미리보기
  python3 plane_sync/plane_sync.py create tasks.json              # 실제 생성
  python3 plane_sync/plane_sync.py create tasks.json --create-labels  # 없는 라벨 자동 생성
  python3 plane_sync/plane_sync.py create tasks.json --force      # 상태파일 무시 재생성
  (호환: `plane_sync.py tasks.json` = create, `plane_sync.py --check` = check)

멱등성: external_source="claude-plane-sync" + external_id 로 식별. 생성 결과를
plane_sync/.plane_sync_state.json (external_id -> work-item id) 에 기록하고,
재실행 시 이미 있는 external_id 는 skip 한다(--force 로 무시). Plane 서버도
동일 external_id+source 중복을 거부하므로, 상태파일이 없어도 중복 생성은 방지된다.
"""
import os
import re
import sys
import json
import time
import html as htmllib
import hashlib
import argparse
import urllib.parse
import urllib.request
import urllib.error

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(HERE)
STATE_PATH = os.path.join(HERE, ".plane_sync_state.json")
EXTERNAL_SOURCE = "claude-plane-sync"
VALID_PRIORITY = {"urgent", "high", "medium", "low", "none"}
PRIORITY_ALIASES = {  # 한국어/약어 -> Plane enum
    "긴급": "urgent", "높음": "high", "상": "high", "중": "medium",
    "보통": "medium", "낮음": "low", "하": "low", "없음": "none",
}
WRITE_PACING_SEC = 1.1  # rate limit 60/min -> write 간 ~1.1s
UUID_RE = re.compile(
    r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-"
    r"[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")


def die(msg):
    print("[plane_sync] 오류:", msg, file=sys.stderr)
    sys.exit(1)


def info(msg):
    print("[plane_sync]", msg)


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


# ---------------------------------------------------------------- HTTP
class Api:
    """Plane REST v1 클라이언트 (stdlib urllib 만 사용)."""

    def __init__(self, base, key, workspace, project):
        self.root = f"{base.rstrip('/')}/api/v1/workspaces/{workspace}/projects/{project}"
        self.key = key
        self._issue_path = None  # 'work-items' or 'issues' (자동탐지 캐시)

    def _request(self, method, url, body=None, retries=3):
        data = None
        headers = {"X-API-Key": self.key, "Accept": "application/json"}
        if body is not None:
            data = json.dumps(body).encode("utf-8")
            headers["Content-Type"] = "application/json"
        req = urllib.request.Request(url, data=data, headers=headers, method=method)
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                raw = resp.read().decode("utf-8", "replace")
                parsed = json.loads(raw) if raw.strip() else None
                return resp.status, parsed, raw
        except urllib.error.HTTPError as e:
            raw = e.read().decode("utf-8", "replace")
            # rate limit -> 대기 후 재시도
            if e.code == 429 and retries > 0:
                reset = e.headers.get("Retry-After") or e.headers.get("X-RateLimit-Reset")
                wait = 5.0
                try:
                    wait = max(1.0, float(reset))
                except (TypeError, ValueError):
                    pass
                info(f"rate limit(429) — {wait:.0f}s 대기 후 재시도")
                time.sleep(min(wait, 65))
                return self._request(method, url, body, retries - 1)
            try:
                parsed = json.loads(raw) if raw.strip() else None
            except json.JSONDecodeError:
                parsed = None
            return e.code, parsed, raw
        except urllib.error.URLError as e:
            die(f"네트워크 오류: {e.reason} ({url})")

    # -- 엔드포인트 자동탐지: /work-items/ (신) 없으면 /issues/ (구)
    def issue_path(self):
        if self._issue_path:
            return self._issue_path
        for candidate in ("work-items", "issues"):
            status, _, _ = self._request(
                "GET", f"{self.root}/{candidate}/?per_page=1")
            if status == 200:
                self._issue_path = candidate
                return candidate
            if status in (401, 403):
                die("인증 실패(401/403). WALDSUPPORT_API_KEY 를 확인하세요.")
        die("이슈 엔드포인트를 찾지 못했습니다(work-items/issues 모두 non-200). "
            "프로젝트 ID/워크스페이스/토큰 권한을 확인하세요.")

    def get_project(self):
        return self._request("GET", f"{self.root}/")

    def list_labels(self):
        labels = {}
        url = f"{self.root}/labels/?per_page=100"
        while url:
            status, parsed, raw = self._request("GET", url)
            if status != 200:
                die(f"라벨 조회 실패(status {status}): {raw[:300]}")
            items = parsed.get("results", parsed) if isinstance(parsed, dict) else parsed
            for lb in (items or []):
                labels[lb["name"].strip().lower()] = lb["id"]
            url = parsed.get("next_page_results") and parsed.get("next") \
                if isinstance(parsed, dict) else None
        return labels

    def create_label(self, name):
        status, parsed, raw = self._request(
            "POST", f"{self.root}/labels/", {"name": name})
        if status in (200, 201) and parsed:
            return parsed["id"]
        die(f"라벨 '{name}' 생성 실패(status {status}): {raw[:300]}")

    def list_states(self):
        """상태 이름(소문자) -> id 매핑과 기본 상태 id 를 반환."""
        states, default_id = {}, None
        status, parsed, raw = self._request(
            "GET", f"{self.root}/states/?per_page=100")
        if status != 200:
            die(f"상태 조회 실패(status {status}): {raw[:300]}")
        items = parsed.get("results", parsed) if isinstance(parsed, dict) else parsed
        for st in (items or []):
            states[st["name"].strip().lower()] = st["id"]
            if st.get("default"):
                default_id = st["id"]
        return states, default_id

    def create_issue(self, payload):
        path = self.issue_path()
        return self._request("POST", f"{self.root}/{path}/", payload)


# ---------------------------------------------------------------- 상태파일
def load_state():
    if os.path.exists(STATE_PATH):
        try:
            return json.load(open(STATE_PATH, encoding="utf-8"))
        except (json.JSONDecodeError, OSError):
            return {}
    return {}


def save_state(state):
    with open(STATE_PATH, "w", encoding="utf-8") as f:
        json.dump(state, f, ensure_ascii=False, indent=2, sort_keys=True)


# ---------------------------------------------------------------- 변환 유틸
def text_to_html(text):
    """평문 -> Plane description_html. 빈 줄로 문단, 단일 줄바꿈은 <br>."""
    text = (text or "").strip()
    if not text:
        return ""
    paras = re.split(r"\n\s*\n", text)
    out = []
    for p in paras:
        esc = htmllib.escape(p.strip()).replace("\n", "<br>")
        out.append(f"<p>{esc}</p>")
    return "".join(out)


def external_id_for(task):
    ext = task.get("external_id")
    if ext:
        return str(ext).strip()
    return "cps-" + hashlib.sha1(task["name"].encode("utf-8")).hexdigest()[:16]


def build_payload(task, label_ids, state_id=None):
    payload = {
        "name": task["name"].strip(),
        "external_source": EXTERNAL_SOURCE,
        "external_id": external_id_for(task),
    }
    if task.get("description_html"):
        payload["description_html"] = task["description_html"]
    elif task.get("description"):
        payload["description_html"] = text_to_html(task["description"])
    prio = (task.get("priority") or "").strip().lower()
    prio = PRIORITY_ALIASES.get(prio, prio)
    if prio:
        if prio in VALID_PRIORITY:
            payload["priority"] = prio
        else:
            info(f"  경고: priority '{prio}' 무효 — 무시 (허용: {sorted(VALID_PRIORITY)})")
    if label_ids:
        payload["labels"] = label_ids
    if state_id:
        payload["state"] = state_id
    return payload


# ---------------------------------------------------------------- 입력 검증
def load_tasks(path):
    if not os.path.exists(path):
        die(f"입력 파일 없음: {path}")
    try:
        data = json.load(open(path, encoding="utf-8"))
    except json.JSONDecodeError as e:
        die(f"JSON 파싱 실패({path}): {e}")
    if not isinstance(data, list):
        die("입력은 JSON 배열이어야 합니다 (task 객체들의 리스트).")
    for i, t in enumerate(data):
        if not isinstance(t, dict) or not str(t.get("name", "")).strip():
            die(f"task[{i}] 에 'name' 이 없습니다: {t!r}")
    return data


def is_duplicate_error(status, raw):
    if status not in (400, 409):
        return False
    low = (raw or "").lower()
    return "external_id" in low or "already exist" in low or "duplicate" in low


# ---------------------------------------------------------------- 연결/설정
def resolve_config(args, env):
    def cfg(*names, default=None):
        for n in names:
            v = os.environ.get(n) or env.get(n)
            if v:
                return v
        return default
    key = cfg("PLANE_API_TOKEN", "WALDSUPPORT_API_KEY")
    if not key:
        die("PLANE_API_TOKEN (또는 WALDSUPPORT_API_KEY) 가 .env 또는 환경변수에 "
            "없습니다. Plane Personal Access Token 을 .env 에 추가하세요.")
    base = (getattr(args, "base", None)
            or cfg("PLANE_BASE_URL", default="https://waldsupport.com"))
    workspace = (getattr(args, "workspace", None)
                 or cfg("PLANE_WORKSPACE", default="main"))
    project = (getattr(args, "project", None)
               or cfg("PLANE_PROJECT_ID",
                      default="353cefb5-7bb2-426f-8ec5-88702fb0a7e3"))
    return key, base, workspace, project


def connect(args):
    """설정 로드 + 연결/토큰 검증 후 Api 반환."""
    key, base, workspace, project = resolve_config(args, load_env())
    api = Api(base, key, workspace, project)
    status, proj, raw = api.get_project()
    if status in (401, 403):
        die("인증 실패(401/403). PLANE_API_TOKEN 을 확인하세요.")
    if status == 404:
        die(f"프로젝트를 찾을 수 없음(404). workspace='{workspace}' "
            f"project='{project}' 확인. 응답: {raw[:200]}")
    if status != 200:
        die(f"프로젝트 조회 실패(status {status}): {raw[:300]}")
    proj_name = proj.get("name") if isinstance(proj, dict) else "?"
    info(f"연결 OK — 프로젝트 '{proj_name}' / workspace '{workspace}'")
    return api


# ---------------------------------------------------------------- 서브커맨드
def cmd_check(args):
    api = connect(args)
    path = api.issue_path()
    st_map, _ = api.list_states()
    lb_map = api.list_labels()
    info(f"이슈 엔드포인트: /{path}/")
    info("상태(state): " + ", ".join(sorted(st_map)))
    info(f"라벨 {len(lb_map)}개: " + (", ".join(sorted(lb_map)) or "(없음)"))
    info("검증 완료(check).")


def cmd_states(args):
    api = connect(args)
    st_map, default_id = api.list_states()
    for name in sorted(st_map):
        mark = "  (default)" if st_map[name] == default_id else ""
        print(f"  {name:<14} {st_map[name]}{mark}")


def cmd_labels(args):
    api = connect(args)
    existing = api.list_labels()
    if args.create:
        for name in args.create:
            if name.strip().lower() in existing:
                info(f"이미 존재: {name}")
            else:
                lid = api.create_label(name)
                info(f"라벨 생성: {name} -> {lid}")
    else:
        for name in sorted(existing):
            print(f"  {name:<20} {existing[name]}")
        info(f"총 {len(existing)}개")


def cmd_create(args):
    api = connect(args)
    api.issue_path()  # 엔드포인트 확정(검증 겸)
    tasks = load_tasks(args.tasks)
    info(f"{len(tasks)}개 task 로드: {args.tasks}")

    # --- 라벨 이름 -> uuid 해석 ---
    wanted = {str(lb).strip() for t in tasks for lb in (t.get("labels") or [])}
    label_map = {}
    if wanted:
        label_map = api.list_labels()
        missing = [w for w in wanted if w.lower() not in label_map]
        if missing:
            if args.create_labels and not args.dry_run:
                for name in missing:
                    lid = api.create_label(name)
                    label_map[name.lower()] = lid
                    info(f"라벨 생성: '{name}'")
            else:
                info(f"경고: 미존재 라벨 {missing} — "
                     + ("(--dry-run 이라 생성 안 함)" if args.dry_run
                        else "해당 라벨은 스킵(--create-labels 로 생성 가능)"))

    # --- state 이름 -> uuid 해석 (이미 uuid 면 그대로 통과) ---
    wanted_states = {str(t["state"]).strip() for t in tasks if t.get("state")}
    state_map = {}
    if any(not UUID_RE.match(s) for s in wanted_states):
        state_map, _ = api.list_states()
        unknown = [s for s in wanted_states
                   if not UUID_RE.match(s) and s.lower() not in state_map]
        if unknown:
            info(f"경고: 미존재 상태 {unknown} — 기본 상태로 생성 "
                 f"(허용: {sorted(state_map)})")

    seen = load_state()
    created, skipped, failed = 0, 0, 0
    for i, task in enumerate(tasks, 1):
        ext = external_id_for(task)
        name = task["name"].strip()
        if not args.force and ext in seen:
            info(f"[{i}/{len(tasks)}] skip(이미 생성됨): {name} "
                 f"-> {seen[ext].get('id')}")
            skipped += 1
            continue

        label_ids = []
        for lb in (task.get("labels") or []):
            lid = label_map.get(str(lb).strip().lower())
            if lid:
                label_ids.append(lid)

        state_id = None
        rs = str(task.get("state") or "").strip()
        if rs:
            state_id = rs if UUID_RE.match(rs) else state_map.get(rs.lower())
        payload = build_payload(task, label_ids, state_id)

        if args.dry_run:
            info(f"[{i}/{len(tasks)}] (dry-run) 생성 예정: {name}")
            print("        " + json.dumps(payload, ensure_ascii=False))
            continue

        status, parsed, raw = api.create_issue(payload)
        if status in (200, 201) and isinstance(parsed, dict) and parsed.get("id"):
            seen[ext] = {"id": parsed["id"], "name": name}
            save_state(seen)
            info(f"[{i}/{len(tasks)}] created: {name} -> {parsed['id']}")
            created += 1
        elif is_duplicate_error(status, raw):
            info(f"[{i}/{len(tasks)}] skip(서버에 이미 존재): {name}")
            skipped += 1
        else:
            info(f"[{i}/{len(tasks)}] FAILED(status {status}): {name}\n        {raw[:300]}")
            failed += 1
        time.sleep(WRITE_PACING_SEC)

    info(f"완료 — created={created} skipped={skipped} failed={failed}")
    if failed:
        sys.exit(1)


# ---------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser(
        description="Plane(waldsupport.com) 이슈/작업 관리 CLI")
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--base", help="PLANE_BASE_URL 오버라이드")
    common.add_argument("--workspace", help="워크스페이스 slug 오버라이드")
    common.add_argument("--project", help="프로젝트 ID 오버라이드")
    sub = ap.add_subparsers(dest="cmd")

    pc = sub.add_parser("check", parents=[common],
                        help="연결/토큰/엔드포인트/상태/라벨 확인")
    pc.set_defaults(func=cmd_check)

    pcr = sub.add_parser("create", parents=[common],
                         help="tasks.json 으로 이슈 벌크 생성")
    pcr.add_argument("tasks", help="tasks.json 경로")
    pcr.add_argument("--dry-run", action="store_true", help="생성 미리보기")
    pcr.add_argument("--force", action="store_true",
                     help="상태파일 무시하고 재생성")
    pcr.add_argument("--create-labels", action="store_true",
                     help="없는 라벨을 자동 생성")
    pcr.set_defaults(func=cmd_create)

    ps = sub.add_parser("states", parents=[common], help="상태(state) 목록")
    ps.set_defaults(func=cmd_states)

    pl = sub.add_parser("labels", parents=[common], help="라벨 목록 / 생성")
    pl.add_argument("--create", nargs="+", metavar="NAME",
                    help="지정한 이름의 라벨 생성")
    pl.set_defaults(func=cmd_labels)

    # 레거시 호환: `plane_sync.py <파일>.json` -> create, `--check` -> check
    argv = sys.argv[1:]
    known = {"check", "create", "states", "labels", "-h", "--help"}
    if argv and argv[0] not in known:
        if argv[0] == "--check":
            argv = ["check"] + argv[1:]
        elif argv[0].endswith(".json"):
            argv = ["create"] + argv

    args = ap.parse_args(argv)
    if not getattr(args, "func", None):
        ap.print_help()
        return
    args.func(args)


if __name__ == "__main__":
    main()
