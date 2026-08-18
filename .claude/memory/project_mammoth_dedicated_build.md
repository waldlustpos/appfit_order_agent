---
name: project_mammoth_dedicated_build
description: "맘모스(MMTH/MHST) 전용 빌드 + 공통/브랜드 2-티어 배포 체계 — Phase A+B 구현·커밋 완료, C~E 미착수"
metadata:
  node_type: memory
  type: project
  originSessionId: 189e1561-e4e8-4434-b4f8-17a8e4dc7c9d
  modified: 2026-08-18T05:36:17.391Z
---

맘모스커피에 전용 앱 이름·아이콘을 입힌 빌드를 만들고 공통 빌드와 구분해 배포하는 체계. 설계는 `.claude/plans/mammoth-dedicated-build.md`(커밋 `605ac09`).

**진행 상태 (2026-08-18)**: 브랜치 `feat/mammoth-dedicated-build`, 커밋 **`57977b9`** 에 **Phase A + B 구현 완료**(analyze 17건·에러 0 / test 513건 / 양쪽 APK aapt 검증). **Phase C(Windows)·D(슬래시 명령어)·E(문서 잔여) 미착수.** 실기기 병존 설치 확인 미실시.

**확정 결정**: 별도 패키지 `co.kr.waldlust.order.receive.appfit.mammoth` / 식별자 전부 `mammoth`(`BrandKey.mhst`→`mammoth` 개명 완료) / 런처 이름 `매머드오더 에이전트` / 아이콘 원본 `~/Downloads/mammoth_icon.png`(4500×4500, 전체 록업·원본색 그대로) / 롤아웃 시점 미정.

**Why (동일 패키지 안이 왜 안 되는가)**: Sunmi App Store 리스팅은 **패키지당 1개**인데 **모든** Sunmi 매장(TPCP/MATA 포함)이 그 리스팅에서 최초 설치한다. **런처 아이콘은 앱 실행 전에 보이므로 런타임 게이팅으로 막을 수 없다.**

**How to apply:**
- **채널 불변식**: 채널은 브랜드가 아니라 **아티팩트**에 종속. Tier 1 아티팩트마다 정확히 채널 1세트, **아티팩트 없이 채널만 늘리지 않는다**. 채널명은 슬러그에서 규칙 파생(`appfit_order_agent_<brand>_release.*`).
- **빌드 축의 사정거리**: applicationId·런처 label/icon·OTA 채널 URL·(Windows) BINARY_NAME/mutex/Inno GUID 까지만. **서버 환경·BrandFeature·프린터/주문 로직·i18n 분기는 금지.** `test/config/build_brand_scope_test.dart` 가 `BuildBrand` 참조 파일을 화이트리스트로 고정한다 — 컴파일러가 못 잡으므로 이게 유일한 장치. 현재 허용: `build_brand.dart`·`ota_config.dart`·`brand_provider.dart`.
- **`--flavor` 와 `--dart-define=APPFIT_BRAND` 는 반드시 같은 값**. 전자가 패키지를, 후자가 OTA 채널을 정해서 어긋나면 맘모스 패키지가 공통 채널을 폴링→설치 실패. 스크립트는 하나의 `BRAND` 변수로 둘을 구동한다. **플레이버 도입 후 `--flavor` 없는 빌드는 실패**하며 `.vscode/launch.json` 은 **gitignored 라 머신마다 직접 고쳐야 한다**(공통 안내는 docs/BUILD.md·CLAUDE.md 에 커밋됨).
- **아이콘 파이프라인 함정 2개**: (1) 대형 여백 캔버스는 bbox 크롭 선행 필수. (2) `flutter_launcher_icons` 가 생성하는 `ic_launcher.xml` 이 전경에 **`inset="16%"` 를 한 번 더** 먹인다 — 안전영역을 또 빼면 이중 축소로 로고가 점처럼 작아진다(`kAdaptiveScale=0.80` 이 그 보정값). 생성 직후 **`git status` 로 `android/app/src/main/res/mipmap-*` 무오염 확인 필수**(덮이면 전 함대 회귀).
- **자산 방향 의심은 검증된 자산과 대조해 판정**. 원본 미리보기에서 한글 워드마크가 좌우 반전돼 보였으나, 컵 심볼의 점 위치·대각선을 `receipt_logo.png` 와 대조해 **정상임을 확인**했다. 육안 글자 판독은 이 기하학 폰트에서 신뢰할 수 없다.

**Phase A 는 출시 차단급이었다**: `MMTH` 가 코드에 없어 MMTH 매장 로그인 시 `resolveOrNull` null → 사운드그래프 OFF·정책 미적용, `resolve()` 폴백으로 **라벨·영수증에 tokyoplatz 로고**. **MHST=스테이징, MMTH=live, 둘이 한 브랜드.** `storeIdPrefix`+`serverEnvironment` 를 **`prefixEnvironments` Map** 하나로 대체해 한 브랜드가 프리픽스를 여러 개 갖게 했다(첫 항목이 대표).

**의도적으로 남긴 비대칭**: `_resolveEnvironmentForStoreId` 는 live/japanLive 세션에서만 동작한다. live 에서 MHST 입력 → staging 전환은 되지만, staging 세션에서 MMTH 입력 → live 복귀는 **안 된다**(개발자가 고른 staging 을 앱이 뺏지 않기 위함). 로그인 화면 서버 선택으로 수동 복귀. 코드 주석에 명시됨.

**Sentry 라우팅**: MHST 라우트를 `MMTH`(environment=live)로 **교체**했다. MHST 는 라우트를 두지 않아 catch-all 로 가는데, 이게 원래 `environment: live` 로 좁혔던 의도("사내 QA 노이즈를 브랜드 채널에서 뺀다")를 그대로 실현한다 — 이제 MHST 가 곧 그 QA 프리픽스다. Slack 채널명 `appfit-alert-mhst` 는 Slack 측 자산이라 유지. **`routes.json` 만 수정했고 Sentry 반영 스크립트는 미실행.**

**오설치 안전망은 차단하지 않는다**: 브랜드 동작이 100% 런타임이라 어느 조합이든 기능은 정상 — 실패 모드가 "깨짐"이 아니라 "런처 아이콘·이름이 다름"이다. 그래서 배너 안내만.

관련: [[project_variant_rename_japan_korea]](변형 폐기 이력), [[project_update_channel_policy_mhst_sunmi]](스토어/OTA 정책), [[project_mhst_brand_image_2026_08]](맘모스 자산), [[reference_brand_asset_large_canvas_bbox_crop]](bbox 크롭), [[project_app_env_gitignored_variant]](gitignored 로컬 파일 함정), [[feedback_concurrent_deploy_version_race]](배포 직전 pubspec 재확인).
