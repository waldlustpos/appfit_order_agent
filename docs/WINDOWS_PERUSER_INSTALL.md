# Windows per-user 설치 전환

> STATUS (2026-08-27 — **구현 완료, 공통 브랜드 실기 검증 완료 / 미배포**)
> 이식 5단계(업데이터 견고화+HTTPS → per-user 전환 → Defender 예외 → 자가진단 →
> `-SkipBuild`)를 모두 구현하고, 공통 브랜드 기준으로 이 PC 에서 실기 검증했다.
> 검증 중 **코드 결함 4건**을 발견해 함께 고쳤다 — 8절 참조.
>
> kokonut 정본: `kokonut_order_agent_v2/docs/WINDOWS_PERUSER_INSTALL.md`
> (브랜치 `feature/windows-localappdata-install`, 별도 레포이므로 상대 링크 불가).
> **8절의 결함 2·3번은 kokonut 정본에도 그대로 있다 — 그쪽에도 반영이 필요하다.**

---

## 1. 왜 바꾸는가

2026-08-26 kokonut 매장 사고에서 Windows Defender 가 설치된 exe 를
`Trojan:Win32/Bearfoos.A!ml`(ML 휴리스틱 오탐)로 격리했다. 주 입력은 **미서명 +
저평판 바이너리**이고, 기존 구조(`C:\Program Files` 설치 + 자기 업데이트 시 UAC
상승 + VBS 숨김 cmd)가 휴리스틱이 의심하는 행위 패턴을 만들어냈다. EV 코드서명은
인증서·HSM 의무 보관과 양쪽 빌드 워크플로 변경 비용이 커서, 대신 **설치 위치를
`%LOCALAPPDATA%\Programs` per-user 로 전환**해 자기 업데이트 시 UAC 상승 자체를
없애는 쪽을 택했다.

appfit 은 kokonut 과 같은 OTA 서버(`waldpay.kokonutstamp2.com`)를 쓰고 같은 updater
패턴(VBS 래퍼 + robocopy)을 이식받아 왔으므로 같은 위험에 노출돼 있다.

> **per-user 전환이 오탐 면제권은 아니다.** 미서명 + 저평판이라는 주 입력은 그대로고,
> 오히려 사용자 쓰기 가능 경로에서 실행되는 미서명 exe 는 휴리스틱이 더 의심하는
> 형태다. Defender 예외 자동 등록(3단계)은 그래서 유지한다.

---

## 2. 전제: 한 PC = 한 아티팩트

공통 앱과 브랜드 전용 앱(매머드)이 **같은 PC 에 동시에 설치·운영되는 경우는 없다**
(운영 확정 사항). `installer/appfit_order_agent.iss` 의 현재 헤더 주석은 "Each brand
gets its own AppId, so both can be installed side by side on the same machine"
이라고 적혀 있어 오히려 병존 설치가 가능하다는 인상을 준다 — 이번 이식 검토 중
실제로 이 주석 때문에 "브랜드 간 충돌 방어"를 설계에 넣을 뻔했다. **2단계에서 이
주석을 정정한다.**

이 전제 때문에 아래 계획에서는 브랜드 간 충돌(예: 자동실행 레지스트리 값 이름 경합,
Defender 예외 경로 경합)을 막는 별도 로직을 넣지 않는다. AppId/뮤텍스/exe명이
브랜드별로 갈리는 이유는 "독립된 아티팩트"이기 때문이지 "병존 설치 지원"이 아니다.

---

## 3. 원칙: 브랜드 축 처리

appfit 의 유일한 구조적 차이는 **멀티 브랜드**(common/mammoth, Android product
flavor 에 대응)다. 전 구간에서 **컴파일타임 분기만** 쓰고 런타임 GUID 배열/순회는
쓰지 않는다 — `.iss` 는 브랜드당 별도 컴파일(`ISCC /DAppfitBrand=<slug>`), `main.cpp`
도 브랜드당 별도 빌드, Dart 는 `BuildBrand.isMammoth` const 이기 때문이다.

| 파일 | 브랜드 처리 |
| --- | --- |
| `installer/appfit_order_agent.iss` | 기존 `#if AppfitBrand == "mammoth"` 블록 확장. `[Code]` 는 1벌만 작성 |
| `windows/runner/main.cpp` | 기존 `#if defined(APPFIT_BRAND_MAMMOTH)` 블록에 Local 폴백 이름 추가 |
| `lib/config/update_config.dart` | 기존 `BuildBrand.isMammoth ? ... : ...` 패턴 확장 |
| 그 외 신규 파일 | 브랜드를 전혀 모름 — `UpdateConfig` / `Platform.resolvedExecutable` 에 위임 |

