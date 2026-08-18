# 매머드(MHST/MMTH) 전용 빌드 + 공통/브랜드 2-티어 배포 체계

## Context

매머드커피 브랜드에 **전용 앱 이름·아이콘**을 입힌 빌드를 만들고, 그 결과를 공통 빌드와 구분해 배포·운영해야 한다. 지금 손대는 이유는 셋이다.

1. **매머드는 아직 서비스 출시 전**이다. 패키지 분리는 매장 수에 비례해 비용이 커지는 결정이라, 지금이 유일하게 싼 시점이다.
2. **`MMTH` 프리픽스가 코드베이스 어디에도 없다.** [brand_registry.dart:142](../../lib/utils/brand_registry.dart) 는 `MHST` 하나만 알고 있어서, live 프리픽스인 MMTH 매장이 로그인하면 `resolveOrNull` 이 null → 사운드그래프 전송 OFF, 업데이트 정책 미적용, 테마 미적용, 그리고 `resolve()` 폴백 때문에 **라벨·영수증에 tokyoplatz 로고가 찍힌다.** 전용 빌드와 무관하게 출시를 막는 결함이다.
3. 현재 정책 문서([docs/RELEASE.md](../../docs/RELEASE.md))는 "MHST 전용 패키지명/전용 APK 생성"을 금지 항목으로 못박고 있다. 2026-07-09 변형 폐기 결정의 산물인데, 그 결정의 진짜 교훈은 "브랜드로 빌드를 나누지 마라"가 아니라 **"빌드 축이 서버·OTA·UI 로직까지 번지게 두지 마라"** 였다. 이번엔 빌드 축의 사정거리를 OS 셸 아이덴티티로 못박아 그 재발을 막는다.

목표 상태: 코드는 단일 main, 브랜드 로직은 100% 런타임(`brand_registry`), 빌드는 공통 1 + 전용 N, 배포 채널은 아티팩트마다 정확히 하나.

### 확정된 결정 (사용자 확인 완료)

| 항목 | 결정 |
| --- | --- |
| 패키지 | 별도 패키지 `co.kr.waldlust.order.receive.appfit.mammoth` |
| 식별자 | 전부 `mammoth` 로 통일 (`BrandKey.mhst` → `BrandKey.mammoth` 개명 포함) |
| 프리픽스/환경 | `MMTH` → live, `MHST` → **staging** (현재는 MHST→live 로 잘못 매핑) |
| 플랫폼 | Android + Windows |
| 브랜딩 범위 | 런처 이름·아이콘, Windows exe/인스톨러 이름, 앱 내부 표기 |
| 업데이트 채널 | **매머드 전용 채널 1세트 신설** — Android OTA APK/JSON + Windows ZIP/JSON. Android 도 스토어와 OTA 두 경로가 병존한다 |
| 롤아웃 시점 | 미정 — 이번엔 골격·문서까지 |

---

## 결론: 2-티어 아티팩트 모델

- **Tier 0 — 공통 아티팩트 (기본값).** 모든 브랜드의 기본. 브랜드 차이는 전부 런타임.
- **Tier 1 — 전용 아티팩트 (예외, opt-in).** 같은 코드·같은 버전, **OS 셸 아이덴티티만** 다르다.

**Tier 1 승격 조건 — 셋 다 충족해야 한다:**
1. 그 브랜드가 자체 App Store 리스팅이나 자체 유통 경로를 요구한다.
2. 그 함대가 해당 브랜드 기기로만 구성된다(타 브랜드와 혼재하지 않는다).
3. 런처 이름·아이콘이 계약·운영상 요구사항이다.

매머드는 셋 다 충족한다. 이 조건표가 곧 무분별한 증식을 막는 장치이며, `/add-brand` 마지막 단계에서 이 3문항을 강제로 묻게 한다(기본은 Tier 0).

**채널 불변식 — 채널은 브랜드가 아니라 아티팩트에 종속된다.** 전용 아티팩트는 자기 패키지·exe명 때문에 공통 채널을 물리적으로 쓸 수 없으므로(받아도 패키지 불일치로 설치 실패), Tier 1 아티팩트마다 **정확히 채널 1세트**(Android OTA APK+JSON / Windows ZIP+JSON)를 부여한다. 뒤집으면 이게 증식 방지선이다 — **아티팩트 없이 채널만 늘리지 않는다.** 채널 수는 항상 아티팩트 수와 같다.

