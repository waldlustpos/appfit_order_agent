---
name: project_label_category_subinfo_settings
description: "라벨 출력 카테고리 필터 + subInfo 지정을 TPCP 하드코딩에서 매장 설정으로 일반화(브랜치 feat/label-category-subinfo-settings, 미푸시·미배포). 시드 없이 완전 대체라 TPCP 는 배포 후 현장 재설정이 필요하다."
metadata:
  type: project
---

TPCP 매장 POS 코드로 박혀 있던 라벨의 두 판정을 매장 설정으로 옮겼다. 브랜치 `feat/label-category-subinfo-settings`(커밋 `68ce2fb` + codegen 정리 `9483214`), **미푸시·실기기 미검증·미배포**. 계획 파일 `~/.claude/plans/typed-wobbling-pinwheel.md`.

- 출력 카테고리 필터: `OrderCategoryCodes.waffleCategoryCodes={'TKP1006'}` + 3버튼(전체/와플만/와플제외) → ON/OFF 스위치 + 카테고리 다중선택 전용화면.
- subInfo: `TKP012`(원두)/`TKP001~003`(온도)/`TKP004,009~013`(사이즈) → 옵션그룹 최대 3개 선택, **고른 순서 = 인쇄 순서**.
- 제거: `LabelFilterStrategy` 3형제, `OrderCategoryCodes`, `KEY_LABEL_FILTER_MODE`, `BrandFeature.labelCategoryFilter`.
- 신규: `LabelOutputPolicy`(+`labelOutputPolicyProvider`), `ShopOptionGroupModel`, 화면 2개, 패널 위젯 1개.

**Why (사용자 결정 4건 — 코드에서 역산 불가):**
1. **완전 대체 + 시드 없음.** "TPCP 기본값 자동 시드" 를 제안했으나 사용자가 시드 없는 완전 대체를 골랐다. → **TPCP 매장은 배포 직후 라벨이 '전량 출력 + subInfo 없음' 으로 돌아간다.** 현장에서 기기마다 재설정해야 종전 동작이 복원된다. 이건 남아 있는 **운영 액션**이지 버그가 아니다.
2. **subInfo 는 선택 순서대로 + 화면에 순번 표시.** "3칸 고정 슬롯" 대안을 버렸다.
3. 선택 UI 는 별도 전체화면(다이얼로그 아님).
4. **재출력은 필터 우회 전체 출력** — 기존 `isReprint` 규약 승계.

**설계 결정 중 되돌리기 쉬운 것 (근거는 docs/PRINTER_FLOW.md §3.7 표에 전부 있다):**
- **ON + 선택 0개 = 전량 인쇄.** 사용자가 "전체체크와 전체해제가 사실상 같은 기능인데 어떻게 표현?" 이라고 물은 것에 대한 답이다. 라벨을 아예 안 내는 건 `라벨 프린터 사용` OFF 의 일이고, 설정 실수로 매장 라벨이 멈추는 사고를 막는다. 화면이 이걸 문구로 안내한다 — **"빈 선택 = 아무것도 안 나옴" 으로 바꾸자는 요청이 오면 이 근거를 먼저 꺼낼 것.**
- **fail-open.** `shopCatalogProvider` 는 조회 실패 시 예외가 아니라 **빈 목록**을 반환한다. 미매칭/빈 카탈로그를 스킵으로 처리하면 조회 한 번 실패에 매장 라벨이 통째로 사라진다.
- **`orderIndex`/`orderTotal` 은 필터 무관 주문 전체 기준 유지.** 컵 식별자이자 QR 페이로드 정본이라 `2/5`·`4/5` 처럼 번호가 건너뛰는 게 정상. "번호가 이상하다" 문의가 오면 버그가 아니다 ([[project_label_qr_cupidx_collision]]).
- **상한 3개**의 실제 근거는 58mm 서브정보 바가 `maxLines: 1` 이라 넘치면 **조용히 잘리는 것**. 갭 라벨도 줄바꿈/축소가 없다.

**함정 2개:**
- painter 3종이 subInfo 를 **각자 다른 순서**로 그리고 있었다(갭=사이즈/온도/원두, 40mm=원두/온도/사이즈, 58mm=온도/사이즈/원두). 목록 순서로 통일했는데 **갭 라벨만 오른쪽부터 그려 목록을 뒤집어야 한다** — `LabelPainter.subInfoDrawOrder` 가 그 반전을 격리하고 테스트가 고정한다. 여기 손대면 반드시 그 테스트를 볼 것.
- 옵션그룹 **표시명이 파서에서 유실**되고 있었다. 옵션은 인공 '옵션' 버킷으로 접히면서 `categoryName` 이 버킷명으로 덮이고 `categoryCode` 에만 그룹 POS 코드가 남는다. `parseShopCatalog` 가 `optionGroups` 를 카테고리처럼 분리 반환하도록 확장해야 후보를 이름으로 보여줄 수 있다(주문이 없어도 후보 생성 가능한 근거).

**남은 것:** ① 실기기 검증(계획 파일의 검증 절 그대로 — OFF/일부선택/재출력/전체해제/subInfo 순서/매장전환) ② 갭·G30 40mm·G30 58mm 3종 레이아웃 확인 ③ TPCP 현장 재설정 안내 ④ 푸시·배포.

관련: [[project_label_qr_cupidx_collision]], [[reference_active_store_id_is_session_key]], [[feedback_brand_artifact_visual_only]], [[reference_slang4_multifile_and_analyze_baseline]]
