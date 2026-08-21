---
name: project-appfit-migration-monitoring
description: Sunmi CSV로 타겟 기기의 appfit 설치 여부를 날짜별 추적하는 SQLite 도구. 코호트 freeze 이유와 위치·운용법·용어 규칙.
metadata:
  node_type: memory
  type: project
  originSessionId: 57eac001-5611-4e07-89d1-195dc2e44c98
  modified: 2026-08-20T06:42:55.557Z
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

**대상앱 패키지 전환 결정 — 적용 완료 (2026-08-19)**: `monitor.py`의 `APPFIT_PKG` 를 공통 appfit(`co.kr.waldlust.order.receive.appfit`) → **매머드 전용 빌드 `co.kr.waldlust.order.receive.appfit.mammoth` 단독**으로 교체(사용자 선택: 전용만 인정, 공통만 깔린 기기는 미설치). 코호트(구앱 2.0.6 기준 881대)는 freeze 유지 — 분모 불변. README.md 도 정의 갱신.
- **sticky 재계산은 코드 구조상 자동으로 해결됐다**: `compute_status()`가 매 실행마다 **전 스냅샷 날짜를 순서대로 `daily_status` 삭제 후 원본 `device_apps`에서 재계산**하는 구조라(캐스케이드로 이전 계산된 `installed` 를 참조), 상수만 바꾸고 `--report-only` 를 돌리면 과거 스냅샷까지 새 패키지 기준으로 다시 확정된다. 별도 wipe/force-recohort 불필요 — 이 도구 한정으로는 "상수 바꾸고 재실행"이 곧 안전한 재계산이다.
- **2026-08-18 데이터로 재실행 결과: 설치 0대/879대(0.0%)** — 사용자가 "의도한 내용"으로 확인(2026-08-19). 타겟 881대 중 2대는 이번에 30일 미접속으로 `dropped`. `device_apps` 직접 조회로도 8/18 스냅샷엔 `...appfit.mammoth` 패키지가 0대(공통 appfit 은 5대만 관측) — 매머드 전용 빌드 첫 배포가 같은 날(8/18)이라 콘솔 앱 인벤토리 스캔이 그 시점 이전에 수집됐을 가능성이 높다. 버그 아님, 확정.
- **의미 있는 수치는 8/19 이후 스냅샷부터.** 그 전까지는 재실행해도 0이 정상 — 사용자가 새 CSV를 줄 때만 다시 돌릴 것.
- **대용량 CSV는 채팅 붙여넣기로 온전히 못 옮긴다.** 사용자가 채팅에 파일을 첨부하면 실제로는 `~/Downloads/<원본파일명>`에 그대로 저장돼 있다 — Write 툴로 재입력 시도하지 말고 먼저 `find ~/Downloads -iname "<파일명>"` 로 원본을 찾아 `cp` 할 것. (947KB apps_ CSV를 Write로 받아적으려다 2.5KB로 잘린 사고 1회 — Downloads 확인 후 정정.)

**설치 "판정" 소스 교체 — apps_ CSV 관측 → Upgrade Details.xlsx (2026-08-20)**: 분모/분자를 서로 다른 소스로 분리한 구조가 최종형이다.
- **분모(대상 기기) = apps_/device_ CSV**, 종전 그대로 구앱(`co.kr.waldlust.order.receive`) 2.0.6 + 30일 이내 활성. 최신 스냅샷(8/20) 기준 **876대**(버전무관이면 907대). 베이스라인 freeze 유지.
- **분자(설치 판정) = `Upgrade Details.xlsx`** 의 Upgrade time ≥ `UPGRADE_TIME_CUTOFF`(2026-08-20). Status(`Not updated` 포함)는 보지 않고 시간 조건만. 8/20 기준 59대 중 코호트 교집합 55대 = 6.3%.
- **freeze 대상이 정반대다**: 코호트는 freeze, Upgrade Details 는 매 실행마다 테이블 통째 교체(수시 갱신이 정상). `--report-only` 를 포함해 **어떤 모드로 실행하든 항상 다시 읽도록** `main()` 에서 `load_upgrade_details()` 를 무조건 호출.