**빌드 축이 건드려도 되는 것 (전부):** applicationId, 런처 label/icon, Windows BINARY_NAME·ProductName·mutex·Inno GUID·설치 경로, **인앱 OTA 채널 URL**, 로그인 전 기본 브랜드 프리시드.

**빌드 축이 절대 건드리면 안 되는 것:** 서버 환경, `BrandFeature` 게이팅, 프린터·주문 로직, i18n 분기. 이건 전부 `brand_registry` 런타임 정본으로 남는다. 위반을 컴파일 타임에 잡을 수는 없으므로 **참조 지점 화이트리스트 테스트**로 고정한다.

**왜 별도 패키지인가 (동일 패키지 안이 안 되는 이유):** Sunmi App Store 리스팅은 패키지당 1개인데, [설치 가이드](../../docs/guide/Sunmi-appfit-agent-install-guide.html) 상 **모든** Sunmi 매장(TPCP/MATA 포함)이 그 리스팅에서 최초 설치한다. 같은 패키지로는 "매머드 매장만 매머드 아이콘"을 구조적으로 보장할 방법이 없다 — 런처 아이콘은 앱을 켜기 전에 이미 보이므로 런타임 게이팅으로 막을 수 없다.

---

## Phase A — 매머드 프리픽스 정본화 (선행·독립)

전용 빌드와 무관하게 단독으로 배포 가능하며, **MMTH live 오픈 전 필수**다. 먼저 끝낸다.

**[lib/utils/brand_registry.dart](../../lib/utils/brand_registry.dart)**
- `storeIdPrefix`(String) + `serverEnvironment`(String) 두 필드를 `prefixEnvironments`(`Map<String, String>`) 하나로 대체. 첫 항목이 대표 프리픽스.
  ```dart
  BrandKey.mammoth: BrandMeta(
    key: BrandKey.mammoth,
    prefixEnvironments: {'MMTH': 'live', 'MHST': 'staging'},
    assetFolder: 'mammoth',
    ...
  ```
  나머지 4개 브랜드는 단일 항목으로 기계적 치환: `{'TPCP': 'japanLive'}`, `{'MATA': 'live'}`, `{'PAIK': 'japanLive'}`, `{'TLJP': 'japanLive'}`.
- 호환 게터 `String get storeIdPrefix => prefixEnvironments.keys.first;` 유지 (로그 문자열이 쓰고 있음).
- `String environmentFor(String storeId)` 신설. `resolveOrNull` 은 모든 prefix 를 순회한다. 6개 prefix 는 상호 접두 관계가 없으므로 순회 순서 무관 — 기존 주석의 전제 그대로다.
- `BrandKey.mhst` → `BrandKey.mammoth` 개명.

**호출부 (기계적, 4곳)**
- [login_screen.dart:1282-1287](../../lib/screens/login_screen.dart) `_maybeSwitchEnvironmentForStore` — `brand.serverEnvironment` → `brand.environmentFor(storeId)`
- [preference_service.dart:283](../../lib/services/preference_service.dart) — 같은 치환
- [preference_service.dart:1013](../../lib/services/preference_service.dart) `isMHSTStoreId`/`isMammothStore` → `isMammothStoreId` 로 정리
- [qr_payload_strategy.dart:103](../../lib/services/label_printer/qr_payload_strategy.dart) — `case BrandKey.mhst:` → `mammoth` (exhaustive switch라 컴파일러가 누락을 잡아준다)

**[sentry_alerts/routes.json](../../sentry_alerts/routes.json)** — MHST 라우트에 `MMTH` 값 추가. MHST 가 staging 으로 옮겨가므로 **환경 스코프(현재 KR live 한정)를 재확인**한다 — 좁힌 채로 두면 staging 이벤트가 스필오버로 새거나 무음 폐기된다.

**테스트** — `test/utils/brand_registry_test.dart` 에 MMTH→live / MHST→staging / 두 프리픽스가 같은 `BrandKey`·같은 자산으로 해석되는지 케이스 추가.

---

## Phase B — 브랜드 빌드 축 (Dart + Android)

**신규 [lib/config/build_brand.dart]** — 커밋되는 파일로 새로 만든다. **`app_env.dart` 에 넣지 않는다**: 그 파일은 머신별 gitignored 로컬 파일이라, 멤버를 추가하면 다른 빌드 머신의 stale 사본에서 컴파일이 깨진다(과거 실사고).
```dart
class BuildBrand {
  static const String slug = String.fromEnvironment('APPFIT_BRAND', defaultValue: 'common');
  static bool get isMammoth => slug == 'mammoth';
}
```

