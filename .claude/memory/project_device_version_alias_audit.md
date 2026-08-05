---
name: project-device-version-alias-audit
description: Sunmi sm_partner MSN 목록 + apps 설치현황 CSV를 교차 매칭해 특정 앱버전 설치 기기의 매장명(Alias)을 뽑는 반복 작업. 스크립트·산출물 위치와 CSV 함정 기록.
metadata: 
  node_type: memory
  type: project
  originSessionId: 5766ad4c-1dc0-4d65-88f5-956758a9f70e
  modified: 2026-08-05T01:23:09.935Z
---

Sunmi 파트너 콘솔에서 내려받은 두 CSV(기기 목록 + 설치 앱 현황)를 교차 매칭해, 특정 패키지·버전이 설치된 기기의 시리얼(SN)과 매장명(Alias)을 뽑아내는 작업. 2026-08-05 최초 실행: `co.kr.waldlust.order.receive` versionName `2.0.6` 설치 기기 958대 식별(전부 sm_partner 목록에서 Alias 매칭 성공).

**Why:** 구버전(2.0.6) 잔존 기기 파악 — 업데이트 캠페인·매장 연락 대상 추리기 위한 것으로 추정(사용자가 명시적 목적은 밝히지 않음, 재진행 예고만 함).

**How to apply:** "이 매칭 다시 해줘" / "다른 버전으로 다시" 같은 요청이 오면:
1. 사용자가 최신 CSV를 `~/Downloads/`에 새로 내려받아 두는지 먼저 확인(파일명에 날짜/ID가 박혀 있어 매번 바뀜 — `apps_D<날짜>.csv`, `sm_partner__msn_list_<ID>.csv`). `find ~/Downloads -iname "*sm_partner*" -o -iname "*apps_D*"`로 최신 파일 찾기.
2. 재사용 가능한 스크립트: `~/Downloads/sm_partner_app_version_match.py` (이 세션에서 작성, 상단 상수 `APPS_CSV`/`SM_PARTNER_CSV`/`OUT_CSV`/`TARGET_PACKAGE`/`TARGET_VERSION`만 바꾸면 재실행 가능). **주의**: 스크래치패드(`/private/tmp/claude-501/.../scratchpad/`)는 세션 종료 후 사라지므로 스크립트는 항상 repo 밖 영구 위치(`~/Downloads` 등)에 저장할 것 — 이번에도 최초엔 scratchpad에 썼다가 뒤늦게 Downloads로 옮김.
3. 실행: `python3 ~/Downloads/sm_partner_app_version_match.py`

**CSV 함정(둘 다 실제 파일 기준, 대화에 붙여넣기된 텍스트의 mojibake는 무시할 것):**
- `apps_D*.csv`는 **첫 줄이 `"Machine Application"` 타이틀 행**이고 실제 헤더(`SN,Model,"ROM Version",...`)는 둘째 줄부터. `csv.DictReader` 전에 `f.readline()`으로 한 줄 건너뛰지 않으면 전부 `None` 키로 깨짐(최초 실행 때 이걸 놓쳐 매칭 0건 나왔었음).
- `apps_D*.csv`는 UTF-8이 아닌 바이트가 섞여 있어(중국어 앱 등) `encoding='utf-8'` 그대로 열면 `UnicodeDecodeError` — `errors='replace'`로 열 것. appName 필드 자체가 소스에서부터 한글이 리터럴 `?`로 깨져 있는 기기들도 있음(내보내기 도구 문제, 우리 쪽 디코딩과 무관) — packageName/versionName은 ASCII라 매칭엔 영향 없음.
- `sm_partner__msn_list_*.csv`는 `utf-8-sig`(BOM 포함)로 열면 정상 — 별도 처리 불필요.
- `Currently Installed App(s)` 컬럼은 CSV 이스케이프된 JSON 배열(`""` → `"`) — csv 모듈이 정상 파싱하면 `json.loads`로 바로 읽힘.

**산출물**: `~/Downloads/order_receive_2.0.6_devices_with_alias.csv` — SN, InstalledVersion, Alias, Terminal(sm_partner 기준 정본 모델명), Model/ROM Version(apps CSV 기준 — `T2mini_s1`처럼 Terminal과 표기가 다른 경우 있음, 참고용), Activation/Last Active Time, Location, FoundInSMPartner.
