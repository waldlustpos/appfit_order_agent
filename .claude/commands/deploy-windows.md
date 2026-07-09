---
description: Windows 릴리즈 빌드(ZIP) 후 Lightsail 서버에 OTA 배포 (단일 채널)
---

이 명령어는 **Windows** Release 빌드를 ZIP으로 압축해 Lightsail 서버에 업로드하는 **비가역적 OTA 배포**다.
Android 배포는 별도(`/deploy-android`, `deploy_apk.sh`), 신규 설치용 인스톨러(`Setup.exe`)도 별도(`build_installer.ps1`)다. 아래 순서를 반드시 지킨다.

## 단일 빌드 · 단일 채널

단일 실행파일(`appfit_order_agent.exe`) 단일 빌드가 한국/일본을 모두 서빙한다.
`-Variant` 인자·`--dart-define=APPFIT_VARIANT` 는 없다. 서버(live/japanLive)는 앱
로그인 화면에서 런타임 선택된다(매장 ID 프리픽스 자동 전환).

OTA 채널은 레거시 무접미 하나다 (`lib/config/update_config.dart`):

| 채널 파일 (ZIP / 버전 JSON) | 용도 |
| --- | --- |
| `appfit_order_agent_windows.zip` / `appfit_order_agent_windows_version.json` | 한국·일본 전 매장 공용 OTA 채널. 기존 설치본이 자연 업데이트됨 |

> **Android 와 정책이 다르다**: Android 는 구 패키지 일본 매장 때문에 무접미
> 레거시 채널을 동결하고 `_release` 채널을 쓰지만, Windows 는 패키지 개념이 없고
> exe명이 기존 설치본과 동일해(`appfit_order_agent.exe`) 레거시 무접미 채널을
> **그대로 계속 사용**한다. 구 `_korea_windows` 채널은 폐기(미사용)됐다.

> ⚠️ **한국/일본 동시 롤아웃**: 채널이 하나이므로 업로드 즉시 양국 매장이 같은
> 빌드로 업데이트된다. 지역별 시차 배포는 불가능하다.

## 1단계 — 배포 전 상태 확인

**(a) 커밋 상태** — Bash 툴로 실행해 현재 브랜치 + 최신 커밋 3개를 보여준다:
```
git log --oneline -3
```

**(b) 버전 비교** — 배포할 빌드번호와 현재 서버 버전을 조회해 명시한다:
- 업데이트할 버전: `version_windows.txt` 의 값(예: `3.3.6+152` → 빌드번호 `152`)을 읽는다. (**Windows 버전 정본 = `version_windows.txt`**, pubspec.yaml 아님. 형식 `x.y.z+n`, `+` 뒤가 빌드번호)
- 현재 서버 버전: `curl -fsS --max-time 10 http://waldpay.kokonutstamp2.com/appfit_order_agent_windows_version.json` (응답 `{"version": <int>}` = 현재 배포된 빌드번호)
- 조회 실패(네트워크/404 등) 시: 실패 사실만 알리고 차단하지 않는다(서버에 아직 파일이 없는 첫 배포일 수 있음).

아래 형식으로 **현재 서버 버전 → 업데이트할 버전** 을 보여준다:

| 현재 서버 버전 | 업데이트할 버전 |
| --- | --- |
| 151 | 152 |

- 업데이트할 빌드번호가 서버 버전보다 **낮거나 같으면 경고**한다(버전 미상향 — OTA가 안 내려가거나 다운그레이드 위험).

**(c) 확인** — 위 (a)·(b)를 함께 보여주고,
"이 상태로 배포하시겠습니까? (yes 입력 시 진행)" 라고 묻는다.

## 2단계 — 사용자가 yes 입력 시에만 실행

`deploy_windows.ps1` 은 PowerShell 스크립트다. **레포 루트에서** PowerShell 로 실행한다 (Bash 툴에서는 `powershell.exe -NoProfile -ExecutionPolicy Bypass -File` 로 호출):
```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./deploy_windows.ps1
```

> 에이전트 셸에서 PowerShell 호출이 거부/실패하면, 사용자에게 **레포 루트의 PowerShell 터미널에서 직접** `.\deploy_windows.ps1` 을 실행하도록 안내한다.

## 실행 후

- 업로드된 ZIP 파일명·버전 JSON(`version=<빌드번호>`)·OTA URL을 요약
- 배포 성공분은 `deploy_windows.ps1` 가 **자동 아카이브**(`archive_windows.ps1`)한다 — `!Project Files/appfit_order_agent/windows/<버전>/` 에 ZIP + `release_notes.txt` 보관 후 폴더가 열린다
- 오류 발생 시 원인 분석 후 수정 방법 제안
  - `.env` 누락(APPFIT_AES_KEY) 시 환경 변수 안내
  - `version_windows.txt` 형식 오류(`x.y.z+n` 아님) 시 형식 안내
  - scp 실패 시 PEM 키(`~/.ssh/LightsailDefaultKey-ap-northeast-3.pem`) 경로·서버 접속 안내
- 사용자가 yes 외 다른 입력을 하면 배포를 취소하고 종료한다
