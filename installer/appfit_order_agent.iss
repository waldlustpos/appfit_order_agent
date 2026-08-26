; ----------------------------------------------------------------------
; Appfit Order Agent -- Inno Setup 6 script
;
; Build:
;   ISCC.exe /DMyAppVersion=3.2.1 /DAppfitBrand=common installer\appfit_order_agent.iss
;   ISCC.exe /DMyAppVersion=3.2.1 /DAppfitBrand=mammoth installer\appfit_order_agent.iss
; Output:
;   dist\AppfitOrderAgent-Setup-<version>.exe          (common)
;   dist\AppfitOrderAgentMammoth-Setup-<version>.exe   (mammoth)
;
; Notes:
;   - Region (KR/JP) never affects this build - the server (live/japanLive) is
;     selected at runtime on the app's login screen.
;   - Brand axis (AppfitBrand, default "common") mirrors the Android product
;     flavor (lib/config/build_brand.dart). Each brand gets its own AppId,
;     exe name and install folder because it is an INDEPENDENT ARTIFACT --
;     NOT because the two are meant to coexist. One machine runs exactly one
;     artifact; that is a settled operational rule, and nothing here defends
;     against the two being installed side by side.
;   - Do NOT regenerate an existing brand's MyAppId; changing it causes
;     duplicate entries in "Programs and Features", and it would also make
;     the legacy machine-wide install undetectable (see [Code] below).
;     Retired GUIDs must never be reused:
;       korea (retired 2026-07):    {{E448C213-990C-AEED-03A8-6A695F9EED14}
;   - AppMutex must match BOTH mutex names in windows/runner/main.cpp
;     (Global\ and Local\) for the same brand.
;   - This is a PER-USER install (see PrivilegesRequired below). Rationale and
;     the migration path from the old machine-wide install are in
;     docs/WINDOWS_PERUSER_INSTALL.md.
; ----------------------------------------------------------------------

#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif
#ifndef AppfitBrand
  #define AppfitBrand "common"
#endif

; Both single-instance mutex names from windows/runner/main.cpp are listed in
; MyAppMutex. The app falls back to the Local\ namespace when it cannot create
; a Global\ object (standard user accounts lack SeCreateGlobalPrivilege), so
; Setup has to look for both to reliably notice a running instance. AppMutex
; takes a comma-separated list.
;
; MyAppIdRaw is the GUID without Inno's leading-brace escape. [Code] Pascal
; string literals do not get that escape treatment, so the two spellings
; cannot be shared -- MyAppId is assembled from MyAppIdRaw below.
#if AppfitBrand == "mammoth"
  #define MyAppName        "매머드오더 에이전트"
  #define MyAppExeName     "appfit_order_agent_mammoth.exe"
  #define MyAppMutex       "Global\AppfitOrderAgent_Mammoth_SingleInstance_Mutex,Local\AppfitOrderAgent_Mammoth_SingleInstance_Mutex"
  ; Generated once via PowerShell [guid]::NewGuid() on 2026-08-18. Permanent -
  ; never regenerate (see warning above).
  #define MyAppIdRaw       "{B9F9381A-7444-4FE6-B7C9-2A5881B79C18}"
  #define MyAppDirName     "AppfitOrderAgentMammoth"
  #define MyOutputBaseName "AppfitOrderAgentMammoth-Setup-" + MyAppVersion
  ; Setup.exe's own icon. Must follow the brand like every other identity
  ; field here - the app exe already gets this same .ico via Runner.rc's
  ; APPFIT_BRAND_MAMMOTH branch (windows/CMakeLists.txt).
  #define MySetupIcon      "..\windows\runner\resources\app_icon_mammoth.ico"
#else
  #define MyAppName        "Appfit Order Agent"
  #define MyAppExeName     "appfit_order_agent.exe"
  #define MyAppMutex       "Global\AppfitOrderAgent_SingleInstance_Mutex,Local\AppfitOrderAgent_SingleInstance_Mutex"
  #define MyAppIdRaw       "{8E19A1C4-AFDA-4061-B0FF-186FB71B1745}"
  #define MyAppDirName     "AppfitOrderAgent"
  #define MyOutputBaseName "AppfitOrderAgent-Setup-" + MyAppVersion
  #define MySetupIcon      "..\windows\runner\resources\app_icon.ico"
#endif

#define MyAppId          "{" + MyAppIdRaw

#define MyAppPublisher  "waldlust"
#define MyAppURL        "http://waldpay.kokonutstamp2.com/"

[Setup]
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
VersionInfoVersion={#MyAppVersion}
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription={#MyAppName} Installer
VersionInfoProductName={#MyAppName}

; === Per-user install ===
; PrivilegesRequired=lowest turns every auto* constant below into its user
; equivalent, so DefaultDirName resolves to
;   %LOCALAPPDATA%\Programs\{#MyAppDirName}
; and the Start Menu group lands in the user's profile instead of
; C:\ProgramData. DefaultDirName itself is deliberately left as {autopf} --
; the install location is switched through PrivilegesRequired, not by
; hardcoding a user path.
;
; That is the whole point of this build: the app can then replace its own
; files during an OTA update without elevation, which removes the VBS "runas"
; + hidden cmd pattern that most likely fed the 2026-08
; Trojan:Win32/Bearfoos.A!ml machine-learning false positive.
;
; Do NOT add PrivilegesRequiredOverridesAllowed. Opening that flips the
; install mode back to machine-wide whenever Setup happens to be started
; elevated ("Run as administrator"), which would silently undo all of this.
DefaultDirName={autopf}\{#MyAppDirName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

; === Output ===
OutputDir=..\dist
OutputBaseFilename={#MyOutputBaseName}
Compression=lzma2/ultra
SolidCompression=yes

; === Wizard UI ===
SetupIconFile={#MySetupIcon}
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}
WizardStyle=modern
ShowLanguageDialog=no

; === Single-instance handling ===
AppMutex={#MyAppMutex}
CloseApplications=yes
CloseApplicationsFilter=*.exe
RestartApplications=no

[Languages]
Name: "korean";  MessagesFile: "compiler:Languages\Korean.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "바탕화면에 바로가기 만들기"; \
    GroupDescription: "추가 아이콘:"; Flags: checkedonce
Name: "defenderexclusion"; \
    Description: "Windows 보안(Defender) 검사 예외 등록 (권장)"; \
    GroupDescription: "보안 설정:"

[Files]
; Flutter Windows Release output (exe, dlls, data/ recursively).
; VC++ runtime DLLs pre-bundled by build_installer.ps1.
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; \
    Flags: ignoreversion recursesubdirs createallsubdirs

; Defender exclusion helper. Shipped into {app} rather than {tmp} so that the
; same script can be re-run by hand on a store PC later. Brand-agnostic - both
; brands ship the identical script and pass different paths.
Source: "register_defender_exclusion.ps1"; DestDir: "{app}"; \
    Flags: ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; \
    IconFilename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; \
    IconFilename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
; Register the Defender scan exclusions.
;
; Setup itself is NOT elevated any more (PrivilegesRequired=lowest) but
; Add-MpPreference needs admin, so the work is pushed into an elevated child
; through the "runas" verb. That costs exactly one UAC prompt, at install time
; only, on a PC being prepared before shipment. OTA updates stay prompt-free,
; which is the point of the per-user layout.
;
; The install paths are passed as arguments instead of being re-derived inside
; the script: if the UAC prompt is answered with a DIFFERENT administrator
; account, $env:LOCALAPPDATA in that elevated process points at the
; administrator's profile and the operator account stays uncovered.
;
; The staging path must match UpdateConfig.installDirName in
; lib/config/update_config.dart - test/config/build_brand_scope_test.dart
; asserts the two agree, because a mismatch leaves the OTA working folder
; unprotected with no visible symptom.
;
; Refusing the UAC prompt is not an install failure -- the app runs fine
; without the exclusion, it is just unprotected against a repeat of the
; 2026-08 false positive. The outcome is recorded in
; {app}\defender_exclusion.log.
;
; This entry must precede the "run now" entry so the exclusion is already in
; place the first time the app starts.
Filename: "powershell.exe"; \
    Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\register_defender_exclusion.ps1"" -AppDir ""{app}"" -StagingDir ""{localappdata}\{#MyAppDirName}"" -LogPath ""{app}\defender_exclusion.log"""; \
    Verb: "runas"; \
    StatusMsg: "Windows 보안 예외 등록 중..."; \
    Flags: shellexec waituntilterminated runhidden; \
    Tasks: defenderexclusion

Filename: "{app}\{#MyAppExeName}"; Description: "지금 실행"; \
    Flags: nowait postinstall skipifsilent

[UninstallRun]
; Drop the exclusions again so an uninstalled app leaves no standing scan
; exemption behind. Needs the same elevation as the registration.
; RunOnceId is mandatory for [UninstallRun] entries.
Filename: "powershell.exe"; \
    Parameters: "-NoProfile -ExecutionPolicy Bypass -Command ""Remove-MpPreference -ExclusionPath '{app}','{localappdata}\{#MyAppDirName}' -ErrorAction SilentlyContinue"""; \
    Verb: "runas"; \
    Flags: shellexec waituntilterminated runhidden; \
    RunOnceId: "RemoveDefenderExclusion"

[UninstallDelete]
; Remove the install folder only. User settings in
; %APPDATA%\co.kr.waldlust.order\{#MyAppExeName untranslated to ProductName,
; see Runner.rc APPFIT_PRODUCT_NAME}\ are preserved so that a reinstall keeps
; the login token, printer config, etc. Each brand has its own ProductName,
; so the two brands' settings never collide.
Type: filesandordirs; Name: "{app}"

[Code]
// ------------------------------------------------------------------
// Migration away from the old machine-wide install.
//
// Builds up to 3.0.0 installed into C:\Program Files\{#MyAppDirName} with
// PrivilegesRequired=admin, so their uninstall entry lives under HKLM. This
// build is per-user and registers under HKCU, which means the two would
// happily coexist: two entries in "Programs and Features", two copies on
// disk, and an OTA update that keeps refreshing whichever copy the shortcut
// happens to point at. So the old one is removed first.
//
// Settings are NOT touched by this. They live in
// %APPDATA%\co.kr.waldlust.order\<ProductName>\, a path derived from the exe
// version info rather than from the install directory, and the old
// uninstaller only deletes its own app folder. The login token and printer
// configuration survive the move.
//
// Written once, not per brand: the preprocessor has already resolved
// MyAppIdRaw and MyAppName for whichever brand is being compiled.
//
// Only line comments are used in this section. Brace comments would collide
// with the preprocessor, which rewrites brace-hash sequences anywhere in the
// file including inside comments.
// ------------------------------------------------------------------

const
  LegacyUninstallSubkey =
    'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{#MyAppIdRaw}_is1';
  LegacyRemovalTimeoutMs = 60000;
  LegacyPollIntervalMs = 500;
  // Line break for the message boxes below. Named rather than inlined: the
  // preprocessor reads any line whose first non-blank character is a hash as
  // a directive, so a wrapped string literal must never begin a line with a
  // character-code escape.
  CRLF = #13#10;

// Setup is a 32-bit process, so HKLM alone would read the WOW6432Node view.
// The old installer was ArchitecturesInstallIn64BitMode and wrote to the
// 64-bit view; HKLM64 is what actually finds it.
function LegacyMachineInstallExists(): Boolean;
begin
  Result := RegKeyExists(HKLM64, LegacyUninstallSubkey);
end;

function GetLegacyUninstaller(): String;
var
  Value: String;
begin
  Result := '';
  if RegQueryStringValue(HKLM64, LegacyUninstallSubkey,
       'UninstallString', Value) then
    Result := RemoveQuotes(Value);
end;

function RemoveLegacyInstall(var ErrorMessage: String): Boolean;
var
  Uninstaller: String;
  ResultCode: Integer;
  Elapsed: Integer;
begin
  Result := False;
  ErrorMessage := '';

  Uninstaller := GetLegacyUninstaller();
  if Uninstaller = '' then
  begin
    ErrorMessage :=
      '이전 버전의 제거 프로그램을 찾지 못했습니다.' + CRLF +
      '제어판 > 프로그램 및 기능에서 "{#MyAppName}" 을(를) 먼저 제거한 뒤' +
      ' 다시 설치해 주세요.';
    Exit;
  end;

  // The old uninstaller is PrivilegesRequired=admin, so Windows raises the
  // UAC prompt here. ShellExec returns False when it is refused.
  if not ShellExec('', Uninstaller,
       '/VERYSILENT /NORESTART /SUPPRESSMSGBOXES', '', SW_SHOW,
       ewWaitUntilTerminated, ResultCode) then
  begin
    ErrorMessage :=
      '이전 버전 제거가 취소되었습니다.' + CRLF +
      '관리자 권한 요청(UAC)에 "예" 를 눌러야 이전 버전을 제거할 수 있습니다.' +
      CRLF + '설치를 다시 실행해 주세요.';
    Exit;
  end;

  // The Inno uninstaller copies itself to %TEMP% and relaunches, so the
  // process we waited on has already exited while the real removal is still
  // running. Poll the registry key instead of trusting the exit code.
  Elapsed := 0;
  while (Elapsed < LegacyRemovalTimeoutMs) and LegacyMachineInstallExists() do
  begin
    Sleep(LegacyPollIntervalMs);
    Elapsed := Elapsed + LegacyPollIntervalMs;
  end;

  if LegacyMachineInstallExists() then
  begin
    ErrorMessage :=
      '이전 버전 제거가 시간 내에 끝나지 않았습니다.' + CRLF +
      '제거가 끝난 것을 확인한 뒤 설치를 다시 실행해 주세요.';
    Exit;
  end;

  Result := True;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ErrorMessage: String;
begin
  Result := '';

  if not LegacyMachineInstallExists() then
    Exit;

  if MsgBox(
       '이전 버전이 C:\Program Files 에 설치되어 있습니다.' + CRLF +
       '이번 버전은 관리자 권한 없이 업데이트되도록 사용자 폴더에 설치됩니다.' +
       CRLF + CRLF +
       '이전 버전을 먼저 제거할까요?' + CRLF +
       '(로그인 정보와 프린터 설정은 그대로 유지됩니다. 제거 과정에서' +
       ' 관리자 권한 요청 창이 한 번 뜹니다.)',
       mbConfirmation, MB_YESNO) <> IDYES then
  begin
    Result :=
      '이전 버전을 제거하지 않으면 설치를 계속할 수 없습니다.' + CRLF +
      '두 버전이 동시에 설치되면 업데이트가 엉뚱한 쪽에 적용됩니다.';
    Exit;
  end;

  if not RemoveLegacyInstall(ErrorMessage) then
    Result := ErrorMessage;
end;