---

## 4. 이식 순서 (그대로 지켜야 하는 계약)

kokonut 문서가 지정한 순서: **① 업데이터 견고화 + HTTPS → ② per-user 전환 →
③ Defender 예외 자동등록 → ④ 자가진단 + 자동실행 경로 갱신**. ①이 먼저 되어야
②가 안전하다 — robocopy 실패 복구가 없는 상태에서 설치 위치까지 바꾸면 현장에서
문제가 생겼을 때 원인을 분리할 수 없다.

### 1단계 — 업데이터 견고화 + HTTPS 전환

**`lib/config/update_config.dart`**
- `_base` 를 `https://waldpay.kokonutstamp2.com/` 로 전환. HTTP 폴백은 두지 않는다
  (다운그레이드 공격 노출). 서버 HTTPS 지원 확인 완료(200 응답).
- `_installDirName` 신설: `BuildBrand.isMammoth ? 'AppfitOrderAgentMammoth' :
  'AppfitOrderAgent'`. **`.iss` 의 `MyAppDirName` 과 반드시 동일해야 한다** — 3단계
  Defender 예외 경로가 `{localappdata}\{#MyAppDirName}` 이라, 어긋나면 예외가 실제
  스테이징 폴더를 못 덮는다.
- `stagingDir()` / `ensureStagingDir()` 신설 →
  `%LOCALAPPDATA%\<_installDirName>\update`. `LOCALAPPDATA` 미제공 시 systemTemp
  폴백. OTA 산출물(zip/압축해제/bat/vbs/log)을 전부 이 한 폴더로 모아야 Defender
  예외 1개가 OTA 전 경로를 덮는다.

**`lib/services/windows_updater_script.dart`**
kokonut 견고화 커밋(`4b022c6`) 이식. 핵심 5가지:
- `robocopy ... /R:3 /W:2` (재시도 3회, 2초 간격)
- `taskkill` 후 **`tasklist` 폴링**(고정 `timeout` 대신 `ping -n 2 127.0.0.1` 루프백,
  최대 20회 예산 → 초과 시 `[WARN]` 남기고 진행)
- `set RC=%ERRORLEVEL%` 로 즉시 복사(블록 안에서 소실 방지)
- **`:fail → :launch` 합류** — robocopy 실패해도 구버전을 다시 띄운다. 이게 없으면
  매장이 앱 없이 남는다
- 로그를 `>` 대신 `>>` append + 구분선/`rc=` 기록
- bat/log 경로를 `Directory.systemTemp` → `UpdateConfig.ensureStagingDir()` 로 변경
- bat 내부는 **ASCII only** 유지(cmd 코드페이지 충돌 방지, 기존 규칙 그대로)

**`lib/services/windows_update_service.dart`** (1단계分)
- `downloadUpdate()`: `getTemporaryDirectory()`(path_provider) → `UpdateConfig.ensureStagingDir()`
- `install()`: `extractDir` / `vbsPath` 를 스테이징 폴더 기준으로
- 이 파일에서 `package:path_provider/path_provider.dart` import 제거
  (`pubspec.yaml` 의존성 자체는 다른 곳에서 쓰므로 유지)

**`test/config/build_brand_scope_test.dart` — 필수 동반 수정**
122~154행의 `UpdateConfig` 그룹이 `http://` URL 을 바이트 단위로 단언한다. https
전환 시 그대로 깨지므로 **같은 커밋에서 반드시 함께 수정**한다(안 하면 CI 파손).
83/103행의 Android `OtaConfig` 그룹은 건드리지 않는다 — Android OTA 는 이번 스코프
밖. 같은 그룹에 `_installDirName` 회귀 방지 단언 추가를 권장한다(`.iss` 와 어긋나면
3단계가 조용히 무효화되므로).

**스코프 경계**: `lib/config/ota_config.dart`(Android), `lib/config/fleet_config.dart`,
배포 스크립트, `docs/BUILD_VARIANTS.md`·`docs/AS-IS.md` 의 http 표기도 같은 도메인을
쓰지만 **이번 작업은 Windows OTA(`UpdateConfig`)로 한정**한다.

### 2단계 — per-user 설치 전환

**`installer/appfit_order_agent.iss`** (이 단계의 핵심)

(a) 브랜드 블록(현재 33~54행):
- 각 브랜드에 `MyAppIdRaw` 신설(홑따옴표 GUID). `[Code]` Pascal 문자열 리터럴은
  Inno 의 중괄호 이스케이프를 받지 않아 `MyAppId` 와 스펠링을 공유할 수 없다.
  `MyAppId` 는 `"{" + MyAppIdRaw` 로 조립.
