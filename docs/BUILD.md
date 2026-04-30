# 빌드 / 배포 / 환경 / 다국어

빌드 명령어, 환경 변수, 다국어(Slang) 워크플로 등 작업 시점에만 필요한 참조 정보입니다.

## 빌드 및 실행 명령어

```bash
# 의존성 설치
flutter pub get

# 코드 생성 (freezed, json_serializable, riverpod_generator, slang i18n)
dart run build_runner build --delete-conflicting-outputs

# 정적 분석
flutter analyze

# 릴리즈 APK 빌드 (.env 파일에 APPFIT_AES_KEY, SENTRY_DSN 필요)
flutter build apk --release --dart-define-from-file=.env

# 전체 클린 + 빌드
./build_main.sh

# 빌드 + Lightsail 서버 배포 (SCP 업로드 + 버전 JSON 업데이트)
./deploy_apk.sh

# 전체 테스트 실행
flutter test

# 단일 테스트 파일 실행
flutter test test/<파일_경로>
```

**중요**: 모델(`freezed`/`json_serializable`), 프로바이더(`riverpod_generator`), i18n JSON 파일을 변경한 후에는 반드시 `dart run build_runner build --delete-conflicting-outputs`를 재실행해야 합니다. `.g.dart` 또는 `.freezed.dart`로 끝나는 생성된 파일은 절대 직접 수정하지 않습니다.

## Windows 빌드 / 배포 / 인스톨러

### 버전 정본

- `version_windows.txt`(루트)가 Windows 빌드의 **단일 정본** (`x.y.z+n` 한 줄). `pubspec.yaml`과 분리되어 있으며 Windows 빌드 스크립트는 pubspec을 읽지 않습니다. Android와 Windows 버전을 따로 끊어 올릴 수 있도록 의도적으로 분리됐습니다.
- 모든 PowerShell 스크립트는 **UTF-8 BOM**으로 저장돼 있어야 합니다 (한국어 Windows의 CP949 콘솔에서 한글이 깨지는 것을 방지).

### 필요 환경

- Visual Studio 2022 (MSVC + `cmake.exe`)
- Inno Setup 6 (`ISCC.exe`) — `winget install JRSoftware.InnoSetup` 또는 https://jrsoftware.org/isdl.php
- 루트의 `.env` 파일 (`APPFIT_AES_KEY`, `SENTRY_DSN`)
- 루트의 `version_windows.txt`

### 스크립트 3종

| 스크립트 | 역할 |
| --- | --- |
| `build_windows.ps1` / `build_windows.sh` | 로컬 release 빌드 (zip 산출 X). `version_windows.txt` → `--build-name` / `--build-number` 주입. |
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

### 무시되는 산출물

`kokonut_order_agent_windows.zip`, `version.json`, `.sentry-native/dist`는 `.gitignore`로 제외돼 있어 커밋되지 않습니다.

## 환경 설정

빌드 타임 시크릿은 `--dart-define-from-file=.env`로 주입 (파일은 커밋하지 않음):

- `APPFIT_AES_KEY` — API 암호화용 32바이트 AES 키
- `SENTRY_DSN` — Sentry 오류 추적 엔드포인트
- `IS_ROTATED_180` — 선택적 180도 화면 회전

Windows 빌드는 추가로 루트의 `version_windows.txt`(`x.y.z+n` 형식)가 필수입니다.

런타임 환경(서버 대상)은 로그인 시 선택되며 `PreferenceService`를 통해 저장됩니다. `main.dart`에서 `AppFitConfig.configure()` 호출 전에 결정됩니다.

## 다국어 지원 (Slang)

- 설정 파일: `slang.yaml`
- 소스 파일: `lib/i18n/strings_ko.i18n.json` (기본), `strings_en.i18n.json`, `strings_ja.i18n.json`
- 생성 파일: `lib/i18n/strings.g.dart` 및 로캘별 파일
- 사용법: `t.common.confirm`, `t.order.status.new_order` 등
- `.i18n.json` 파일 편집 후 반드시 build_runner로 재생성
