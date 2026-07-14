# 빌드 / 배포 / 환경 / 다국어

빌드 명령어, 환경 변수, 다국어(Slang) 워크플로 등 작업 시점에만 필요한 참조 정보입니다.

> 단일 빌드 모델(런타임 서버선택)·OTA 채널·버전 이원화를 도식으로 본 문서: [docs/BUILD_VARIANTS.md](BUILD_VARIANTS.md).
>
> 배포 채널 정책(OTA + Sunmi App Store 이중 채널, 롤아웃 순서·핫픽스 절차)의 정본: [docs/RELEASE.md](RELEASE.md).

## 빌드 및 실행 명령어

```bash
# 의존성 설치
flutter pub get

# 코드 생성 (freezed, json_serializable, riverpod_generator)
flutter pub run build_runner build --delete-conflicting-outputs

# 다국어 생성 (slang i18n) — standalone 이라 build_runner 와 별개로 실행해야 함
flutter pub run slang

# 정적 분석
flutter analyze

# 릴리즈 APK 빌드 (.env 파일에 APPFIT_AES_KEY, SENTRY_DSN 필요)
flutter build apk --release --dart-define-from-file=.env

# 전체 클린 + 빌드 (단일 빌드 — 인자 없음)
./build_main.sh

# 빌드 + Lightsail 서버 배포 (SCP 업로드 + 버전 JSON 업데이트)
./deploy_apk.sh

# 전체 테스트 실행
flutter test

# 단일 테스트 파일 실행
flutter test test/<파일_경로>
```

**중요**: 모델(`freezed`/`json_serializable`)·프로바이더(`riverpod_generator`)를 변경한 후에는 `flutter pub run build_runner build --delete-conflicting-outputs`를, i18n JSON(`*.i18n.json`)을 변경한 후에는 `flutter pub run slang`을 재실행해야 합니다. **slang 은 standalone 설정(`slang_build_runner` 미사용)이라 build_runner 로는 `strings.g.dart` 가 갱신되지 않습니다.** Flutter 프로젝트라 `dart run` 은 SDK 해석 에러가 나므로 `flutter pub run` 을 씁니다. `.g.dart` 또는 `.freezed.dart`로 끝나는 생성된 파일은 절대 직접 수정하지 않습니다.

## 단일 빌드와 런타임 서버선택, OTA 채널

**단일 패키지(`co.kr.waldlust.order.receive.appfit`)·단일 exe(`appfit_order_agent.exe`)·단일 빌드**가 한국/일본을 모두 서빙합니다. 빌드 변형·flavor·`APPFIT_VARIANT` dart-define 은 없습니다.

- **서버는 런타임 결정**: 서버(live=한국 / japanLive=일본)는 저장값(`PreferenceService.getEnvironment()`, 기본 `live`)으로 시작하고, 로그인 화면 우상단 배지(KR/JP)를 탭해 변경할 수 있습니다(릴리즈는 live/japanLive 2종, 개발 빌드는 dev/staging 포함 4종).
- **매장 ID 프리픽스 자동 전환**: 로그인 시 입력한 매장코드의 브랜드(`BrandRegistry.serverEnvironment` — TPCP·PAIK→japanLive, MHST·MATA→live)로 서버가 자동 전환됩니다. 미등록 프리픽스는 명시 선택 이력이 없으면 서버선택 다이얼로그를 1회 띄웁니다. release 에서 dev/staging 잔존 저장값은 시작 시 live 로 클램프됩니다(`main.dart`).
- **OTA 채널은 플랫폼별 1개** (`lib/config/ota_config.dart` / `lib/config/update_config.dart`):
  - Android — `appfit_order_agent_release_version.json` / `appfit_order_agent_release.apk`
    - ⚠️ 레거시 무접미 채널(`appfit_order_agent.apk` / `appfit_order_agent_version.json`)은 **동결(FROZEN)**. 구 패키지(`co.kr.waldlust.order.receive`)로 설치된 일본 매장 1곳 전용이라 `.appfit` APK 를 올리면 패키지 불일치로 설치 실패 — 업로드 금지. 구 `_japan`/`_korea`/`_appfit` 채널은 폐기(미사용).
  - Windows — `appfit_order_agent_windows_version.json` / `appfit_order_agent_windows.zip` (레거시 무접미 채널 **계속 사용** — 패키지 개념이 없고 exe명이 동일해 기존 설치본이 자연 업데이트. Android 와 정책 반대)
  - ⚠️ 채널이 하나이므로 업로드 즉시 **한국/일본 동시 롤아웃**됩니다(지역별 시차 배포 불가).