**Why(판정 소스를 바꾼 실측 근거)**: 8/20 스냅샷에서 업그레이드 55대 중 apps_ CSV 로 실제 관측된 건 **단 1대**였다. 업그레이드 시각 14:42~14:47 vs apps_ 수집 14:52 — 콘솔 앱 인벤토리가 업그레이드를 즉시 반영하지 않는다. 즉 apps_ 관측 기반 판정은 실제 설치를 며칠 늦게 잡는 구조적 지연이 있었다. **리포트의 "실측 미관측"은 정상이며 오류가 아니다** — 이 설명을 안 달면 매번 "왜 0대냐"가 된다.

**How to apply:**
- 판정은 스냅샷 날짜별로 `cutoff <= upgrade_date <= snapshot_date` — 과거 스냅샷에 미래 업그레이드가 소급되지 않게 상한을 반드시 걸 것. 날짜는 ISO(`YYYY-MM-DD`)로 정규화해 문자열 비교=날짜 비교가 성립하게 한다(원본은 `YYYY/MM/DD HH:MM`).
- **역방향 불일치는 미설치가 맞다 — 사용자 확정(2026-08-20).** apps_ 에는 매머드가 보이는데 Upgrade 기록이 없는 기기(8/20 기준 1대, DE10P45A10090 과천중앙공원점 3.0.0 = OTA·수동 설치 경로)는 `pending` 으로 둔다. **판정 정본은 Upgrade Details 하나뿐이고, 실측을 근거로 설치로 승격하지 않는다.** 예외는 `--mark-installed` 로 사람이 명시적으로 확정할 때만. 다만 조용히 묻히면 나중에 "왜 빠졌지"가 되므로 어떤 기기가 그렇게 분류됐는지는 리포트에 "참고" 카드로 남긴다(조치 불필요·설치율 미반영을 문구에 명시).
- **표준 라이브러리로 .xlsx 파싱**: `openpyxl`/`pandas` 미설치 환경이라 `zipfile`+`xml.etree` 로 `xl/worksheets/sheet1.xml` 직접 읽음(`_xlsx_rows`/`read_upgrade_details`). 셀이 inline string(`t="inlineStr"`)이고 sharedStrings.xml 이 없다. 같은 SN 다중 행이면 Upgrade time 최신 행만.
- **`--force-recohort` 는 `cohort` 를 통째로 지운다 — 수동 편입·메모도 함께 사라진다.** 실제로 겪음(DE33256H10784·TN11211U40325 메모 소실 → `--add-target --note` 로 복구). cutoff 만 바꿀 때는 `--force-recohort` 불필요.
- `daily_status` 에 ALTER 로 붙인 컬럼(`upgrade_date`/`observed_version`)은 맨 뒤로 가므로 **INSERT 는 컬럼명 명시 필수** — 위치 기반이면 기존 DB와 새 DB의 순서가 어긋나 값이 밀린다.

**요구사항을 거꾸로 이해한 사고 (2026-08-20)**: 첫 지시 "집계 대상을 Upgrade Details 파일 기준으로"를 **코호트(분모) 교체**로 읽고 59대 코호트를 만들었으나, 실제 의도는 **설치 판정(분자) 교체**였다. 사용자가 "대상 기기 / mammoth앱 설치 여부"로 항목을 나눠 재설명해 바로잡음. **"집계 대상"처럼 분모·분자 어느 쪽도 가리킬 수 있는 말이 나오면 되묻거나, 최소한 어느 쪽으로 읽었는지 명시하고 진행할 것.** 잘못된 전제 위에서 AskUserQuestion 을 던지면 사용자가 그 프레이밍에 갇힌 답을 고르게 되어(실제로 "완전 대체"를 골랐다) 오해가 오히려 굳는다.
관련: [[project_mammoth_dedicated_build]].
