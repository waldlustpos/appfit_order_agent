---
description: Plane(waldsupport.com) 프로젝트에 작업(이슈)을 생성하거나 상태/라벨을 조회 — plane_sync CLI 래퍼
---

Plane 프로젝트 `SX(KIOSK/AGENT)`(waldsupport.com)에 작업을 생성/조회하는 명령이다.
엔진은 [plane_sync/plane_sync.py](../../plane_sync/plane_sync.py) (stdlib CLI). 토큰은 `.env`의 `PLANE_API_TOKEN`.

입력: `$ARGUMENTS`

## 1) 조회/검증 서브커맨드 — `$ARGUMENTS` 가 아래 중 하나면 그대로 실행하고 결과만 요약한다

- `check`  → `python3 plane_sync/plane_sync.py check` (연결·엔드포인트·상태·라벨)
- `states` → `python3 plane_sync/plane_sync.py states`
- `labels` → `python3 plane_sync/plane_sync.py labels`

## 2) 그 외 — `$ARGUMENTS` 를 **작업 목록**으로 보고 이슈를 생성한다

### 작업 한 줄 형식 (한 줄 = 한 작업)
```
제목 / 설명 / 우선순위 / 라벨[,라벨2] / 상태(선택)
```
- 구분자는 `/`. 여러 라벨은 라벨 칸 안에서 `,` 로 구분.
- 뒤쪽 칸은 생략 가능(예: `제목 / 설명 / low` 만 줘도 됨). 제목만 있어도 생성된다.
- 제목의 `[공통]` `[에이전트]` 같은 접두어는 **제목에 그대로 유지**한다(라벨로 빼지 않음).

### 필드 정규화
- **우선순위**: `urgent|high|medium|low|none`. 한국어도 매핑 — 긴급→urgent, 높음→high, 보통→medium, 낮음→low, 없음→none. 빈 값이면 생략.
- **상태(state)**: 이 프로젝트는 `backlog / todo / in progress / done / cancelled`. 한국어 매핑 — 할일·대기→todo, 진행·진행중→in progress, 완료→done, 백로그→backlog, 취소→cancelled. 이름 그대로 `state` 에 넣으면 스크립트가 uuid 로 해석한다.
- **라벨**: 이름을 그대로 넣는다(스크립트가 uuid 해석). 오타 방지를 위해 먼저 `python3 plane_sync/plane_sync.py labels` 로 기존 라벨을 확인하고 최대한 기존 이름에 맞춘다. 기존 라벨(예: `에이전트/키오스크/공통 없음→없이/매머드커피/빽다방/하드웨어/printer/android/cleanup/appfit`)에 없는 새 라벨이면 사용자에게 "새 라벨 X 를 만들까요?" 확인한다.

### 절차 (반드시 순서대로)
1. 기존 라벨/상태 확인이 필요하면 `labels` / `states` 를 먼저 실행한다.
2. 파싱한 작업들을 **JSON 배열**로 [plane_sync/tasks.json](../../plane_sync/tasks.json) 에 Write 한다. 각 원소는 `{name, description, priority?, labels?, state?}`. (`tasks.json` 은 gitignore 대상)
3. **미리보기**: `python3 plane_sync/plane_sync.py create plane_sync/tasks.json --dry-run` 실행 → payload 를 사용자에게 보여준다.
4. 새 라벨이 있으면 생성 여부를 확인한다.
5. **확인 후 생성**: `python3 plane_sync/plane_sync.py create plane_sync/tasks.json` 실행. 새 라벨을 만들기로 했으면 `--create-labels` 를 붙인다.
6. 결과 요약: 생성된 이슈 제목·work-item id, 그리고 프로젝트 URL
   `https://waldsupport.com/main/projects/353cefb5-7bb2-426f-8ec5-88702fb0a7e3/issues` 안내.

### 멱등성 주의
- 같은 제목을 다시 생성하려 하면 `external_id`(제목 해시)로 **skip** 된다. 의도적 재생성은 `--force`.
- 즉 제목이 같으면 중복 이슈가 안 생기니, 재실행을 두려워하지 말 것.

## 오류 처리
- `PLANE_API_TOKEN` 누락(인증 401/403) 시 `.env` 에 토큰을 넣도록 안내한다.
- FAILED 가 나오면 스크립트가 출력한 status/응답 본문을 그대로 사용자에게 전달한다.
