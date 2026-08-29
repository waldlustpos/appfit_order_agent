---
name: project-simple-pos-jp-pilot
description: 신규 레포 appfit_simple_pos — 일본향 판매 등록기 파일럿. P0/P1 완료·실기기 검증
metadata: 
  node_type: memory
  type: project
  originSessionId: 63d816ff-a848-4835-861f-76dd56b13cbb
  modified: 2026-08-29T00:31:35.573Z
---

**레포**: `~/Documents/GitHub/appfit_simple_pos` (신규, 2026-08-28 시작)
**계획 정본**: `~/.claude/plans/simple-pos-jp-md-fizzy-cloud.md`
**조사 정본**: `appfit_order_agent/docs/SIMPLE_POS_JP.md`

파일럿 범위는 조사 문서 §11.1 보다 **의도적으로 훨씬 좁다**. 목표가 "매장에 넣을 물건"이 아니라
UI/UX 속도와 현재 AppFit API 로 판매가 성립하는지를 실기기에서 확인하는 것이기 때문이다.

| 축 | 결정 |
|---|---|
| 서버 | 스테이징 고정 (`core-stgapi`) |
| 결제 | 연동 없음. `payments=[{CASH, 전액}]` 1건 |
| 현금 | **금액 확정만** — 받은금액·거스름돈·드로어·시재 전부 없음(캐시리스 구조 채택 가능성 고려) |
| 영수증 | **단순 영수증** — 適格簡易請求書 5요건·領収書 없음 |
| 세액 | **법령 정합성은 추후 보완**(사용자 결정). 서버 검증식만 맞춘다 |
| 언어 | ja/ko/en 3개를 **동등하게** — 한국어도 1급 |
| 로컬 원장 | **씨앗만** — 테이블 + 멱등키 + 재시도 큐. 오프라인 완결 판매는 2차 |

**진행**: P0(골격·로그인)·P1(토큰·폰트·i18n) 커밋 2ff3e0c / P2(카탈로그·판매화면)·P3(금액계산)
커밋 c285cb6. **P4(로컬 원장·주문 등록/취소) 이후 미착수.**

**심어둔 씨앗** — 나중에 넣으면 원장 전체 마이그레이션이 되는 것들: `sales.id`=UUIDv4=멱등키=
`externalOrderNo` · `terminal_id` 컬럼(고정 "01") · `business_date` · `is_training` 플래그 ·
`origin_sale_id` 정정 링크 · `catalog_version` 라인 복사 · `Tender` 추상 · `allowBackup=false`.

**실기기 실측 (D3 MINI, Android 13)**: 물리 1280x800 / density 160 → **논리 해상도가 1280x800 과 1:1**.
조사 문서 §9.3 의 레이아웃 산술(160+736+384, 4열×5행)이 그대로 유효하다. 렌더러는 Impeller(Vulkan).

**스테이징 계정**: `TPCP00001`(tokyoplatscoffe)로 로그인·카탈로그 로드까지 실증됐다.
`MHST00084` 는 `404 NOT_FOUND_OWNER` — 매장마다 POS 로그인 가부가 다르다.
**남은 확인**: `orderSource=WALD_POS` 스테이징 허용 여부, 취소 `payInfos[]` 의 CASH 표현.

**개발 편의 장치**: 디버그 빌드 로그인 화면에 `DEMO (no server)` 버튼(`lib/dev/demo_data.dart`).
서버 없이 판매 화면 전체를 열어 UI 를 검증한다 — 계정·네트워크에 막히지 않는다.
에뮬레이터는 **Pixel Tablet 계열이 논리 1280×800 으로 D3 MINI 와 동일**하다.

관련: [[reference-font-coverage-pretendard-notosansjp]] · [[reference-kotlin-pin-sentry8]] ·
[[reference-themeextension-type-field-collision]] · [[project-sibling-kiosk-repos-jp]]
