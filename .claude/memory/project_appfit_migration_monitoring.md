---
name: project-appfit-migration-monitoring
description: Sunmi CSV로 타겟 기기의 appfit 설치 여부를 날짜별 추적하는 SQLite 도구. 코호트 freeze 이유와 위치·운용법·용어 규칙.
metadata:
  node_type: memory
  type: project
  originSessionId: 57eac001-5611-4e07-89d1-195dc2e44c98
  modified: 2026-08-14T07:12:22.932Z
---

`/Users/kimsungchun/Documents/Sunmi-Appfit Monitoring/` 에 `monitor.py` + `report_html.py` + `fleet.db`(SQLite) + `README.md`. 매일 `apps_D<날짜>.csv` / `device_D<날짜>.csv` 를 폴더에 넣고 `python3 monitor.py` 하나면 적재→상태계산→CSV 3종 + `reports/latest.html` 까지 나온다. 파이썬 표준 라이브러리만 사용(이 맥에 duckdb·pandas 없음, `/usr/bin/python3` 시스템 파이썬). 2026-08-14 구축, 실데이터 + 가짜 스냅샷 시뮬레이션으로 검증 완료.

베이스라인 2026-08-13: 구앱 설치 1136대 → 30일 이내 활성 911대 → 그중 **구앱 2.0.6 정확히 880대가 타겟** + 수동 편입 1대(개발실테스트) = 881대. 조건 밖 31대는 2.0.6 미만 25대(1.0.1~1.2.0) + 초과 5대(2.0.15·2.1.0·3.3.x, 대체로 개발기기).

**Why:** 조건마다 스크립트 상수를 고쳐 재실행하는 단발 방식(`~/Downloads/sm_partner_app_version_match.py`, [[project-device-version-alias-audit]])으로는 시점 간 비교가 원천적으로 불가능했다. 목표가 "특정 시점부터 설치 여부를 모니터링"이라 스냅샷 누적 구조가 필요했다.

**How to apply:**
- **용어는 "전환"이 아니라 "설치 여부".** 구 앱(`co.kr.waldlust.order.receive`)과 appfit(`...receive.appfit`)은 **패키지가 달라 한 기기에 공존한다** — 실제로 개발실테스트 장비가 구앱 2.1.0 + appfit 3.0.0 둘 다 설치 상태다. "전환"은 구앱이 사라진다는 오해를 부른다. DB status 값도 `installed`(← 옛 `migrated`), 화면도 설치 완료/미설치/설치율로 통일했다. 사용자가 직접 잡아준 지적이다.
- **버전 조건은 하루 사이 네 번 바뀌었다(2.0.6만 → 무관 → 이하 → 다시 2.0.6만).** 최종은 `TARGET_VERSION="2.0.6"` + `TARGET_VERSION_MATCH="exact"`. 그래서 세 모드(exact/lte/None=무관)를 상수 두 개로 전환 가능하게 만들어 뒀다 — **자주 흔들리는 정책은 코드가 아니라 상수로 뽑아 둘 것.** 조건 밖 기기는 데이터에 남아 있으니 언제든 다시 잡을 수 있다.
- **버전 비교는 SQL 문자열로 하면 안 된다.** `'2.0.15' < '2.0.6'` 이 참이 되어 조건 초과 기기가 타겟에 섞인다. lte 모드는 숫자 튜플 비교(`ver_lte()`, 자리수 0 패딩)로 파이썬에서 필터한다.
- **코호트는 freeze — 매일 재계산하면 안 된다.** 이유가 조건에 따라 바뀌므로 셋 다 기억할 것: ①"최근 30일 활성"이 **슬라이딩 윈도우**라 매일 뜻이 달라져 분모가 요동친다, ②재계산하면 **신규 개통 기기**가 계속 분모에 섞여 캠페인이 진행돼도 설치율이 제자리로 보인다, ③구앱이 제거되면 조건에서 빠져 증발한다. (버전 조건이 있던 시절엔 "버전 상승으로 이탈"도 이유였는데, 조건 완화로 그건 해소됐다 — 논거가 조건에 종속된다는 것 자체가 교훈.) 어떤 "조건으로 추려 이후를 추적" 요청이든 같은 함정이 있다 — 추적 대상은 관측 시점에 박제할 것.
- **설치 판정은 sticky.** 콘솔이 하루치 앱 데이터를 누락하면 관측만으로는 installed 가 pending 으로 되돌아가 설치율이 뒷걸음질친다. sticky 를 뷰 단계에서만 적용했다가 타일(849)과 표(863)가 어긋난 적 있음 — **상태 계산 단계에서 확정**해야 installed/pending/unknown/dropped 4상태가 배타적이 되고 합이 타겟과 맞는다.
- **"미설치"와 "앱 데이터 없음"은 다르다.** `device_` 에만 있고 `apps_` 에 없는 기기가 120대. 이걸 미설치로 세면 집계가 틀어진다 → `unknown` 으로 분리.
- 조건 밖 기기 편입은 `--add-target <SN> --note "이유"`. `source='manual'` 로 출처가 남고 리포트 헤더에 항상 표시된다. 이미 타겟에 있는 SN이면 메모만 갱신한다.
- 조건 변경은 `monitor.py` 상단 상수(`TARGET_VERSION` / `INACTIVE_DAYS` / `LEGACY_PKG`) 수정 후 `--init-cohort <날짜> --force-recohort`.
- 매장명(Alias)은 `device_` 에 없다. `sm_partner__msn_list_<epoch>.csv`(파일명 숫자 = 유닉스 타임스탬프)를 같은 폴더에 두면 조인해 채운다. 1301대 중 926대만 Alias 존재.
- 임시 질의는 `sqlite3 fleet.db` 로 직접. 주요 뷰 `v_progress` / `v_pending` / `v_newly_installed` / `v_cohort_status`.
- CSV 파싱 함정(타이틀 1행 스킵, `errors='replace'`, appName 한글 깨짐)은 [[project-device-version-alias-audit]] 와 동일하며 코드에 반영돼 있다.

**대상앱 패키지 전환 결정 (2026-08-19, 미적용)**: 집계 대상앱을 공통 appfit(`co.kr.waldlust.order.receive.appfit`) → **매머드 전용 빌드 `co.kr.waldlust.order.receive.appfit.mammoth` 단독**으로 교체하기로 확정(사용자 선택: 전용만 인정, 공통만 깔린 기기는 미설치). 코호트(구앱 2.0.6 기준 881대)는 freeze 유지 — 분모 불변. 도구 정본이 Mac 에만 있어 Windows 세션에서는 적용 불가, 패치 절차만 전달했다. 적용 시 필수 후속: **sticky 로 굳은 과거 `installed` 행 재계산**(공통 appfit 기준으로 확정된 상태가 남으면 수치가 거짓말한다). 지표 의미가 "appfit 보급률"→"전용 빌드 보급률"로 바뀌므로 설치율 하락은 정상이며, 전용 빌드 배포 개시일은 2026-08-18(3.0.0+185)이라 0 근처에서 시작한다. 관련: [[project_mammoth_dedicated_build]].
