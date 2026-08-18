---
name: project_mammoth_dedicated_build
description: "맘모스(MHST/MMTH) 전용 빌드 + 공통/브랜드 2-티어 배포 체계 — 설계 확정·커밋, 구현 미착수"
metadata: 
  node_type: memory
  type: project
  originSessionId: 189e1561-e4e8-4434-b4f8-17a8e4dc7c9d
  modified: 2026-08-18T04:47:41.201Z
---

2026-08-18, 맘모스커피에 전용 앱 이름·아이콘을 입힌 빌드를 만들고 공통 빌드와 구분해 배포하는 체계를 설계했다. **설계 문서만 커밋(`605ac09`, 브랜치 `feat/mammoth-dedicated-build`, 경로 `.claude/plans/mammoth-dedicated-build.md`). 구현 미착수.** Windows 빌드 PC 에서 Phase C 를 이어받으려고 레포에 올렸다.

**확정 결정**: 별도 패키지 `co.kr.waldlust.order.receive.appfit.mammoth` / 식별자는 전부 `mammoth` 로 통일(`BrandKey.mhst`→`mammoth` 개명 포함) / Android+Windows 둘 다 / 맘모스 전용 채널 1세트 신설(Android OTA + Windows ZIP) / 롤아웃 시점 미정.

**Why (동일 패키지 안이 왜 안 되는가)**: Sunmi App Store 리스팅은 **패키지당 1개**인데, 설치 가이드상 **모든** Sunmi 매장(TPCP/MATA 포함)이 그 리스팅에서 최초 설치한다. 같은 패키지로는 "맘모스 매장만 맘모스 아이콘"을 구조적으로 보장할 수 없다 — **런처 아이콘은 앱 실행 전에 이미 보이므로 런타임 게이팅으로 막을 수 없다.** 그리고 맘모스는 출시 전이라 패키지 분리 비용이 지금이 최저다(매장 수에 비례해 커짐).

**How to apply:**
- **채널 불변식**: 채널은 브랜드가 아니라 **아티팩트**에 종속. Tier 1 아티팩트마다 정확히 채널 1세트, **아티팩트 없이 채널만 늘리지 않는다**. 채널명은 슬러그에서 규칙 파생(`appfit_order_agent_<brand>_release.*`). 이게 `docs/RELEASE.md` 의 "브랜드별 OTA 채널 증설 금지"를 대체하는 규칙 — 금지의 취지를 더 강하게 보존한다.
- **빌드 축의 사정거리**: applicationId·런처 label/icon·Windows BINARY_NAME/ProductName/mutex/Inno GUID·OTA 채널 URL·로그인 전 기본 브랜드까지만. **서버 환경·BrandFeature·프린터/주문 로직·i18n 분기는 금지** — 전부 `brand_registry` 런타임 정본. 2026-07 변형 폐기의 교훈은 "브랜드로 빌드를 나누지 마라"가 아니라 "빌드 축이 로직까지 번지게 두지 마라"였다. 참조 지점 화이트리스트 테스트로 고정한다.
- **Tier 1 승격 조건 3개(AND)**: 자체 스토어 리스팅/유통 경로 요구 + 함대가 그 브랜드 기기 전용(혼재 없음) + 런처 이름·아이콘이 계약·운영 요구사항. `/add-brand` 마지막에 이 3문항을 강제로 묻게 한다(기본 Tier 0).
- 빌드 브랜드 상수는 **`lib/config/build_brand.dart` 를 새로 만든다**. `app_env.dart` 에 넣으면 안 된다 — gitignored 머신별 파일이라 다른 빌드 머신 stale 사본에서 컴파일이 깨진다([[project_app_env_gitignored_variant]]).
- Android product flavor 도입 시 **`--flavor` 없는 빌드는 실패한다** — 스크립트·`.vscode/launch.json`·문서 전부에 `--flavor common` 명시 필요([[project_dual_variant_build]] 시절과 동일).

**Phase A 는 독립 선행이고 출시 차단급이다**: `MMTH` 프리픽스가 코드베이스 어디에도 없다. live 프리픽스가 MMTH 인데 `brand_registry` 는 MHST 하나만 알아서, MMTH 매장이 로그인하면 `resolveOrNull` null → 사운드그래프 전송 OFF·업데이트 정책 미적용·테마 미적용, `resolve()` 폴백 때문에 **라벨·영수증에 tokyoplatz 로고가 찍힌다.** 사용자 확인: **MHST=스테이징 프리픽스, MMTH=live 프리픽스, 둘이 한 브랜드.** 현재 레지스트리의 MHST→live 매핑은 틀렸고 MHST→staging 으로 가야 한다. 그래서 `storeIdPrefix`+`serverEnvironment` 두 필드를 `prefixEnvironments` Map 하나로 대체하는 구조 변경이 따라온다.

관련: [[project_variant_rename_japan_korea]](변형 폐기 이력), [[project_update_channel_policy_mhst_sunmi]](스토어/OTA 정책), [[project_mhst_brand_image_2026_08]](맘모스 자산), [[feedback_concurrent_deploy_version_race]](배포 직전 pubspec 재확인).
