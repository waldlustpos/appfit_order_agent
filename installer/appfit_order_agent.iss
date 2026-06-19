; ----------------------------------------------------------------------
; Appfit Order Agent -- Inno Setup 6 script
;
; Build (update variant, default):
;   ISCC.exe /DMyAppVersion=3.2.1 installer\appfit_order_agent.iss
; Build (standalone variant, coexists with the old/update app):
;   ISCC.exe /DMyAppVersion=3.2.1 /DStandalone=1 installer\appfit_order_agent.iss
; Output:
;   dist\AppfitOrderAgent-Setup-<version>.exe            (update)
;   dist\AppfitOrderAgentStandalone-Setup-<version>.exe  (standalone)
;
; Notes:
;   - Each variant's AppId is a permanent GUID. Do NOT regenerate; changing it
;     causes duplicate entries in "Programs and Features". The two variants use
;     different AppIds on purpose so they install/uninstall independently.
;   - AppMutex must match the constant defined in
;     windows/runner/main.cpp (kSingleInstanceMutexName) for each variant.
;   - The Korean AppName is kept inside this UTF-8 .iss (not passed via /D) so
;     the console code page cannot corrupt it.
; ----------------------------------------------------------------------

#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif

#ifdef Standalone
  #define MyAppName        "Appfit Order Agent"
  #define MyAppExeName     "appfit_order_agent_standalone.exe"
  #define MyAppMutex       "Global\AppfitOrderAgentStandalone_SingleInstance_Mutex"
  #define MyAppId          "{{E448C213-990C-AEED-03A8-6A695F9EED14}"
  #define MyAppDirName     "AppfitOrderAgentStandalone"
  #define MyOutputBaseName "AppfitOrderAgentStandalone-Setup-" + MyAppVersion
#else
  #define MyAppName        "Appfit Order Agent"
  #define MyAppExeName     "appfit_order_agent.exe"
  #define MyAppMutex       "Global\AppfitOrderAgent_SingleInstance_Mutex"
  #define MyAppId          "{{8E19A1C4-AFDA-4061-B0FF-186FB71B1745}"
  #define MyAppDirName     "AppfitOrderAgent"
  #define MyOutputBaseName "AppfitOrderAgent-Setup-" + MyAppVersion
#endif

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

; === System-wide install ===
DefaultDirName={autopf}\{#MyAppDirName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

; === Output ===
OutputDir=..\dist
OutputBaseFilename={#MyOutputBaseName}
Compression=lzma2/ultra
SolidCompression=yes

; === Wizard UI ===
#ifdef Standalone
SetupIconFile=..\windows\runner\resources\app_icon_standalone.ico
#else
SetupIconFile=..\windows\runner\resources\app_icon.ico
#endif
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

[Files]
; Flutter Windows Release output (exe, dlls, data/ recursively).
; VC++ runtime DLLs pre-bundled by build_installer.ps1.
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; \
    Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; \
    IconFilename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; \
    IconFilename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "지금 실행"; \
    Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Remove the install folder only. User settings in
; %APPDATA%\co.kr.waldlust.order\appfit_order_agent\ are preserved
; so that a reinstall keeps the login token, printer config, etc.
Type: filesandordirs; Name: "{app}"
