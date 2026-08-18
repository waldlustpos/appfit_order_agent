---
name: project_mammoth_dedicated_build
description: "매머드(MMTH/MHST) 전용 빌드 + 공통/브랜드 2-티어 배포 체계 — Phase A~E 전부 구현·커밋 완료"
metadata:
  node_type: memory
  type: project
  originSessionId: 189e1561-e4e8-4434-b4f8-17a8e4dc7c9d
  modified: 2026-08-18T12:47:18.200Z
---

매머드커피에 전용 앱 이름·아이콘을 입힌 빌드를 만들고 공통 빌드와 구분해 배포하는 체계. 설계는 `.claude/plans/mammoth-dedicated-build.md`(커밋 `605ac09`).

**진행 상태 (2026-08-18)**: 브랜치 `feat/mammoth-dedicated-build`, **Phase A~E 전부 구현·커밋 완료**(`57977b9`→`4ad4d2a`→`53e9fb5`→`71259d8`). Android 실기기 병존 설치 확인 완료. Windows 는 common/mammoth 양쪽 실제 인스톨러 빌드로 검증(exe/ProductName/아이콘 분리, sentinel 전환 확인) — **Windows 인스톨러 실제 설치(병존)는 미검증**, 다음 세션 확인 대상.

**확정 결정**: 별도 패키지 `co.kr.waldlust.order.receive.appfit.mammoth` / 식별자 전부 `mammoth`(`BrandKey.mhst`→`mammoth` 개명 완료) / 런처·인스톨러 표시명 `매머드오더 에이전트`(Android/Windows 통일) / 아이콘 원본 `~/Downloads/mammoth_icon.png`(4500×4500, 전체 록업·원본색 그대로) / 롤아웃 시점 미정.

**Why (동일 패키지 안이 왜 안 되는가)**: Sunmi App Store 리스팅은 **패키지당 1개**인데 **모든** Sunmi 매장(TPCP/MATA 포함)이 그 리스팅에서 최초 설치한다. **런처 아이콘은 앱 실행 전에 보이므로 런타임 게이팅으로 막을 수 없다.**

**How to apply:**
- **채널 불변식**: 채널은 브랜드가 아니라 **아티팩트**에 종속. Tier 1 아티팩트마다 정확히 채널 1세트, **아티팩트 없이 채널만 늘리지 않는다**. 채널명은 슬러그에서 규칙 파생(`appfit_order_agent_<brand>_release.*`, `_<brand>_windows.*`).
- **빌드 축의 사정거리**: applicationId·런처 label/icon·OTA 채널 URL·Windows BINARY_NAME/mutex/Inno GUID 까지만. **서버 환경·BrandFeature·프린터/주문 로직·i18n 분기는 금지.** `test/config/build_brand_scope_test.dart` 가 `BuildBrand` 참조 파일을 화이트리스트로 고정한다 — 컴파일러가 못 잡으므로 이게 유일한 장치. 최종 허용 목록: `build_brand.dart`(정의)·`ota_config.dart`/`update_config.dart`(OTA 채널)·`main.dart`(로그인 전 테마 프리시드, 저장 슬롯 빈 경우만)·`drawer_menu.dart`·`login_screen.dart`(로그인 로고 — 둘 다 "아티팩트 정체성" 요소로 테마 선택과 무관하게 강제).
- **`--flavor`/`-Brand` 와 `--dart-define=APPFIT_BRAND`(+ Windows `$env:APPFIT_BRAND`)는 반드시 같은 값**. 어긋나면 매머드 아티팩트가 공통 채널을 보게 됨. 스크립트는 하나의 브랜드 변수로 전부 구동한다. **Android 플레이버 도입 후 `--flavor` 없는 빌드는 실패**하며 `.vscode/launch.json` 은 **gitignored 라 머신마다 직접 고쳐야 한다**(공통 안내는 docs/BUILD.md·CLAUDE.md 에 커밋됨).
- **Windows 브랜드 전환 캐시 정리는 부분 wipe 만**: `build\windows` 전체 삭제는(특히 `_deps` 재fetch 를 동반한 완전 콜드 configure) 이 머신의 CMake+VS2022 조합에서 `CMAKE_GENERATOR_PLATFORM` 기록이 빈 문자열이 되고 "generator platform: x64 does not match previously" 에러로 이어지는 것을 실제로 재현했다. `CMakeCache.txt`+`CMakeFiles` 만 정밀 삭제 + Release 폴더의 이전 브랜드 exe 만 별도 삭제로 해결(부분 wipe 는 반복 재현에서 매번 정상).
- **아이콘 파이프라인 함정 3개**: (1) 대형 여백 캔버스는 bbox 크롭 선행 필수. (2) `flutter_launcher_icons` 가 생성하는 `ic_launcher.xml` 이 전경에 **`inset="16%"` 를 한 번 더** 먹인다 — 안전영역을 또 빼면 이중 축소로 로고가 점처럼 작아진다(`kAdaptiveScale=0.80` 이 그 보정값). (3) Windows `.ico` 는 별도 파이프라인(`gen_korea_icon.dart` 패턴 재사용, 256px 인코딩)이 필요 — flutter_launcher_icons 는 Windows 를 안 건드린다. 생성 직후 **`git status` 로 `android/app/src/main/res/mipmap-*` 무오염 확인 필수**(덮이면 전 함대 회귀).
- **자산 방향 의심은 검증된 자산과 대조해 판정**. 원본 미리보기에서 한글 워드마크가 좌우 반전돼 보였으나, 컵 심볼의 점 위치·대각선을 `receipt_logo.png` 와 대조해 **정상임을 확인**했다. 육안 글자 판독은 이 기하학 폰트에서 신뢰할 수 없다.

