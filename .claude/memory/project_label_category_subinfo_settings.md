---
name: project_label_category_subinfo_settings
description: "라벨 출력 카테고리 필터만 매장 설정으로 일반화(브랜치 feat/label-category-subinfo-settings, 미푸시·미배포). subInfo 매장 지정은 구현했다가 롤백 — 점주 조작 부담 + 매장별 옵션그룹 데이터 편차. TPCP 는 배포 후 카테고리 재설정 필요."
metadata:
  type: project
---

TPCP 매장 POS 코드로 박혀 있던 라벨 판정 중 **출력 카테고리 필터만** 매장 설정으로 옮겼다. 브랜치 `feat/label-category-subinfo-settings`(`68ce2fb` 구현 → `1e2417b` subInfo 롤백), **미푸시·실기기 미검증·미배포**. 계획 파일 `~/.claude/plans/typed-wobbling-pinwheel.md`(subInfo 절은 폐기됨).

- 출력 카테고리 필터: `waffleCategoryCodes={'TKP1006'}` + 3버튼(전체/와플만/와플제외) → ON/OFF 스위치 + 카테고리 다중선택 전용화면. **매장 설정.**
- 라벨 sub-info(원두/온도/사이즈): **브랜드 하드코딩 그대로.** `LabelSubInfoStrategy` + `BrandFeature.labelSubInfo`(구 `labelCategoryFilter` 를 이름값 하도록 개명).

## subInfo 매장 지정은 만들었다가 롤백했다 (2026-09-03)

옵션그룹을 점주가 최대 3개까지 순서대로 고르는 화면까지 구현했다가 사용자 판단으로 되돌렸다. **이유: ① 점주가 옵션그룹을 고르는 조작 부담이 크고 ② 그룹 이름·구성이 매장마다 제각각이라 화면만 보고 무엇을 골라야 할지 알기 어렵다.** 라벨에 무엇을 크게 찍을지는 매장 취향보다 브랜드 운영 정책에 가깝다는 결론.

- 롤백 시 painter 3종·더미 경로·카탈로그 파서를 **pre-feature 와 바이트 동일**로 복원해 TPCP 라벨 레이아웃 회귀 위험을 없앴다.
- 함께 버린 것: `ShopOptionGroupModel`, 파서 `optionGroups`, `shopOptionGroupListProvider`. 이건 **오직 subInfo 선택 화면의 후보 목록**을 위해 넣었던 것이다. 옵션그룹 표시명이 필요해지면 다시 만들어야 한다 — 옵션이 인공 '옵션' 버킷으로 접히며 `categoryName` 이 버킷명으로 덮이고 `categoryCode` 에만 그룹 POS 코드가 남기 때문에 카탈로그에서 이름을 못 얻는다(파서가 `rawGroup['name']` 을 안 읽는다).
- **두 축을 한 클래스에 다시 합치지 말 것.** 카테고리 필터는 매장 설정, subInfo 는 브랜드 정책이라 수명이 다르다. 원래 `LabelFilterStrategy` 하나에 둘 다 있었고 그게 이번에 갈라진 이유다.

**Why (사용자 결정 — 코드에서 역산 불가):**
1. 카테고리 필터는 **완전 대체 + 시드 없음.** "TPCP 기본값 자동 시드" 제안을 물렀다. → **TPCP 매장은 배포 직후 카테고리 필터가 OFF(전량 출력)로 시작한다.** 종전 와플 필터를 쓰던 기기는 현장에서 다시 지정해야 한다. 남아 있는 **운영 액션**이지 버그가 아니다. (subInfo 는 롤백했으니 종전대로 나온다.)
2. 선택 UI 는 별도 전체화면(다이얼로그 아님).
3. **재출력은 필터 우회 전체 출력** — 기존 `isReprint` 규약 승계.
4. subInfo 매장 지정 롤백(위 절).

**되돌리기 쉬운 결정 (근거는 docs/PRINTER_FLOW.md §3.7 표에 전부 있다):**
- **ON + 선택 0개 = 전량 인쇄.** 사용자가 "전체체크와 전체해제가 사실상 같은 기능인데 어떻게 표현?" 이라고 물은 것에 대한 답이다. 라벨을 아예 안 내는 건 `라벨 프린터 사용` OFF 의 일이고, 설정 실수로 매장 라벨이 멈추는 사고를 막는다. 화면이 이걸 문구로 안내한다 — **"빈 선택 = 아무것도 안 나옴" 으로 바꾸자는 요청이 오면 이 근거를 먼저 꺼낼 것.**
- **fail-open.** `shopCatalogProvider` 는 조회 실패 시 예외가 아니라 **빈 목록**을 반환한다. 미매칭/빈 카탈로그를 스킵으로 처리하면 조회 한 번 실패에 매장 라벨이 통째로 사라진다.
- **`orderIndex`/`orderTotal` 은 필터 무관 주문 전체 기준 유지.** 컵 식별자이자 QR 페이로드 정본이라 `2/5`·`4/5` 처럼 번호가 건너뛰는 게 정상. "번호가 이상하다" 문의가 오면 버그가 아니다 ([[project_label_qr_cupidx_collision]]).

**남은 것:** ① 실기기 검증(OFF/일부선택/재출력/전체해제/매장전환 + TPCP subInfo 종전대로 나오는지) ② 갭·G30 40mm·G30 58mm 3종 레이아웃 확인 ③ TPCP 현장 카테고리 재설정 안내 ④ 푸시·배포.

관련: [[project_label_qr_cupidx_collision]], [[reference_active_store_id_is_session_key]], [[feedback_brand_artifact_visual_only]], [[reference_slang4_multifile_and_analyze_baseline]]