**[android/app/build.gradle.kts](../../android/app/build.gradle.kts)**
- `flavorDimensions += "brand"`, `productFlavors { create("common") {}; create("mammoth") { applicationIdSuffix = ".mammoth" } }`
- `common` 은 suffix 없음 → 기존 함대의 applicationId 불변.
- ⚠️ **플레이버 도입 후 `--flavor` 없는 빌드는 실패한다.** 모든 빌드 스크립트, `.vscode/launch.json` 전 구성, 문서에 `--flavor common` 을 명시해야 한다. (이 강제성은 아티팩트가 2개가 된 이상 오히려 안전장치다.)
- 스테일 정리: `android/app/commonBrand/`, `android/app/kokonut/` — 구 플레이버 산출물 잔재.

**리소스 오버레이** — `android/app/src/mammoth/res/values/strings.xml` 에 `app_name` 만. 나머지는 `main` 상속.

**런처 아이콘** — `flutter_launcher_icons-mammoth.yaml` 를 추가하면 `android/app/src/mammoth/res/` 로 생성된다. 원본 PNG 는 [tool/gen_korea_icon.dart](../../tool/gen_korea_icon.dart) 를 본떠 `tool/gen_brand_icon.dart` 로 만든다 — 배경은 매머드 테마색(`0xFF5B443B`~`0xFFC7A79B` 그라데이션, [brand_theme.dart:18-30](../../lib/constants/brand_theme.dart)), 전경은 흰색 매머드 심볼. 대형 캔버스 원본은 표준 파이프라인 전에 alpha bbox 크롭이 필요하다([docs/BRAND_ASSETS.md](../../docs/BRAND_ASSETS.md) §4.1). **플레이버 출력 경로는 1회 실행으로 실제 확인**하고, 미동작 시 mipmap 수동 배치로 폴백한다.

**매머드 Android OTA 채널 (신설)** — 매머드 패키지가 공통 `_release` APK 를 받으면 **패키지 불일치로 설치가 실패**한다(레거시 무접미 채널 동결과 정확히 같은 원리). 끄는 게 아니라 **자기 채널로 돌린다** — 매머드 함대에도 스토어 경로와 OTA 경로가 둘 다 존재하기 때문이다.
- [ota_config.dart](../../lib/config/ota_config.dart) 의 `versionUrl`/`downloadUrl` 을 `BuildBrand` 기준 **컴파일 타임 const 분기**로 바꾼다. 과거 standalone 변형이 쓰던 것과 같은 형태다.
  - 공통: `appfit_order_agent_release.apk` / `_release_version.json` (불변)
  - 매머드: `appfit_order_agent_mammoth_release.apk` / `_mammoth_release_version.json`
- [login_screen.dart:287](../../lib/screens/login_screen.dart) `_checkForUpdate` 와 [settings_screen.dart:252](../../lib/screens/settings_screen.dart) `_checkUpdateFromSettings` 는 코드 변경 없이 올바른 채널을 보게 된다. **수동 체크 경로에 브랜드 게이팅이 없는 현재 상태가 그대로 정답이 된다** — 채널이 패키지와 일치하므로.
- 자동 체크 ON/OFF 판정은 기존 런타임 규칙(`BrandFeature.sunmiAppStoreUpdate` + Sunmi 여부, [login_screen.dart:498](../../lib/screens/login_screen.dart))을 **그대로 유지**한다. 이제 채널이 맞으므로 이 규칙이 의도대로 작동한다: 매머드+Sunmi 는 스토어로, 매머드 비-Sunmi 는 매머드 OTA 채널로.
- 레거시 무접미 채널 동결은 불변 — 어떤 브랜드도 그 이름으로 올리지 않는다.

**오설치 안전망** — 로그인 성공 직후 빌드 브랜드와 매장 브랜드를 비교해 안내한다. 차단하지 않는다(런타임 브랜드 시스템이 살아 있어 기능은 정상 동작하므로, 실패 모드가 "깨짐"이 아니라 "일반 아이콘 + 안내"가 된다).
- 공통 빌드 + 매머드 매장 → "매머드 전용 앱 설치 필요" 배너
- 매머드 빌드 + 타 브랜드 매장 → 경고

**규율 테스트** — `test/config/build_brand_scope_test.dart`: `BuildBrand` 를 참조하는 파일 집합을 화이트리스트로 고정한다. 새 참조가 생기면 테스트가 깨지고, 통과시키려면 사람이 의도적으로 목록을 늘려야 한다.