- **실행**: 모든 빌드/배포 스크립트는 인자가 없습니다 — `./build_main.sh`, `./deploy_apk.sh`, `.\build_windows.ps1`, `.\deploy_windows.ps1`, `.\build_installer.ps1`.
- Android 는 flavor 없이 `defaultConfig` 의 단일 applicationId 를 쓰고, Windows exe명(CMake BINARY_NAME)·mutex·설치 GUID 도 국가와 무관하게 통일됐습니다. 한 머신에 하나만 설치되며, 재설치 시 in-place 업그레이드됩니다.

## Android APK 크기 정책 (ABI 2종 · .so 압축)

릴리즈 APK 는 **`armeabi-v7a` + `arm64-v8a` 2종**이며 네이티브 라이브러리를 **압축**해 넣습니다. 정본은 `android/app/build.gradle.kts` 의 `release` buildType 입니다. OTA 가 매장 Wi-Fi 로 APK 를 통째로 내려받는 구조라 다운로드 크기가 곧 업데이트 실패율입니다.

**79.1 MiB → 28.55 MiB (-64%)**. 내역:

| 조치 | 위치 | 효과 |
|---|---|---|
| `ndk.abiFilters = ["armeabi-v7a", "arm64-v8a"]` | `buildTypes.release` | -24.8 MiB (x86_64 제거 — 에뮬레이터 전용) |
| `packaging.jniLibs.useLegacyPackaging = true` | `android` | -22.3 MiB (.so 압축) |
| Pretendard-Light 미선언 | `pubspec.yaml` | -1.1 MiB (`FontWeight.w300` 사용처 0) |
| `packaging.resources.excludes` | `android` | -0.6 MiB (JNA 의 AIX/Win/macOS 네이티브, autoreplyprint `.java` 소스) |
| `.proto` 서술자 · `cupertino_icons` | `android` / `pubspec.yaml` | -0.3 MiB (사용처 0) |

`.so` 압축은 설치 시 추출되므로 기기 저장공간을 ~10 MiB 더 쓰지만, **콜드 스타트는 오히려 빨라집니다**(D3 MINI 825→690ms, T2mini_s 1702→1335ms, 3회 평균).

### ⚠️ armeabi-v7a 를 절대 빼지 말 것 — **D2s_KDS 는 32비트 전용이다**

fleet 전수 실측 결과입니다. **SoC 스펙시트로는 알 수 없고 `getprop` 으로만 드러납니다.**

| 기기 | Android | SoC | `ro.zygote` | `abilist64` | 판정 |
|---|---|---|---|---|---|
| D3 MINI | 13 | bengal (Snapdragon) | `zygote64_32` | `arm64-v8a` | 64비트 |
| T2mini_s | 7.1 | msm8937 (SD430) | `zygote64_32` | `arm64-v8a` | 64비트 |
| **D2s_KDS_STGL** | **11** | **rk356x (RK3566)** | **`zygote32`** | **(비어 있음)** | **32비트 전용** |

arm64 전용 APK 를 D2s_KDS 에 넣으면 **`INSTALL_FAILED_NO_MATCHING_ABIS` 로 설치가 거부됩니다**(실측 확인). 자동 OTA 가 꺼진 Sunmi 기기 특성상 복구는 매장 방문이 됩니다.

**새 기기를 fleet 에 들일 때는 반드시** `adb shell getprop ro.product.cpu.abilist64` **를 먼저 확인하세요.** 값이 비어 있으면 32비트 전용입니다. 연식·OS 버전·SoC 로 추정하지 마세요 — D2s_KDS 는 Android 11, 2025년 6월 빌드, 64비트 SoC 인데도 32비트입니다.

### D2s_KDS 는 왜 32비트인가 (조사 결과)

**RAM 절약이 아닙니다.** RAM 이 **3.79 GB** 이고 `ro.config.low_ram` 도 꺼져 있습니다. Android Go 도 아닙니다.

**하드웨어는 64비트가 맞습니다.** `CPU part 0xd05` = Cortex-A55, `CPU architecture: 8` — RK3566 은 정직한 ARMv8-A 쿼드코어입니다.

**그런데 64비트 실행 인프라가 이미지에 아예 없습니다.** "껐다"가 아니라 "넣지 않았다"입니다:

| 항목 | D2s_KDS |
|---|---|
| `uname -m` | **`armv8l`** — ARMv8 코어를 AArch32 로 실행 = **커널조차 32비트** |
| `/system/bin/linker64` | **없음** (64비트 ELF 를 로드할 동적 링커가 부재) |
| `/system/bin/app_process64` | **없음** |
| `/vendor/lib64` | **0개** (`/vendor/lib` 은 111개) |
| `/system/lib64` | 2개 — linker64 가 없어 로드조차 불가능한 잔재 |

**원인은 BSP 계보입니다.** 모든 fingerprint prop(`ro.build`/`ro.vendor`/`ro.odm`/`ro.system`/`ro.bootimage`)이 하나같이:

```
alps/full_rlk6580_we_c_m/rlk6580_we_c_m:11/1241/1241:user/release-keys
```

`alps` 는 **MediaTek 의 Android BSP 빌드 시스템 코드명**이고 `rlk6580` 은 **MT6580 프로젝트명**입니다. MT6580 은 Cortex-A7 = ARMv7 = **64비트가 물리적으로 불가능한 칩**입니다. 반면 실제 보드는 `ro.build.tracker = sunmi_rk3566_base_v1.3.8_20221108`, `ro.hardware = rk30board` 로 Rockchip 입니다.

즉 **SUNMI 의 RK3566 이미지는 MT6580(ALPS) 제품의 device makefile 을 물려받아 만들어졌고, 그 32비트 빌드 구성(`TARGET_ARCH := arm`)이 실리콘을 갈아탄 뒤에도 그대로 따라온 것**으로 보입니다. fingerprint 조차 갱신하지 않은 걸 보면 의도된 설계가 아니라 관성입니다. (지문에서 끌어낸 추론이며 SUNMI 가 문서화한 내용은 아닙니다. 다만 Rockchip 네이티브 빌드에 `alps/rlk6580` 문자열이 우연히 박힐 수는 없습니다.)

**앞으로도 32비트로 남을 가능성이 높습니다.** BSP 베이스가 2022-11 이고 보안 패치는 2024-03 에 멈췄는데 빌드는 2025-06 입니다 — 동결된 BSP 위에 재빌드만 하고 있다는 뜻이라, "언젠가 64비트가 되겠지"를 기대하고 `armeabi-v7a` 를 빼면 안 됩니다.

**부수 제약 — KDS 는 32비트 프로세스로 돕니다.** 프로세스당 주소공간이 실질 2~3GB 로 제한됩니다. KDS 모드에서 주문 이미지·캐시를 크게 쥐는 변경을 하면 **다른 기기는 멀쩡한데 D2s_KDS 에서만 OOM** 이 날 수 있습니다.

### 꼭 알아야 할 함정

- **`--target-platform` 플래그만으로는 ABI 가 안 걸러진다.** Flutter Gradle 플러그인이 서드파티 AAR 용 `abiFilters` 를 `[arm32, arm64, x86_64]` 로 **항상 고정**하기 때문에(`FlutterPlugin.kt`), 플래그만 쓰면 `libautoreplyprint.so`·`libsentry.so` 의 x86_64 판이 그대로 남습니다. 패키징 차단의 정본은 `build.gradle.kts` 의 `abiFilters` 이고, 스크립트의 `--target-platform android-arm,android-arm64` 는 x86_64 AOT 컴파일을 건너뛰어 빌드 시간을 줄이는 보조 수단입니다.
- **`--split-per-abi` 를 쓰지 말 것.** versionCode 에 ABI 오프셋을 더해 [RELEASE.md](RELEASE.md) 의 "아티팩트 1개 · 채널 2개 · 같은 versionCode" 불변식을 깹니다.
- **debug 는 건드리지 않았습니다** — x86_64 에뮬레이터 개발이 그대로 됩니다.
- **`--obfuscate` 를 켜지 말 것.** `captureError` 가 `exception.runtimeType` 을 Sentry 중복억제 키로 쓰고 `api_error_mapper.dart` 가 `runtime_type` 을 태그로 전송하는데, 난독화하면 이 값이 `a`/`b` 로 바뀝니다(앱이 만든 문자열이라 심볼리케이션 대상이 아님). `--split-debug-info` 도 현재는 보류 — `sentry_dart_plugin` 이 pubspec 에 있지만 **어떤 스크립트도 호출하지 않고 `SENTRY_AUTH_TOKEN` 도 없어 심볼 업로드가 실제로 실행되지 않습니다**. 심볼 업로드 파이프라인을 먼저 구축한 뒤에 재고하세요(-1.3 MiB).

## Windows 빌드 / 배포 / 인스톨러

### 버전 정본

