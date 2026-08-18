---
name: feedback_flavor_preseed_vs_explicit_choice
description: "빌드 flavor 기반 강제는 \"런타임 설정값\"과 \"아티팩트 정체성 요소(로그인 로고 등)\"를 구분해야 한다 — 전자는 저장값 없음에만 개입, 후자는 테마 선택과 무관하게 항상 강제"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 194f4f88-499a-480f-a9c6-f0bef70cddfe
  modified: 2026-08-18T06:15:01.658Z
---

`BuildBrand.isMammoth` 로 로그인 전 브랜드 테마를 프리시드할 때, 판단 기준을 "저장된 preference id 가 null 인가"가 아니라 "해석된 `BrandTheme` 이 `appfitDefault` 와 같은가"로 잡으면 안 된다. 후자는 사용자가 설정 화면에서 **명시적으로** 기본 테마를 선택해 저장한 경우까지 다시 매머드로 덮어써버려서, mammoth flavor 빌드에서는 "기본 테마로 전환" 기능 자체가 죽는다(선택 → 저장 → 재시작해도 반영 안 됨).

**Why**: [[project_mammoth_dedicated_build]] 작업 중 "테마 기본일 때도 MAMMOTH flavor면 로그인 이미지도 매머드로"라는 요청을 받고 판단 조건을 `resolved == appfitDefault`로 넓혔다가, 사용자가 실기기에서 "설정→기본 테마 선택→재시작해도 테마 안 바뀜"으로 회귀를 발견해 되돌렸다. 원인은 `reconcileForStore`가 저장을 건드리지 않는 한 preference 는 계속 null 로 남는다는 걸 놓치고, "값이 없어서 기본으로 보이는 상태"와 "사용자가 기본을 골라서 저장한 상태"를 같은 조건(`== appfitDefault`)으로 뭉뚱그린 것.

**How to apply**: 빌드 축(`BuildBrand`)이 런타임 브랜드 선택에 프리시드/기본값을 제공할 때는 항상 "저장 슬롯이 비어있는가"(`prefs.getX() == null`)로 판단한다. 해석 후 값이 특정 상수와 같은지로 판단하면, 그 상수를 사용자가 의도적으로 고른 경우와 구분할 수 없다. 유사 패턴(예: 향후 다른 preference 에 flavor 프리시드를 추가할 때) 재발 방지 체크리스트: "이 조건이 '아무도 고르지 않음'과 '명시적으로 이 값을 고름'을 구별하는가?"

**단, 이 규칙은 "런타임 설정값"에만 적용된다 — "아티팩트 정체성 요소"는 예외.** 사용자가 최종적으로 확정한 요구사항은: 앱 전체 색상 테마(`AppStyles.activeBrand`, main.dart 프리시드)는 위 규칙대로 명시적 선택을 존중하되, **로그인 화면 로고 하나만큼은** 선택된 테마와 무관하게 `BuildBrand.isMammoth`면 항상 매머드로 고정한다(`lib/screens/login_screen.dart` `_buildHeroPanel()` — `BrandLogo` 대신 직접 `Image.asset` 분기, 화이트리스트 등록 완료). 논리: 로그인 로고는 런처 아이콘/이름과 동급으로 "이 APK가 무슨 아티팩트인가"를 나타내는 요소지 매장/사용자가 고르는 브랜드 취향이 아니다. 드로어 헤더 로고(`drawer_menu.dart`)도 처음부터 이 방식(activeBrand 무관, `BuildBrand.isMammoth` 직접 분기)으로 구현되어 있었다. 새 "아티팩트 정체성" 요소를 추가할 때는 이 예외 목록에 포함되는지 먼저 물을 것: "이게 어느 매장이든/어느 테마를 고르든 이 APK 자체를 나타내는 표식인가?" — 맞으면 강제, 아니면 설정값 규칙(null 일 때만 개입) 적용.