**Phase A 는 출시 차단급이었다**: `MMTH` 가 코드에 없어 MMTH 매장 로그인 시 `resolveOrNull` null → 사운드그래프 OFF·정책 미적용, `resolve()` 폴백으로 **라벨·영수증에 tokyoplatz 로고**. **MHST=스테이징, MMTH=live, 둘이 한 브랜드.** `storeIdPrefix`+`serverEnvironment` 를 **`prefixEnvironments` Map** 하나로 대체해 한 브랜드가 프리픽스를 여러 개 갖게 했다(첫 항목이 대표).

**의도적으로 남긴 비대칭**: `_resolveEnvironmentForStoreId` 는 live/japanLive 세션에서만 동작한다. live 에서 MHST 입력 → staging 전환은 되지만, staging 세션에서 MMTH 입력 → live 복귀는 **안 된다**(개발자가 고른 staging 을 앱이 뺏지 않기 위함). 로그인 화면 서버 선택으로 수동 복귀.

**Sentry 라우팅**: MHST 라우트를 `MMTH`(environment=live)로 **교체**했다. MHST 는 라우트를 두지 않아 catch-all 로 가는데, 이게 원래 `environment: live` 로 좁혔던 의도("사내 QA 노이즈를 브랜드 채널에서 뺀다")를 그대로 실현한다. **`routes.json` 만 수정했고 Sentry 반영 스크립트는 미실행.**

**오설치 안내는 아예 없앴다(2026-08-18)**: `BrandInstallBanner`·`brandInstallMismatchProvider`·`BrandInstallMismatch`·i18n `common.brand_install.*` 전부 삭제. 원칙 = **로그인에 제약을 두지 않는다** — 어느 아티팩트로 어느 브랜드 매장에 로그인하든 로직은 완전히 동일하고, 전용 빌드가 다른 것은 초기 테마·앱 이름·아이콘 같은 화면 요소뿐이다. 어긋남의 실제 증상이 "런처 아이콘·이름이 다름"뿐이라 안내조차 소음이었다. 이 삭제로 `brand_provider.dart` 는 `BuildBrand` 를 더 이상 참조하지 않아 화이트리스트에서도 빠졌다.

**"런타임 설정값" vs "아티팩트 정체성" 구분** — 상세: [[feedback_flavor_preseed_vs_explicit_choice]]. `BuildBrand` 가 프리시드/기본값을 제공할 때는 "저장 슬롯이 비어있는가"로 판단해야지 "해석된 값==특정 상수"로 판단하면 사용자의 명시적 선택(예: 설정에서 기본 테마 선택)과 구별할 수 없다(main.dart 에서 실측한 회귀). 단 로그인 로고·드로어 로고처럼 "이 APK 가 무슨 아티팩트인가"를 나타내는 요소는 예외 — 테마 선택과 무관하게 `BuildBrand.isMammoth` 로 항상 강제한다.

**Phase D 에서 발견한 실제 버그**: `/add-brand` 커맨드의 STEP 2-1 템플릿이 Phase A 이후에도 옛 `storeIdPrefix:`/`serverEnvironment:` named parameter 를 그대로 쓰고 있어서, **그 시점 이후 `/add-brand` 를 실행하면 컴파일이 깨지는 상태**였다. `prefixEnvironments: {...}` 로 수정 완료(`71259d8`). 교훈: 런타임 구조를 바꾸는 리팩터는 그 구조를 생성하는 슬래시 명령어 템플릿까지 같은 시점에 훑어야 한다.