---

## Phase C — Windows 전용 빌드

과거 dual-variant 골격에서 검증된 지점을 그대로 재사용한다. **모든 네이티브/빌드 소스는 ASCII 만** (CLAUDE.md 절대 규칙).

| 파일 | 변경 |
| --- | --- |
| [windows/CMakeLists.txt:12](../../windows/CMakeLists.txt) | `$ENV{APPFIT_BRAND}` 로 `BINARY_NAME` 분기 + `add_compile_definitions(APPFIT_BRAND_MAMMOTH)` |
| [windows/runner/Runner.rc:76-81](../../windows/runner/Runner.rc) | `#ifdef` 로 `APPFIT_PRODUCT_NAME`/`APPFIT_EXE_NAME` 분기, ICON 을 `app_icon_mammoth.ico` 로 |
| [windows/runner/main.cpp:14-15](../../windows/runner/main.cpp) | mutex 명·window title 분기 |
| [installer/appfit_order_agent.iss:23-29](../../installer/appfit_order_agent.iss) | `-Brand` 에서 `/D` 로 주입 — AppName·ExeName·Mutex·DirName·OutputBaseName·**AppId** |
| [lib/config/update_config.dart](../../lib/config/update_config.dart) | 매머드 채널 + 임시 파일명 전부 분리 (zip/extract/bat/vbs/log) |

- `ProductName` 이 `%APPDATA%\CompanyName\ProductName` 을 결정하므로 SharedPreferences 샌드박스가 자동 분리된다. 출시 전이라 설정 승계는 불필요하다.
- **Inno AppId GUID 를 새로 1회 생성해 영구 고정**하고 iss 주석에 박는다. 폐기된 korea GUID `{E448C213-990C-AEED-03A8-6A695F9EED14}` 는 재사용 금지.
- 새 Windows OTA 채널: `appfit_order_agent_mammoth_windows.zip` / `_mammoth_windows_version.json`. 임시 파일명까지 분리해야 공통 설치본과 병존 시 업데이트가 충돌하지 않는다.
- **CMake 캐시**: 브랜드 전환 시 `build/windows` clean 이 필수다. 스크립트가 sentinel(`build/windows/.appfit_brand`)로 자동 감지·삭제한다.

---

## Phase D — 스크립트 + 슬래시 명령어

### 스크립트

| 스크립트 | 변경 |
| --- | --- |
| `build_main.sh` | `[common\|mammoth\|all]` (기본 common). `--flavor` + `--dart-define=APPFIT_BRAND=` 주입, 산출물 `app-<flavor>-release.apk` → `<project>_<brand>_v<ver>_<date>.apk` |
| `deploy_apk.sh` | `[common\|mammoth]` (기본 common). 브랜드에서 APK명·버전 JSON명을 파생한다. **업로드 직전 `aapt dump badging` 으로 APK 의 package 가 그 채널과 맞는지 검증하고 불일치면 중단** — 채널·아티팩트 교차 업로드는 되돌릴 수 없고, 레거시 채널이 동결된 원인이 정확히 이 사고다 |
| `archive_apk.sh` | 인자에 `<brand>` 추가, 경로를 `apk/<brand>/<버전>/` 로. **지금 구조면 같은 버전에서 두 브랜드의 `release_notes.txt` 가 서로 덮어쓴다** |
| `build_windows.ps1` / `deploy_windows.ps1` / `build_installer.ps1` / `archive_windows.ps1` | `-Brand` 파라미터 + 브랜드 채널·아카이브 경로. UTF-8 BOM 유지 |
| 신규 배포 이력 파일 | 스토어 업로드는 서버 JSON 이 없어 **어디에도 기록이 남지 않는다.** 브랜드/버전/채널/일시/gray 범위를 남기는 로컬 기록을 둔다 |

### 슬래시 명령어

