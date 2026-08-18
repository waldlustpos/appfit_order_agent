---
description: Windows 릴리즈 빌드 (배포 없이 로컬 빌드만) — 설치본(installer) 또는 Release 폴더 선택, common/mammoth 브랜드 선택, PowerShell
---

이 명령어는 **서버 배포 없이** Windows 릴리즈 산출물을 로컬에서 빌드한다.
OTA 서버 배포는 별도(`/deploy-windows`, `deploy_windows.ps1`)다.
빌드가 끝나면 산출물은 `archive_windows.ps1` 가 **자동으로** 로컬 공용 보관소
(`!Project Files/appfit_order_agent/windows/<브랜드>/<버전>/`)에 버전별로 보관하고 노트를 남긴다.

## 1단계 — 브랜드 + 산출물 형태 선택

`AskUserQuestion` 2개로 묻는다:

- **브랜드**: **common**(기본, `appfit_order_agent.exe`)/**mammoth**(전용,
  `appfit_order_agent_mammoth.exe` — 인스톨러 표시명 `매머드오더 에이전트`).
- **산출물 형태**:
  - **installer** — `build_installer.ps1 -Brand <브랜드>` → Inno Setup 으로
    `dist\AppfitOrderAgent-Setup-<semver>.exe`(common) 또는
    `dist\AppfitOrderAgentMammoth-Setup-<semver>.exe`(mammoth) 생성(신규 설치/재설치용). ISCC(Inno Setup 6) 필요.
  - **release_folder** — `build_windows.ps1 -Brand <브랜드>` → `build\windows\x64\runner\Release` 폴더 빌드 (아카이브 시 `appfit_order_agent_<브랜드>_windows.zip` 으로 압축 보관).

2-티어 아티팩트 모델 — 같은 코드·같은 버전이고 다른 것은 exe명·ProductName·
mutex·인스톨러 GUID·아이콘뿐이다(브랜드 로직은 전부 런타임 `BrandRegistry`).
서버(live/japanLive)는 앱 로그인 화면에서 런타임 선택된다.

> 버전 정본은 `pubspec.yaml` 의 `version`(`x.y.z+n`)이다 (Android/Windows 공통, 브랜드 무관). 구 `version_windows.txt` 는 폐지.

> ⚠️ 브랜드를 전환하며 연속 빌드하면 첫 빌드는 CMake 캐시 정리(sentinel 감지)
> 때문에 콜드 configure 가 끼어 평소보다 느릴 수 있다 — 정상 동작이다.

## 2단계 — 빌드 전 상태 확인

Bash 툴로 현재 브랜치 + 최신 커밋 3개를 보여준다:
```
git log --oneline -3
```
`pubspec.yaml` 의 `version` 값(빌드될 버전)을 함께 보여주고, "이 상태로 <브랜드> <산출물> 빌드하시겠습니까? (yes 입력 시 진행)"라고 묻는다.

## 3단계 — 사용자가 yes 입력 시에만 실행

선택에 따라 **레포 루트에서** PowerShell 스크립트를 실행한다 (Bash 툴에서는 `powershell.exe -NoProfile -ExecutionPolicy Bypass -File` 로 호출):
- installer:       `powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./build_installer.ps1 -Brand <브랜드>`
- release_folder:  `powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./build_windows.ps1 -Brand <브랜드>`

> macOS 에는 `pwsh` 가 없을 수 있다. PowerShell 호출이 거부/실패하면, 사용자에게 **Windows 빌드 PC 의 PowerShell 터미널에서 직접** 위 명령을 실행하도록 안내한다.

## 실행 후

- 생성된 산출물 경로(설치본 `.exe` 또는 Release 폴더)와 핵심 파일(`appfit_order_agent[_mammoth].exe`, VC++ 런타임 DLL `vcruntime140.dll`/`vcruntime140_1.dll`/`msvcp140.dll`) 포함 여부를 보고
- **자동 아카이브** 결과를 요약: `!Project Files/appfit_order_agent/windows/<브랜드>/<버전>/` 에 산출물 + `release_notes.txt` 가 보관되고 폴더가 열린다
- 빌드 실패 시 오류 메시지를 분석하고 원인·수정 방법을 제안
  - `.env` 누락(APPFIT_AES_KEY, SENTRY_DSN), `pubspec.yaml` 의 `version` 형식 오류(`x.y.z+n` 아님), ISCC.exe 미설치(installer) 안내
  - `"generator platform: x64 does not match"` CMake 에러가 나면 브랜드 전환 캐시 정리가 실패한 것 — `build\windows\x64\CMakeCache.txt`/`CMakeFiles` 를 수동 삭제 후 재시도 안내(전체 `build\windows` 삭제는 권장하지 않음 — `_deps` 재fetch 를 동반한 완전 콜드 configure 에서 이 머신은 같은 에러를 실제로 재현한 바 있다)