**Tier 1 승격 게이트**: `/add-brand` STEP 0-B 에 3문항 신설(자체 유통 경로/전용 함대/계약상 요구, 기본 전부 아니오). 셋 다 예일 때만 안내만 하고 패키지 분리는 범위 밖(매머드 사례를 참고해 사람이 별도 진행).

관련: [[project_variant_rename_japan_korea]](변형 폐기 이력), [[project_update_channel_policy_mhst_sunmi]](스토어/OTA 정책), [[project_mhst_brand_image_2026_08]](매머드 자산), [[reference_brand_asset_large_canvas_bbox_crop]](bbox 크롭), [[project_app_env_gitignored_variant]](gitignored 로컬 파일 함정), [[feedback_concurrent_deploy_version_race]](배포 직전 pubspec 재확인).

**로그인 화면 서버 선택 — 매머드는 숨김 + 완전 양방향 자동전환 (같은 날)**: 릴리즈 매머드 아티팩트는 우상단 서버 배지(`_buildEnvBadge`)를 숨긴다(`AppEnv.showInternalUi`일 때만 유지 — 개발 빌드 QA 용). 배지를 숨기면 기존의 "live→staging만 자동, staging→live는 수동" 비대칭이 그대로 남아 매장이 MHST 한 번 로그인하면 재설치 전까지 못 돌아오는 문제가 생기므로, `_resolveEnvironmentForStoreId`의 `_selectedEnv != 'live' && != 'japanLive'` 조기 return 가드를 `BuildBrand.isMammoth`일 때 우회하도록 수정 — 매머드 빌드는 현재 서버가 뭐든 매장ID 프리픽스로 항상 전환(MHST→staging, MMTH→live). 이 비대칭 보호는 원래 "개발자가 고른 staging을 앱이 뺏지 않기 위함"이었는데, 매머드 전용 아티팩트는 개발자가 안 쓰므로(매장 직원 전용, 서버 선택 UI 자체가 없음) 보호 이유가 사라진다는 논리. 화이트리스트 파일 추가 없음(login_screen.dart 이미 등록됨). analyze/test(515건) 통과, 실기기 미검증.

**mammoth OTA 배포 완료 (같은 날)**: 버전 **3.0.0+184**로 Android+Windows 양쪽 첫 배포 완료 — Android `appfit_order_agent_mammoth_release`(패키지 검증 통과), Windows `appfit_order_agent_mammoth_windows`(exe `appfit_order_agent_mammoth.exe`). 둘 다 이전에는 404(빈 채널)였던 첫 업로드. 버전 계열은 common(3.0.3계)과 별개로 **mammoth 는 3.0.0부터 시작**(사용자 확정, 의도적). 실제 매장 유통 정본은 Sunmi App Store — 이 OTA 배포는 비-Sunmi/수동체크 안전망일 뿐, `/store-upload mammoth` 미실행.

**3.0.0+185 전 경로 배포 완료 (2026-08-18)**: Android OTA(version=185, 패키지 검증 통과) + Windows OTA(version=185) + **Sunmi App Store 매머드 전용 리스팅 업로드 완료**(리스팅은 이미 등록돼 있었음 — 이전 메모의 "MMTH 미등록=출시 차단" 은 해소됨, gray=소규모 canary) + Windows 설치파일 `dist\AppfitOrderAgentMammoth-Setup-3.0.0.exe`(15.95MB) 빌드. 스토어 업로드 이력은 `~/Documents/!Project Files/appfit_order_agent/store_uploads.log` 가 **유일한 기록**(OTA 와 달리 자동 생성 이력 없음). 설치파일은 빌드만 하고 **서버 업로드·클린PC 설치 검증 미실시**. 배포 시점 코드 변경분(login_screen.dart 서버배지 숨김 + 양방향 자동전환 등) **미커밋** — 배포 산출물과 커밋 이력이 어긋나 있음.

## 다음 세션 시작점

- Windows 인스톨러 실제 설치 검증(common+mammoth 병존, 제어판 항목 분리, mutex 독립, `%APPDATA%` 샌드박스 분리)
- Sentry `routes.json` 반영 스크립트 실행(`sentry_alerts.py apply`) — 아직 정본 파일만 수정, 미반영
- Sunmi App Store 매머드 전용 리스팅 등록(콘솔 수동 작업, 롤아웃 임계 경로일 수 있음)
- 로그인 화면 매머드 로고 배경 조합(로고=매머드, 배경=기본 핑크 그라데이션 섞임 가능) 실기기 시각 확인
- 드로어 로고 폭(975×640 워드마크를 36px 높이로 넣으면 실사용 폭 ~55px) 좁은 드로어에서 답답해 보이는지 확인 — 답답하면 정사각 심볼 자산(`app_icon_mammoth_fg.png`)로 교체 검토
