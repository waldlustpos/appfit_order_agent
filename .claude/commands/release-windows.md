---
description: Windows 릴리즈 빌드 (배포 없이 로컬 빌드만) — 설치본(installer) 또는 Release 폴더 선택, PowerShell
---

이 명령어는 **서버 배포 없이** Windows 릴리즈 산출물을 로컬에서 빌드한다.
OTA 서버 배포는 별도(`/deploy-windows`, `deploy_windows.ps1`)다.
빌드가 끝나면 산출물은 `archive_windows.ps1` 가 **자동으로** 로컬 공용 보관소
(`!Project Files/appfit_order_agent/windows/<버전>/`)에 버전별로 보관하고 노트를 남긴다.

## 1단계 — 산출물 형태 선택

`AskUserQuestion` 으로 어떤 산출물을 만들지 묻는다:

- **installer** — `build_installer.ps1` → Inno Setup 으로 `dist\AppfitOrderAgent-Setup-<semver>.exe` 생성 (신규 설치/재설치용). ISCC(Inno Setup 6) 필요.
- **release_folder** — `build_windows.ps1` → `build\windows\x64\runner\Release` 폴더 빌드 (아카이브 시 `appfit_order_agent_windows.zip` 으로 압축 보관).

단일 exe(`appfit_order_agent.exe`) 단일 빌드가 한국/일본을 모두 서빙한다. 변형
인자·`--dart-define=APPFIT_VARIANT` 는 없다(서버는 앱 로그인 화면에서 런타임 선택).

> Windows 버전 정본은 `version_windows.txt`(`x.y.z+n`)다. pubspec.yaml 아님.

## 2단계 — 빌드 전 상태 확인

Bash 툴로 현재 브랜치 + 최신 커밋 3개를 보여준다:
```
git log --oneline -3
```
`version_windows.txt` 값(빌드될 버전)을 함께 보여주고, "이 상태로 `<산출물>` 빌드하시겠습니까? (yes 입력 시 진행)"라고 묻는다.

## 3단계 — 사용자가 yes 입력 시에만 실행

선택에 따라 **레포 루트에서** PowerShell 스크립트를 실행한다 (Bash 툴에서는 `powershell.exe -NoProfile -ExecutionPolicy Bypass -File` 로 호출):
- installer:       `powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./build_installer.ps1`
- release_folder:  `powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./build_windows.ps1`

> macOS 에는 `pwsh` 가 없을 수 있다. PowerShell 호출이 거부/실패하면, 사용자에게 **Windows 빌드 PC 의 PowerShell 터미널에서 직접** 위 명령을 실행하도록 안내한다.

## 실행 후

- 생성된 산출물 경로(설치본 `.exe` 또는 Release 폴더)와 핵심 파일(`appfit_order_agent.exe`, VC++ 런타임 DLL `vcruntime140.dll`/`vcruntime140_1.dll`/`msvcp140.dll`) 포함 여부를 보고
- **자동 아카이브** 결과를 요약: `!Project Files/appfit_order_agent/windows/<버전>/` 에 산출물 + `release_notes.txt` 가 보관되고 폴더가 열린다
- 빌드 실패 시 오류 메시지를 분석하고 원인·수정 방법을 제안
  - `.env` 누락(APPFIT_AES_KEY, SENTRY_DSN), `version_windows.txt` 형식 오류(`x.y.z+n` 아님), ISCC.exe 미설치(installer) 안내