| 명령어 | 변경 |
| --- | --- |
| `/release-apk [common\|mammoth\|all]` | 인자 없으면 AskUserQuestion. `all` 은 **같은 커밋·같은 버전**으로 연속 빌드 후 두 APK 의 versionCode 동일 여부를 출력 |
| `/deploy-android [common\|mammoth\|all]` | 1단계 버전표를 **브랜드×채널 행렬**로 확장(각 채널 JSON 조회 + 마지막 스토어 업로드 기록). 매머드 행에는 "운영 정책상 실제 배포는 스토어 경로"임을 함께 표시한다 |
| **신규 `/store-upload [common\|mammoth]`** | Sunmi App Store 수동 업로드 체크리스트·기록. 아티팩트 존재/서명/versionCode 확인 → gray 타깃 범위 확인 → 업로드 후 이력 기록. 콘솔 자동화는 불가하나 **절차 강제와 이력은 가능하다** |
| `/release-windows`, `/deploy-windows` | `[common\|mammoth]` 인자 + 브랜드별 채널 JSON 조회/갱신 |
| `/add-brand` | 마지막에 **Tier 1 승격 3문항** 추가(기본 Tier 0). STEP 2-1 앵커를 `storeIdPrefix:` → `prefixEnvironments:` 로 갱신 |
| deploy 계열 공통 | 1단계에 `git status --porcelain` dirty 확인 + **실행 직전 `pubspec.yaml` 재확인** (동시 세션이 build-number 를 올리며 먼저 배포한 사고가 2회 있었다) |

---

## Phase E — 문서·운영 자산

- **[docs/RELEASE.md](../../docs/RELEASE.md)** — "하지 말 것"의 두 항목(*MHST 전용 패키지명/전용 APK 생성*, *브랜드별 OTA 채널 증설*)을 **티어 모델 + 승격 조건 + 채널 불변식**으로 대체한다. 금지의 취지("채널을 함부로 늘리지 마라")는 *채널 수 = 아티팩트 수* 규칙으로 더 강하게 보존된다. "대원칙: 아티팩트 1개, 채널 2개" 절도 다시 쓴다.
- **[docs/BUILD.md](../../docs/BUILD.md)**, **[docs/BUILD_VARIANTS.md](../../docs/BUILD_VARIANTS.md)** — 플레이버·`-Brand`·채널 매트릭스 반영. BUILD_VARIANTS 는 "단일 빌드 모델"이라는 제목부터 갱신 대상.
- **[CLAUDE.md](../../CLAUDE.md)** — "flavor·변형 인자 없음" 문장 수정.
- **[docs/ARCHITECTURE.md](../../docs/ARCHITECTURE.md)**, **[docs/AS-IS.md](../../docs/AS-IS.md)**, **[agentc4model/](../../agentc4model/)** — 패키지·채널 표 갱신.
- **설치 가이드** — 매머드는 별도 리스팅이므로 [Sunmi 설치 가이드](../../docs/guide/Sunmi-appfit-agent-install-guide.html) 의 매머드 버전 1부가 필요하다(검색할 앱 이름·아이콘 캡처가 다르다).
- **설치 모니터링 도구** — 추적 대상 패키지 목록에 `.appfit.mammoth` 추가.

---

## 배포 매트릭스 (목표 상태)

| 브랜드 | 플랫폼 | 아티팩트 | 스토어 경로 | OTA 채널 |
| --- | --- | --- | --- | --- |
| 공통 | Android | `app-common-release.apk` (`….appfit`) | Sunmi App Store 공통 리스팅 | `appfit_order_agent_release.apk` / `_release_version.json` (불변) |
| 매머드 | Android | `app-mammoth-release.apk` (`….appfit.mammoth`) | Sunmi App Store **매머드 리스팅**, gray 단계 배포 | `appfit_order_agent_mammoth_release.apk` / `_mammoth_release_version.json` (신설) |
| 공통 | Windows | `appfit_order_agent.exe` | — | 무접미 ZIP 채널 (불변) |
| 매머드 | Windows | `appfit_order_agent_mammoth.exe` | — | `_mammoth_windows` ZIP 채널 (신설) |

**채널 이름은 규칙으로 파생한다** — `appfit_order_agent_<brand>_release.*` / `appfit_order_agent_<brand>_windows.*`. 다음 Tier 1 브랜드는 슬러그만 정하면 채널이 따라오고, 스크립트도 문자열 조립만 하면 된다. 브랜드마다 채널명을 손으로 짓지 않는다.

**매머드의 실제 운영 정책은 Sunmi 스토어 전용이다.** OTA 채널은 (1) 향후 Tier 1 브랜드를 위한 구조적 대비이고, (2) 비-Sunmi 단말과 수동 체크 경로의 안전망이다. 다만 **빈 채널은 안전망이 아니다** — 404 는 조용히 삼켜진다. 릴리즈마다 매머드 채널도 함께 채워 살아 있게 유지한다(추가 비용은 scp 한 번).

