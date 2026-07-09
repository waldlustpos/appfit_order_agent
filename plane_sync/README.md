# plane_sync — Plane(waldsupport.com) 이슈 벌크 생성

self-hosted **Plane** 프로젝트(`https://waldsupport.com/main/projects/353cefb5-.../issues`)에
작업(이슈)을 REST API 로 벌크 생성하는 재사용 스크립트. stdlib(`urllib`)만 사용 — 추가 의존성 없음.

## 준비 (1회)

repo 루트 `.env` 에 Plane Personal Access Token 을 추가한다(`.env` 는 gitignore 됨):

```
PLANE_API_TOKEN=<Plane Personal Access Token>
# 선택 오버라이드 (기본값 내장):
# PLANE_BASE_URL=https://waldsupport.com
# PLANE_WORKSPACE=main
# PLANE_PROJECT_ID=353cefb5-7bb2-426f-8ec5-88702fb0a7e3
```

> 변수명은 `PLANE_API_TOKEN` 우선, `WALDSUPPORT_API_KEY` 도 허용.

토큰 발급: Plane → 우상단 프로필 → **Settings → Personal Access Tokens → Add personal access token**.

## 사용

두 가지 방법: **① 터미널 CLI** 또는 **② 채팅에서 `/plane` 슬래시 명령**.

### ① 터미널 (서브커맨드)

```bash
# 조회/검증
python3 plane_sync/plane_sync.py check      # 연결·엔드포인트·상태·라벨 한눈에
python3 plane_sync/plane_sync.py states     # 상태(state) 목록 + uuid
python3 plane_sync/plane_sync.py labels     # 라벨 목록 + uuid
python3 plane_sync/plane_sync.py labels --create 신규라벨   # 라벨 생성

# 이슈 생성
python3 plane_sync/plane_sync.py create plane_sync/tasks.json --dry-run       # 미리보기(POST 없음)
python3 plane_sync/plane_sync.py create plane_sync/tasks.json                 # 실제 생성
python3 plane_sync/plane_sync.py create plane_sync/tasks.json --create-labels # 없는 라벨 자동 생성
python3 plane_sync/plane_sync.py create plane_sync/tasks.json --force         # 상태파일 무시 재생성
```

> 호환: `plane_sync.py tasks.json` = `create tasks.json`, `plane_sync.py --check` = `check`.

### ② 채팅 (`/plane`)

```
/plane check
/plane states
/plane [공통] 라벨프린터 상단영역 수정 / QR 페이로드 변경으로 상단 잘림 수정 / low / 에이전트 / todo
```
`제목 / 설명 / 우선순위 / 라벨 / 상태(선택)` 형식(한 줄 = 한 작업). Claude 가 `tasks.json`
으로 정규화 → dry-run → 확인 후 생성한다. 정의: [.claude/commands/plane.md](../.claude/commands/plane.md).

## 입력 형식 (`tasks.json`)

JSON 배열. 각 원소에서 **`name` 만 필수**. 예시는 [tasks.example.json](tasks.example.json).

| 필드 | 필수 | 설명 |
|------|------|------|
| `name` | ✅ | 이슈 제목 |
| `description` | | 평문 설명 (자동으로 `<p>`/`<br>` HTML 변환) |
| `description_html` | | HTML 설명 (있으면 `description` 보다 우선) |
| `priority` | | `urgent` / `high` / `medium` / `low` / `none` |
| `labels` | | 라벨 **이름** 배열 — uuid 로 자동 해석(없으면 스킵, `--create-labels` 로 생성) |
| `state` | | 상태 **이름**(`backlog`/`todo`/`in progress`/`done`/`cancelled`) 또는 uuid — 이름은 자동 해석 |
| `external_id` | | 안정적 고유키 (없으면 `name` 해시로 자동 생성) |

## 멱등성

`external_source="claude-plane-sync"` + `external_id` 로 각 이슈를 식별한다.
생성 결과는 `plane_sync/.plane_sync_state.json`(gitignore)에 기록되며, 재실행 시
이미 생성된 `external_id` 는 자동 스킵된다. 상태파일이 없어도 Plane 서버가
동일 `external_id+source` 중복을 거부하므로 중복 생성은 방지된다. 강제 재생성은 `--force`.

## 흐름

1. 사용자가 작업 목록을 제공(채팅/파일).
2. Claude 가 `plane_sync/tasks.json` 으로 정규화.
3. `--dry-run` 확인 → 실제 생성.