- `pubspec.yaml`의 `version`(`x.y.z+n`)이 **Android·Windows 공통 단일 정본**입니다. Windows 스크립트(`build_windows.ps1` / `deploy_windows.ps1` / `build_installer.ps1` / `archive_windows.ps1`)가 이 값을 파싱해 `--build-name` / `--build-number`로 주입합니다.
- 과거 Windows 전용이던 `version_windows.txt`는 **폐지**됐습니다(두 플랫폼 버전이 어긋나 OTA 사고를 유발). 버전 상향은 `pubspec.yaml` 한 곳만 고칩니다.
- 모든 PowerShell 스크립트는 **UTF-8 BOM**으로 저장돼 있어야 합니다 (한국어 Windows의 CP949 콘솔에서 한글이 깨지는 것을 방지).

### 필요 환경

- Visual Studio 2022 (MSVC + `cmake.exe`)
- Inno Setup 6 (`ISCC.exe`) — `winget install JRSoftware.InnoSetup` 또는 https://jrsoftware.org/isdl.php
- 루트의 `.env` 파일 (`APPFIT_AES_KEY`, `SENTRY_DSN`)

### 스크립트 3종

| 스크립트 | 역할 |
| --- | --- |
| `build_windows.ps1` / `build_windows.sh` | 로컬 release 빌드 (zip 산출 X). `pubspec.yaml`의 `version` → `--build-name` / `--build-number` 주입. |
| `deploy_windows.ps1` | release 빌드 + VC++ 런타임 DLL 번들링 + zip 패키징 + Lightsail SCP 업로드 + `version.json` 갱신 (OTA 채널). CMake install prefix 점검 후 필요 시 `cmake -A x64`로 재구성. |
| `build_installer.ps1` | release 빌드 + VC++ 런타임 DLL 번들링 + Inno Setup으로 `dist\AppfitOrderAgent-Setup-<semver>.exe` 생성. **신규 설치용** — OTA에는 사용하지 않음. |

### Inno Setup 스크립트

- 위치: `installer/appfit_order_agent.iss`
- `MyAppVersion`은 `build_installer.ps1`이 `/DMyAppVersion=<semver>`로 주입
- `AppId`는 영구 GUID — **재생성 금지** (변경 시 제어판 "프로그램 추가/제거"에 중복 항목 발생)
- `AppMutex`는 `windows/runner/main.cpp`의 `kSingleInstanceMutexName` 상수(`Global\AppfitOrderAgent_SingleInstance_Mutex`)와 동일해야 함

### OTA 자동 업데이트

- 사용자 설정 위치: `%APPDATA%\co.kr.waldlust.order\appfit_order_agent\` — 인스톨러 재설치 시 보존되어 로그인 토큰/프린터 설정이 유지됨
- 업데이트 진행 UI: `lib/widgets/update/update_progress_dialog.dart`
- 체크/다운로드/재시작 로직: `WindowsUpdateService` (`lib/services/windows_update_service.dart`)

## 환경 설정

빌드 타임 시크릿은 `--dart-define-from-file=.env`로 주입 (파일은 커밋하지 않음):

- `APPFIT_AES_KEY` — API 암호화용 32바이트 AES 키
- `SENTRY_DSN` — Sentry 오류 추적 엔드포인트
- `IS_ROTATED_180` — 선택적 180도 화면 회전
- `SLACK_BOT_TOKEN` — 로그 업로드용 Slack 봇 토큰(`xoxb-`, `files:write` 스코프). 대상 채널에 봇 초대 필수. 없으면 설정화면 "로그 전송" 카드가 비활성(`SlackDirectSink`). 클라이언트 바이너리에 박히므로 최소 스코프·단일 채널로 제한
- `SLACK_CHANNEL_ID` — 로그를 게시할 단일 채널 ID(예: `C0XXXXXXX`)

런타임 환경(서버 대상)은 로그인 시 선택되며 `PreferenceService`를 통해 저장됩니다. `main.dart`에서 `AppFitConfig.configure()` 호출 전에 결정됩니다.

## 다국어 지원 (Slang)

- 설정 파일: `slang.yaml`
- 소스 파일: `lib/i18n/strings_ko.i18n.json` (기본), `strings_en.i18n.json`, `strings_ja.i18n.json`
- 생성 파일: `lib/i18n/strings.g.dart` 및 로캘별 파일
- 사용법: `t.common.confirm`, `t.order.status.new_order` 등
- 생성 방식: **standalone slang CLI** (`slang_build_runner` 미사용). `.i18n.json` 편집 후 `flutter pub run slang` 으로 재생성한다 — `build_runner` 로는 `strings.g.dart` 가 갱신되지 않으므로 주의.
