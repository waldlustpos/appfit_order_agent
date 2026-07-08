---
description: Windows 릴리즈 빌드(ZIP) 후 Lightsail 서버에 OTA 배포 (japan / korea / 둘다 선택)
---

이 명령어는 **Windows** Release 빌드를 ZIP으로 압축해 Lightsail 서버에 업로드하는 **비가역적 OTA 배포**다.
Android 배포는 별도(`/deploy-android`, `deploy_apk.sh`), 신규 설치용 인스톨러(`Setup.exe`)도 별도(`build_installer.ps1`)다. 아래 순서를 반드시 지킨다.

## 배포 변형(variant)

단일 실행파일(`appfit_order_agent.exe`)로 통합되었다. 국가는 `-Variant` 인자 →
`--dart-define=APPFIT_VARIANT` 로만 구분되며, 지역별 서버 기본값이 다르므로 OTA
채널(ZIP + 버전 JSON)만 분리된다:

| 변형 | 실행파일 | 채널 파일 (ZIP / 버전 JSON) | 용도 |
| --- | --- | --- | --- |
| `japan` (기본) | `appfit_order_agent.exe` | `appfit_order_agent_windows.zip` / `appfit_order_agent_windows_version.json` | 일본 매장 OTA. 레거시 채널을 **계속 사용**(동결 아님) |
| `korea` | `appfit_order_agent.exe` | `appfit_order_agent_korea_windows.zip` / `appfit_order_agent_korea_windows_version.json` | 한국 신규 채널(아직 미배포) |

OTA URL 분기는 빌드 타임 `--dart-define=APPFIT_VARIANT` 로 결정된다 (`lib/config/update_config.dart`).

> **Android 와 정책이 다르다**: Android 는 무접미 레거시 채널을 동결하고 `_japan`
> 신규 채널로 옮기지만, Windows japan 은 레거시 무접미 채널을 **그대로 계속 사용**한다.
> Windows 는 패키지 개념이 없고 exe명이 통일되어(`appfit_order_agent.exe`) 기존 japan
> 설치본이 레거시 채널로 자연스럽게 업데이트되기 때문이다. exe명·CMake 는 이제
> 변형과 무관하므로 변형 전환 시 클린 재구성도 없다(증분 빌드).

## 1단계 — 변형 선택

`AskUserQuestion` 으로 어떤 변형을 배포할지 묻는다:
- **japan** — 일본 운영 채널 (현재 유일한 라이브, 대부분의 경우)
- **korea** — 한국 신규 병존 설치 채널 (미배포)
- **둘다** — japan 먼저, 성공 시 korea 순차 배포

## 2단계 — 배포 전 상태 확인

**(a) 커밋 상태** — Bash 툴로 실행해 현재 브랜치 + 최신 커밋 3개를 보여준다:
```
git log --oneline -3
```

**(b) 버전 비교** — 배포할 빌드번호와 현재 서버 버전을 **선택한 변형의 채널별로** 조회해 명시한다:
- 업데이트할 버전: `version_windows.txt` 의 값(예: `3.3.6+152` → 빌드번호 `152`)을 읽는다. (**Windows 버전 정본 = `version_windows.txt`**, pubspec.yaml 아님. 형식 `x.y.z+n`, `+` 뒤가 빌드번호)
- 현재 서버 버전: 변형에 해당하는 버전 JSON을 조회한다 (응답 `{"version": <int>}` = 현재 배포된 빌드번호):
  - japan: `curl -fsS --max-time 10 http://waldpay.kokonutstamp2.com/appfit_order_agent_windows_version.json`
  - korea: `curl -fsS --max-time 10 http://waldpay.kokonutstamp2.com/appfit_order_agent_korea_windows_version.json`
  - "둘다" 선택 시 두 채널 모두 조회한다.
- 조회 실패(네트워크/404 등) 시: 실패 사실만 알리고 차단하지 않는다(서버에 아직 파일이 없는 첫 배포일 수 있음).

아래 형식으로 변형별 **현재 서버 버전 → 업데이트할 버전** 을 표로 보여준다:

| 변형 | 현재 서버 버전 | 업데이트할 버전 |
| --- | --- | --- |
| japan | 151 | 152 |

- 업데이트할 빌드번호가 서버 버전보다 **낮거나 같으면 경고**한다(버전 미상향 — OTA가 안 내려가거나 다운그레이드 위험).

**(c) 확인** — 위 (a)·(b)와 **선택한 변형**을 함께 보여주고,
"이 상태로 `<선택한 변형>` 배포하시겠습니까? (yes 입력 시 진행)" 라고 묻는다.

## 3단계 — 사용자가 yes 입력 시에만 실행

`deploy_windows.ps1` 은 PowerShell 스크립트다. **레포 루트에서** PowerShell 로 실행한다 (Bash 툴에서는 `powershell.exe -NoProfile -ExecutionPolicy Bypass -File` 로 호출):
- japan: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./deploy_windows.ps1 -Variant japan`
- korea: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./deploy_windows.ps1 -Variant korea`
- 둘다: japan 실행·성공 확인 후 korea
  - japan 단계가 실패하면 korea 는 실행하지 않고 중단·보고한다.

> 에이전트 셸에서 PowerShell 호출이 거부/실패하면, 사용자에게 **레포 루트의 PowerShell 터미널에서 직접** `.\deploy_windows.ps1 -Variant <변형>` 을 실행하도록 안내한다.

## 실행 후

- 변형별로 업로드된 ZIP 파일명·버전 JSON(`version=<빌드번호>`)·OTA URL을 요약
- 배포 성공분은 `deploy_windows.ps1` 가 **자동 아카이브**(`archive_windows.ps1`)한다 — `!Project Files/appfit_order_agent/windows/<버전>/` 에 ZIP + `release_notes_<변형>.txt` 보관 후 폴더가 열린다
- 오류 발생 시 원인 분석 후 수정 방법 제안
  - `.env` 누락(APPFIT_AES_KEY) 시 환경 변수 안내
  - `version_windows.txt` 형식 오류(`x.y.z+n` 아님) 시 형식 안내
  - scp 실패 시 PEM 키(`~/.ssh/LightsailDefaultKey-ap-northeast-3.pem`) 경로·서버 접속 안내
- 사용자가 yes 외 다른 입력을 하면 배포를 취소하고 종료한다