- **기존 GUID 를 재생성하지 않는다**(불변조건 2-3, 아래 5절). per-user 언인스톨
  항목은 HKCU 로 가서 HKLM 구 항목과 충돌하지 않고, 재생성하면 구설치 감지 자체가
  불가능해진다. 폐기 GUID(`{E448C213-...}`) 재사용 금지 주석은 유지.
- `MyAppMutex` 에 `Local\` 이름을 콤마로 추가:
  `"Global\AppfitOrderAgent[_Mammoth]_SingleInstance_Mutex,Local\AppfitOrderAgent[_Mammoth]_SingleInstance_Mutex"`
- **헤더 주석 정정**: "both can be installed side by side on the same machine" 이
  2절의 운영 전제와 정반대로 읽힌다. AppId 분리의 목적이 "독립 아티팩트"이지
  "병존 설치 지원"이 아니라는 점을 명시하도록 고친다.

(b) `[Setup]` 섹션 (현재 73~79행, "System-wide install" 블록 교체):
- `PrivilegesRequired=admin` → **`lowest`**. `DefaultDirName={autopf}\{#MyAppDirName}`
  은 **그대로 둔다** — `{autopf}` 가 lowest 아래에서 `{userpf}`=`%LOCALAPPDATA%\Programs`
  로 해석되고, `{group}`/`{autodesktop}` 도 per-user 위치가 된다(불변조건 2-1).
- **`PrivilegesRequiredOverridesAllowed` 를 추가하지 않는다**(불변조건 2-2). 열면
  "관리자 권한으로 실행" 시 machine-wide 로 되돌아가 전환이 조용히 무효화된다.
  왜 넣지 않는지 주석으로 남긴다.

(c) `[Code]` 신규 — 구 machine-wide 설치 감지·제거(불변조건 2-4):
- 상수: `LegacyUninstallSubkey = 'SOFTWARE\...\Uninstall\{#MyAppIdRaw}_is1'`,
  `LegacyRemovalTimeoutMs = 60000`, `LegacyPollIntervalMs = 500`
- 조회는 **`HKLM64`** 로 한다 — Setup 은 32비트 프로세스라 `HKLM` 만 쓰면
  WOW6432Node 를 본다
- `PrepareToInstall()`: 구설치 없으면 즉시 반환 → 있으면 안내 `MsgBox`(브랜드명은
  `{#MyAppName}` 로 표시) → 거부 시 설치 중단 메시지 반환
- `RemoveLegacyInstall()`: `UninstallString` 을 `/VERYSILENT /NORESTART
  /SUPPRESSMSGBOXES` 로 `ShellExec`(구 언인스톨러가 admin 이라 UAC 1회, 거부는 중단)
  → **언인스톨 레지스트리 키가 사라질 때까지 폴링**. Inno 언인스톨러는 자기를
  `%TEMP%` 로 복사 후 재실행하고 원본은 즉시 반환하므로 `ewWaitUntilTerminated` 로는
  완료를 알 수 없다.
- `[Code]` 는 **1벌만** 작성 — 전처리기가 현재 빌드 브랜드의 `MyAppIdRaw`/`MyAppName`
  을 이미 확정해 둔다.

**`windows/runner/main.cpp`** (불변조건 2-6)
현재 코드([main.cpp](../windows/runner/main.cpp) 의 진입 체크)는
`mutex == nullptr || GetLastError() == ERROR_ALREADY_EXISTS` 가 한 조건으로 묶여
있어, `Global\` 생성 권한(`SeCreateGlobalPrivilege`)이 없는 **표준 사용자가 "중복
실행"으로 오판되어 창도 오류 메시지도 없이 즉시 종료**하는 버그가 있다. per-user
전환은 표준 사용자 운영을 현실적 선택지로 만들므로 이 결함이 노출된다.
- 브랜드 블록에 `kSingleInstanceMutexNameLocal` 추가(기존 `#if` 구조 유지)
- `AcquireSingleInstanceMutex(bool* already_running)` 헬퍼 신설: `Global\` 1차 →
  실패 시 `Local\` 폴백 → 둘 다 실패하면 `nullptr` 반환하고 **뮤텍스 없이 계속
  진행**(중복 창이 아무것도 안 뜨는 것보다 낫다). 생성 실패와 이미 존재를 **분리**
- `ReleaseSingleInstanceMutex(HANDLE)` 헬퍼로 nullptr 안전 정리
- `wWinMain` 의 3곳(진입 체크 / `window.Create` 실패 경로 / 정상 종료) 교체
- **ASCII only + 영어 주석**(CLAUDE.md 네이티브 소스 규칙)

**`lib/services/windows_update_service.dart`** (2단계分, 불변조건 2-5)
**이 항목 하나가 기존 매장 전체를 살린다.** `runas` 를 무조건 제거하면 아직
Program Files 에 있는 매장에서 robocopy 가 권한 부족으로 실패하고, bat 이
`:fail → :launch` 로 구버전을 다시 띄우므로 **앱은 살아 있는 채 버전만 영원히
멈춘다.**
- `_isDirectoryWritable(appDir)` 신설: 대상 폴더에 실제 probe 파일을 써 보고 판정.
  판정 실패는 전부 "쓰기 불가"(오판 손해가 UAC 1회로 그치는 안전한 쪽)
- `final needsElevation = !await _isDirectoryWritable(appDir);`
  `final verb = needsElevation ? 'runas' : '';` → VBS 의 `ShellExecute` 4번째 인자로
- **경로 문자열로 "Program Files 인가"를 판정하지 않는다** — 설치 경로는 마법사에서
  바꿀 수 있고 같은 경로라도 ACL 이 다를 수 있다
- VBS 래퍼 자체는 유지(목적이 창 숨김 — 마지막 인자 0). verb 가 빈 문자열이면
  기본 동사로 실행되어 UAC 가 뜨지 않는다
- **어느 경로를 탔는지 `logToFile` 로 남긴다** — 매장 로그만 받아도 그 PC 가 이관
  됐는지 판별할 수 있어야 한다

**변경 불필요 (이번 이식 검토에서 확인 완료)**
- `lib/services/windows_restart_script.dart` / `windows_restart_service.dart` —
  exe 경로를 `Platform.resolvedExecutable` 에서 동적 파생, 설치 경로 가정 없음
- `build_installer.ps1` / `deploy_windows.ps1` — `Program Files`/`LOCALAPPDATA`
  참조가 전부 **빌드 도구**(VS cmake, Inno ISCC) 경로이지 설치된 앱 경로가 아니다.
  kokonut 선례대로 `.iss` 만 바꾸면 된다
- `windows/CMakeLists.txt` — `APPFIT_BRAND_MAMMOTH` 정의 메커니즘은 설치 위치와
  무관

### 3단계 — Defender 예외 자동 등록

Setup 이 더 이상 관리자가 아니므로 `Add-MpPreference` 를 직접 실행할 수 없다.
per-user 전환이 오탐 면제권은 아니므로(1절) 예외 등록은 유지한다.

**`installer/register_defender_exclusion.ps1`** (신규, **UTF-8 BOM**, ASCII only)
- `param($AppDir, $StagingDir, $LogPath)` — **경로를 인자로 받는다**(불변조건 2-7).
  스크립트 안에서 `$env:LOCALAPPDATA` 를 재해석하면 다른 관리자 계정으로 승격됐을
  때 그 관리자 프로필에 예외가 걸리고 운영 계정은 무방비가 된다.
- `Add-MpPreference -ExclusionPath $AppDir, $StagingDir -ErrorVariable addErr`
- 진단 로그 6키 고정 스펙(kokonut 과 동일하게 유지 — 운영 문서 공유):
  `addError` / `winDefend` / `av` / `runningMode` / `tamperProtected` / `exclusions`
- **항상 `exit 0`** — 예외 등록 실패가 설치 실패가 되면 안 된다
- 브랜드 무관(경로가 전부 인자) — 두 브랜드가 같은 스크립트를 다른 인자로 호출

**`installer/appfit_order_agent.iss`** (3단계分)
- `[Tasks]`: `defenderexclusion` 체크박스 추가
- `[Files]`: 스크립트를 `{tmp}` 가 아니라 **`{app}` 에 설치**(나중에 매장에서 수동
  재실행 가능하도록)
- `[Run]`: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File
  "{app}\register_defender_exclusion.ps1" -AppDir "{app}" -StagingDir
  "{localappdata}\{#MyAppDirName}" -LogPath "{app}\defender_exclusion.log"`,
  `Verb: "runas"`, `Flags: shellexec waituntilterminated runhidden`,
  `Tasks: defenderexclusion`. **기존 "지금 실행" 항목보다 앞에** 둔다(첫 실행 전에
  예외가 걸려 있어야 함). 설치 시 UAC 1회, OTA 는 여전히 프롬프트 없음
- `[UninstallRun]` 신규: `Remove-MpPreference` 대응(`RunOnceId` 부여)
- `{localappdata}\{#MyAppDirName}` 이 이미 브랜드별로 다르므로 추가 분기 불필요.
  1단계의 `UpdateConfig._installDirName` 과 값이 일치해야 한다

### 4단계 — 자가진단 + 자동실행 경로 갱신

**`lib/utils/windows_startup_maintenance.dart`** (신규)
`runWindowsStartupMaintenance(PreferenceService)` — Windows 기동 시 1회, 어느
작업도 실패가 기동을 막지 않는다. import 는 전부 `package:appfit_order_agent/...`
형태.

(a) 자동실행 레지스트리 경로 갱신(불변조건 2-8): `launch_at_startup` 은
`HKCU\...\Run` 에 등록 시점 exe 절대경로를 그대로 박는다. 이관된 PC 는 그 값이
삭제된 `C:\Program Files\...` 를 가리켜 **부팅 자동 실행이 조용히 실패**한다.
`prefs.getAutoLaunch()` 가 true 면 `PlatformService.setAutoStartup(true)` 를 한 번
재호출해 덮어쓴다(멱등).

(b) Defender 예외 상태 3상태 진단(불변조건 2-9):

| 상태 | 판정 |
| --- | --- |
| 목록 있고 2경로 모두 포함 | 정상 |
| 목록 있는데 경로 없음 | **미등록.** 조치 필요 |
| 조회 실패 / 목록 비어 있음 | **판정 불가.** 단정하지 않는다 |

`Get-MpPreference` 의 `ExclusionPath` 는 비상승 프로세스에서 조회가 거부되는
경우가 있고 앱은 상승되지 않은 채 돈다. **조회 실패를 미등록으로 오판하지 않는 것이
핵심**이다.
- 대상 2경로: `File(Platform.resolvedExecutable).parent.path` 와
  `UpdateConfig.stagingDir().parent.path`(= `%LOCALAPPDATA%\<_installDirName>`,
  3단계의 `{localappdata}\{#MyAppDirName}` 과 일치)
- 경로 비교는 소문자화 + 후행 `\` 정규화 + prefix 매칭
- **하루 1회 제한** — powershell 프로세스 기동 비용과, 부팅 자동실행 직후 프린터
  연결과의 자원 경합 방지

**`lib/services/preference_service.dart`**
`_keyDefenderCheckDate` + `getDefenderCheckDate()` / `setDefenderCheckDate(String)`
추가. 파일 하단 `// ── Windows 전용 프린터 설정 ──` 헤더 앞에, 이웃한
`_keyComPortName` 의 private 네이밍 컨벤션을 따른다.

**`lib/main.dart`**
`logger.i('PreferenceService 초기화 완료');` 직후에
`await runWindowsStartupMaintenance(preferenceService);` 추가. 이 위치는
`runStartupUpdateFlow()`(업데이트 설치 시 `exit(0)`) **이후**라, 실제 업데이트가
설치되는 회차에는 실행되지 않고 정상 기동 회차에만 돈다 — kokonut 과 같은 순서.

**`installer/appfit_order_agent.iss`** (4단계分)
`[Registry]` 신규 — 언인스톨 시 삭제된 exe 를 가리키는 Run 값이 남지 않도록
`uninsdeletevalue` 로 소유권을 명시한다(불변조건 2-8 후반).

```
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; \
    ValueType: none; ValueName: "AppfitOrderAgent"; \
    Flags: uninsdeletevalue
```

`deletevalue` 는 **붙이지 않는다.** 그 플래그는 *설치 시점*에 값을 지우므로,
재설치·업그레이드마다 점주가 켜 둔 부팅 자동실행이 한 번씩 꺼진다. 필요한 것은
언인스톨 시 정리뿐이다. 값 이름은 [main.dart](../lib/main.dart) 의
`LaunchAtStartup.instance.setup(appName: 'AppfitOrderAgent')` 과 일치해야 한다 —
**브랜드 무관 고정값을 그대로 쓴다**(2절 전제: 한 PC 에 아티팩트가 하나뿐이므로
두 브랜드가 같은 값 이름을 두고 충돌할 일이 없다). `main.dart` 의 `setup()` 호출은
이 단계에서 손대지 않는다.

---

## 5. 불변 조건 (kokonut 계약, appfit 이식 시에도 그대로 지킨다)

1. **설치 경로는 `DefaultDirName` 이 아니라 `PrivilegesRequired` 로 바꾼다** —
   `DefaultDirName={autopf}\<AppDirName>` 은 그대로 두고 `PrivilegesRequired` 만
   `admin` → `lowest`.
2. **`PrivilegesRequiredOverridesAllowed` 를 열지 않는다** — 열면 관리자 권한으로
   Setup 을 실행했을 때 machine-wide 로 되돌아가 전환이 무효화된다.
3. **`AppId` 를 재생성하지 않는다** — per-user 언인스톨 항목은 HKCU 로 가서 HKLM
   구 항목과 하이브가 달라 충돌 안 함. 재생성하면 구설치 감지 자체가 불가능해진다.
4. **구 machine-wide 설치를 감지해 먼저 제거한다** — 조회는 `HKLM64`(Setup 은
   32비트라 `HKLM` 만 쓰면 WOW6432Node 를 봄). 구 언인스톨러는 UAC 1회, 거부는
   설치 중단. 언인스톨 레지스트리 키가 사라질 때까지 폴링(`ewWaitUntilTerminated`
   로는 완료를 알 수 없음).
5. **updater 의 상승 여부는 실제 쓰기 시도로 판정한다** — 경로 문자열로 판정하지
   않는다. 판정 실패는 전부 "쓰기 불가"로 본다. 어느 경로를 탔는지 로그에 남긴다.
6. **단일 인스턴스 뮤텍스는 `Global\` 1차 + `Local\` 폴백** — 생성 실패와 이미
   존재를 분리한다. 둘 다 실패하면 뮤텍스 없이 계속 진행. `AppMutex` 에 두 이름
   모두 나열.
7. **Defender 예외 등록은 상승된 자식 프로세스로 분리한다** — 경로는 인자로 전달
   (스크립트 안에서 재해석 금지). UAC 거부를 설치 실패로 만들지 않는다. 등록 대상은
   설치 폴더 + OTA 스테이징 2경로.
8. **자동 실행 레지스트리 경로를 기동 시 갱신한다** — 이관된 PC 가 삭제된 구경로를
   계속 가리키지 않도록 멱등하게 재등록. `.iss` 에도 `uninsdeletevalue` 를 둔다.
9. **예외 등록 상태를 앱이 스스로 진단한다** — 3상태(정상/미등록/판정불가), 조회
   실패를 미등록으로 단정하지 않는다. 하루 1회로 제한.

---

## 6. 검증 계획 / 결과

**common / mammoth 각각 전부 반복한다** — AppId·뮤텍스·exe명·AppDirName 이
브랜드마다 독립이라 한쪽 검증이 다른 쪽을 보증하지 않는다.

### 실측 결과 요약 (2026-08-27, 공통 브랜드)

운영 OTA 서버는 건드리지 않았다 — `UpdateConfig._base` 를 `127.0.0.1:8099` 로
돌린 **커밋하지 않는 임시 패치**로 테스트 빌드를 만들고, 로컬 정적 서버(Dart)가
버전 JSON/ZIP 을 서빙했다. 설치본 195 ↔ 페이로드 196.

| 항목 | 결과 | 근거 |
| --- | --- | --- |
| 레거시(Program Files) OTA — 상승 경로 | ✅ | 앱 로그 `(관리자 권한 필요 — UAC 프롬프트 발생)` → UAC 1회 → `rc=3` → 재기동 |
| per-user OTA — 무상승 | ✅ | 앱 로그 `(관리자 권한 불필요)` + 생성된 VBS 의 verb 인자가 빈 문자열 |
| 상승 판정이 실제 쓰기 시도 기반인가 | ✅ | 비상승 셸 probe: PF 쓰기 실패 / `%LOCALAPPDATA%\Programs` 쓰기 성공 |
| updater 견고화 | ✅ | `tasklist` 폴링, `/R:3 /W:2` 재시도 2회 후 포기, 로그 append + `rc=` |
| `:fail → :launch` | ✅ | 파일 잠금 유도 → `rc=11` → 앱 재기동. **단 롤백은 아님**(아래 주의) |
| 이관(machine-wide → per-user) | ✅ | HKLM64 키·PF 폴더 소멸, HKCU 등록, 설치 경로 이동 |
| 설정 보존 | ✅ | `shared_preferences.json` 2517 bytes 이관 전후 동일, 로그인 유지 |
| Defender 예외 2경로 등록 | ✅ | `defender_exclusion.log` 의 `addError=` 공백, `exclusions=` 에 설치 폴더 + 스테이징 |
| per-user 설치 모드 계약 | ✅ | Setup 로그 `User privileges: None` / `Administrative install mode: No` / `Install mode root key: HKEY_CURRENT_USER` |
| 자동실행 경로 갱신 | ✅ | stale Run 값(삭제된 PF 경로) → per-user 경로로 자동 교체 |
| 뮤텍스 `Local\` 폴백 | ✅ | `Global\` 을 거부 DACL 로 선점 → 앱 정상 기동 + 2회차 실행은 여전히 1인스턴스 |
| 구설치 감지 키(HKLM64) | ✅ | 진단 전용 Setup 으로 두 브랜드 GUID 모두 `RegKeyExists(HKLM64)=1` + UninstallString 확인 |
| UAC 거부 시 설치 중단 | ✅ | 1차 실행에서 거부 → 중단 안내 노출 |
| 매머드 브랜드 | ⏳ | 미검증 |

> **`:fail` 은 롤백이 아니다.** robocopy 는 exit code 8 이상이어도 일부 파일은 이미
> 복사한 뒤다. 실측(rc=11)에서 exe·`app.so` 는 교체되고 잠긴 파일 하나만 구버전으로
> 남았다. 보장되는 것은 "앱이 다시 뜬다"까지이며, 어떤 파일이 실패했는지는 로그의
> robocopy 오류 줄로만 알 수 있다. 원자적 교체가 필요하면 스테이징 후 폴더 스왑으로
> 바꿔야 하고, 그건 별도 설계 변경이다.

### A. 클린 PC (신규 출고)
1. 설치 — UAC 는 **Defender 예외 단계에서 1회만** 떠야 한다
2. `%LOCALAPPDATA%\Programs\AppfitOrderAgent[Mammoth]\` 에 exe 확인
   (탐색기 주소창에 경로 붙여넣기 — `AppData` 는 숨김 폴더)
3. 같은 폴더 `defender_exclusion.log` 에서 `addError=` 가 비어 있고 `exclusions=`
   에 2경로가 있는지
4. 앱 로그에 `Defender 예외 점검: 정상` 1줄
5. 시작메뉴/바탕화면 바로가기, 제어판 "프로그램 및 기능" 항목 표시
6. 자동실행 토글 → `HKCU\...\Run\AppfitOrderAgent` 값이 새 경로를 가리키는지

### B. 이관 (machine-wide → per-user)
1. 구버전 설치본으로 `C:\Program Files` 에 설치 + 로그인/프린터 설정 남김
2. 새 설치본 → 구설치 감지 안내(브랜드명 정확히 표시) → UAC 1회 → 이관
3. 구 설치 폴더 소멸, HKLM64 언인스톨 키 소멸 확인
4. **로그인 상태·프린터 설정 유지 확인.** 설정은 `%APPDATA%` 에 있고 그 경로는
   exe 버전 정보에서 파생되므로 설치 위치와 무관 — 마이그레이션 코드가 필요 없다
5. **UAC 거부 시 설치 중단 + 안내 노출**(kokonut 미검증 항목 — appfit 최초 검증)
6. 매머드가 실제로 machine-wide 로 배포된 이력이 없다면, 구버전 `.iss` 를 로컬
   재빌드해 합성 시나리오로 검증

### C. OTA 회귀 (핵심)
1. **per-user 설치본**에서 업데이트 → **UAC 없이** 완료·재기동, 앱 로그에
   "관리자 권한 불필요" 확인
2. **구 machine-wide 설치본**에서 업데이트 → 기존대로 UAC 1회 후 정상 완료,
   updater 로그가 `[OK] ... rc=0~7` 로 끝나는지.
   **이 케이스가 깨지면 기존 전 매장이 조용히 멈춘다**
3. robocopy 강제 실패 유도(대상 exe 를 락 건 상태로 업데이트) → `:fail → :launch`
   로 구버전이 다시 뜨는지(1단계 견고화 검증)

### D. 표준 사용자 계정 (kokonut 미검증 — appfit 최초)
1. 표준 사용자로 로그인 → 앱 실행 → 창이 정상적으로 뜨는지(`Local\` 폴백)
2. 두 번 실행 → 기존 창이 포그라운드로 오는지(뮤텍스 정상 감지)
3. 표준 사용자 계정 OTA 가 UAC 없이 끝나는지

### E. 자동화
- `flutter analyze`
- `flutter test test/config/build_brand_scope_test.dart`
  (기본 + `--dart-define=APPFIT_BRAND=mammoth` 재실행)

---

## 7. 배포 시 유의

- `pubspec.yaml` 의 `version` 상향 필요(현재 `3.0.0+195`). Android·Windows 가 버전
  정본을 공유하므로 Windows 만 배포해도 번호는 함께 올라간다.
- 설치본과 OTA exe 해시를 통일하려면 **반드시** 아래 순서로 돌린다(`-SkipBuild`
  는 이번 이식에서 추가됐다):

  ```
  .\build_installer.ps1 -Brand <brand>
  .\deploy_windows.ps1  -Brand <brand> -SkipBuild
  ```

  두 스크립트가 각각 `flutter build` 를 돌리면 MSVC 링커가 PE `TimeDateStamp`/PDB
  GUID 를 새로 새겨 같은 소스인데 해시가 달라진다. Defender 평판은 해시 단위로
  쌓이므로 오탐 표면이 릴리스마다 2배가 된다. `deploy_windows.ps1` 의
  `1-0) 산출물 버전 검증` 게이트가 낡은 Release 폴더를 새 번호로 올리는 사고를
  막는다.

- 이 순서는 이제 **선택이 아니다**. `deploy_windows.ps1` 이 ZIP·버전 JSON 과 함께
  **설치본도 업로드**하기 때문이다(원격 고정명
  `appfit_order_agent[_mammoth]_windows_setup.exe`, Fleet 다운로드 페이지가 링크).
  `dist\` 에 이번 버전 설치본이 없거나 러너 exe 보다 오래됐으면
  `1-0b) 설치본 검증` 이 **아무것도 업로드하지 않고** 중단한다 — 설치본 파일명에는
  빌드번호가 없어 semver 비교로는 낡은 설치본을 못 거르므로 mtime 을 본다.

- **첫 배포 전 확인**: 이 전환은 매장 PC 에서 구설치 제거(UAC 1회)를 동반하므로,
  기존 매장은 OTA 로 자동 이관되지 않는다. OTA 는 계속 Program Files 설치본을
  갱신할 뿐이고(그 경로는 검증됨), per-user 로 옮기려면 **새 설치본을 한 번
  실행**해야 한다. 롤아웃 계획을 여기에 맞춰 잡을 것.

---

## 8. 이식 중 발견해 고친 결함 (2026-08-27 실기 검증)

계획대로 이식만 했으면 넘어갔을 것들이다. **2·3번은 kokonut 정본에도 그대로
있으므로 그쪽에도 반영이 필요하다.**

1. **`install()` 이 flush 없이 `exit(0)` → 진단 로그 통째 유실**
   파일 기록은 버퍼(30줄/2초)를 거치는데 `install()` 은 로그 직후 종료한다.
   하필 그 안에 상승 경로 판정 결과가 있어, "매장 로그만 받아도 이관 여부를
   판별한다"는 목적 자체가 무효였다. `flushLogBuffer()` 호출로 해결.

2. **비상승 `Get-MpPreference` 를 "미등록"으로 오판** ⚠️
   앱은 상승되지 않은 채 도는데, 그 상태에서 Defender 는 목록 대신 안내 문자열
   한 줄(`N/A: Must be an administrator to view exclusions`)을 돌려준다.
   **exitCode 는 0 이고 목록도 비어 있지 않다.** 그래서 3상태 가드 두 개를 모두
   통과해, 예외가 정상 등록된 PC 가 매일 ERROR 레벨로 "미등록"을 남겼다 —
   불변조건 9가 막으려던 바로 그 오판이다. 항목이 경로 모양인지로 판정하도록
   수정(문구는 로캘에 따라 달라질 수 있어 문자열 매칭은 쓰지 않는다).
   덧붙여, 라이브 조회가 사실상 늘 막히므로 설치본이 남긴
   `{app}\defender_exclusion.log` 를 함께 읽어 "설치 시점 기록"을 날짜와 함께
   병기한다(그것으로 "정상"이라 단정하지는 않는다).

3. **Defender 로그 6키가 한 줄로 뭉침** ⚠️
   PowerShell 의 쉼표 연산자가 `+` 보다 강하게 묶여, `@('a='+$x, 'b='+$y)` 가
   `'a=' + ($x,'b=') + $y` 로 파싱된다. 배열이 `$OFS`(공백)로 평탄화되어 요소
   1개짜리 문자열이 되고, 로그 전체가 공백으로 이어진 한 줄이 된다(실측
   `Count=1`). 각 요소를 괄호로 묶어 해결.

4. **`:fail` 로그가 롤백처럼 읽힘**
   "Relaunching previous version" 이라고 적혀 있었지만 robocopy 는 rc≥8 에서도
   일부 파일을 이미 복사한 뒤다. 혼합 상태가 남을 수 있음을 로그에 명시하도록
   문구 정정(6절 주의 참조).