**불변식:** 두 Android 아티팩트는 항상 **같은 커밋·같은 versionCode·같은 서명키**로 만든다. 버전 정본은 `pubspec.yaml` 하나를 유지한다. 롤아웃 순서는 아티팩트별로 기존 규칙을 따른다 — 스토어 gray canary 먼저, 비율 제어가 없는 OTA 는 항상 맨 뒤.

---

## 검증

1. `flutter analyze` — warning baseline 은 **69**(0 아님). 새 에러 0 확인. `flutter test` 전량 통과.
2. 양쪽 빌드 후 `aapt dump badging` 으로 package / versionCode / label / icon 확인 → **두 versionCode 동일** 확인.
3. 실기기(Sunmi D3 MINI): 두 APK 병존 설치 후 `adb shell pm list packages | grep appfit` → 런처에 이름·아이콘 2종이 각각 보이는지 육안 확인.
4. 매머드 빌드: 로그인·설정의 업데이트 체크가 **매머드 채널 URL** 로 나가는지 로그로 확인. 공통 빌드는 기존 `_release` 그대로인지 확인(회귀 방지). 매머드+Sunmi 는 자동 체크가 OFF 로 재조정되는지도 함께 확인.
5. MMTH 매장 ID 로그인 → 라벨·영수증 로고가 매머드(tokyoplatz 폴백 아님), 서버 live 자동 전환. MHST 매장 ID → staging 전환.
6. 공통 빌드에 MMTH 로그인 → 전용 앱 안내 배너가 뜨고 **기능은 정상 동작**.
7. Windows `-Brand mammoth`: exe명·ProductName·`%APPDATA%` 분리·mutex 독립·인스톨러 GUID 별개(공통 설치본과 병존 설치), 매머드 채널 JSON 조회.
8. 브랜드 전환 빌드 2연속(`common → mammoth → common`)으로 Gradle·CMake 캐시 오염이 없는지.

## 다른 머신에서 이어받기 (Windows 빌드 PC)

Phase C 는 Windows 빌드 PC 에서 수행한다. 옮겨가기 전 확인할 것:

- **`lib/config/app_env.dart` 와 `.env` 는 gitignored 머신별 로컬 파일**이라 clone 만으로는 없다. Windows PC 에 사본이 있는지 먼저 확인한다(없으면 빌드가 실패한다). 이번 계획은 `app_env.dart` 를 **건드리지 않도록** 일부러 `build_brand.dart` 를 새로 만드는 방식이므로, 두 머신의 `app_env.dart` 가 달라도 문제되지 않는다.
- PowerShell 스크립트는 **UTF-8 BOM** 으로 저장한다. 네이티브·빌드 소스(`.cpp`/`.h`/`.rc`/`.cmake`/`.ps1`)는 **ASCII 만** — MSVC 가 BOM 없는 UTF-8 을 CP949 로 읽어 C4819 를 내고 문자열이 깨진다.
- Windows 빌드 도구 함정: `build_windows.ps1` 의 종료 코드를 반드시 검사한다. fresh configure 후 **첫 INSTALL 이 MSB3073 으로 실패하고 2차에 성공**하는 알려진 패턴이 있어, 검사 없이 아카이브하면 깨진 산출물이 보관된다.
- 브랜드를 바꿔 연속 빌드할 때는 `build/windows` clean 이 필수다(CMake 캐시). 스크립트의 sentinel 이 자동 처리하도록 만드는 것이 Phase C 작업 항목에 포함돼 있다.
- 버전 정본은 `pubspec.yaml` 하나이고 Android/Windows 가 공유한다. **실행 직전 `pubspec.yaml` 을 다시 확인한다** — 다른 세션이 build-number 를 올리며 먼저 배포한 사고가 두 번 있었다.

## 열린 항목 (실행 중 확인)

- **Sunmi App Store 신규 리스팅** 등록·심사 리드타임 — 콘솔 수동 작업이라 자동화 불가. 롤아웃 일정의 임계 경로일 수 있다.
- **이미 `.appfit` 이 깔린 매머드 함대 처리** — 신규 패키지 설치 후 구 패키지를 제거할지 병존시킬지. 롤아웃 시점이 미정이라 별도 결정으로 남긴다.
- `flutter_launcher_icons` 플레이버 출력 경로 — 1회 실행으로 확인 후 확정.
- MHST 를 staging 으로 옮긴 뒤 **Sentry 라우팅 환경 스코프** 재확인.
