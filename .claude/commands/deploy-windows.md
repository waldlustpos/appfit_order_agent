---
description: Windows 릴리즈 빌드(ZIP) 후 Lightsail 서버에 OTA 배포 (common/mammoth 브랜드 선택, 아티팩트당 채널 1세트)
---

이 명령어는 **Windows** Release 빌드를 ZIP으로 압축해 Lightsail 서버에 업로드하는 **비가역적 OTA 배포**다.
Android 배포는 별도(`/deploy-android`, `deploy_apk.sh`), 신규 설치용 인스톨러(`Setup.exe`)도 별도(`/release-windows`, `build_installer.ps1`)다. 아래 순서를 반드시 지킨다.

## 2-티어 아티팩트 · 아티팩트당 채널 1세트

Tier 0(공통)과 Tier 1(매머드 전용)은 같은 코드·같은 버전이고, 다른 것은
exe명·ProductName·mutex뿐이다(브랜드 로직은 전부 런타임 `BrandRegistry`).
서버(live/japanLive)는 앱 로그인 화면에서 런타임 선택된다(매장 ID 프리픽스 자동 전환).

OTA 채널은 아티팩트마다 하나다 (`lib/config/update_config.dart`):

| 브랜드 | 채널 파일 (ZIP / 버전 JSON) | 용도 |
| --- | --- | --- |
| common | `appfit_order_agent_windows.zip` / `appfit_order_agent_windows_version.json` | 한국·일본 전 매장 공용. **레거시 무접미 채널 — 계속 사용(동결 아님)**. 기존 설치본이 자연 업데이트됨 |
| mammoth | `appfit_order_agent_mammoth_windows.zip` / `appfit_order_agent_mammoth_windows_version.json` | 매머드 전용(신설) |

> **Android 와 정책이 다르다**: Android 는 구 패키지 일본 매장 때문에 공통이
> 무접미 레거시 채널을 동결하고 `_release` 채널을 쓰지만, Windows 는 패키지
> 개념이 없고 exe명이 기존 설치본과 동일해(`appfit_order_agent.exe`) 공통은
> 레거시 무접미 채널을 **그대로 계속 사용**한다. 매머드는 exe명 자체가 달라
> (`appfit_order_agent_mammoth.exe`) 공통 채널의 ZIP 을 받아도 자연 업데이트가
> 걸리지 않으므로 전용 채널이 신설됐다. 구 `_korea_windows` 채널은 폐기(미사용)됐다.

> ⚠️ **한국/일본 동시 롤아웃**: 한 채널 안에서는 지역 구분이 없으므로 업로드
> 즉시 양국 매장이 같은 빌드로 업데이트된다. 지역별 시차 배포는 불가능하다.

## 1단계 — 브랜드 선택

`AskUserQuestion` 으로 묻는다: **common**(기본)/**mammoth**.

## 2단계 — 배포 전 상태 확인

**(a) 커밋 상태** — Bash 툴로 실행해 현재 브랜치 + 최신 커밋 3개를 보여준다:
```
git log --oneline -3
```

**(b) 버전 비교** — 배포할 빌드번호와 현재 서버 버전을 조회해 명시한다. 선택한
브랜드의 채널 URL을 쓴다:
- 업데이트할 버전: `pubspec.yaml` 의 `version` 값(예: `3.0.0+161` → 빌드번호 `161`)을 읽는다. (**버전 정본 = `pubspec.yaml`**, Android/Windows 공통, 브랜드 무관. 형식 `x.y.z+n`, `+` 뒤가 빌드번호. 구 `version_windows.txt` 는 폐지)
- 현재 서버 버전:
  ```
  curl -fsS --max-time 10 http://waldpay.kokonutstamp2.com/appfit_order_agent_windows_version.json          # common
  curl -fsS --max-time 10 http://waldpay.kokonutstamp2.com/appfit_order_agent_mammoth_windows_version.json  # mammoth
  ```
  (응답 `{"version": <int>}` = 현재 배포된 빌드번호)
- 조회 실패(네트워크/404 등) 시: 실패 사실만 알리고 차단하지 않는다(서버에 아직 파일이 없는 첫 배포일 수 있음 — 매머드 채널은 아직 한 번도 채워지지 않았을 수 있다).

아래 형식으로 **현재 서버 버전 → 업데이트할 버전** 을 보여준다:

| 현재 서버 버전 | 업데이트할 버전 |
| --- | --- |
| 151 | 152 |

- 업데이트할 빌드번호가 서버 버전보다 **낮거나 같으면 경고**한다(버전 미상향 — OTA가 안 내려가거나 다운그레이드 위험).

**(c) 확인** — 위 (a)·(b)를 함께 보여주고,
"이 상태로 <브랜드> 배포하시겠습니까? (yes 입력 시 진행)" 라고 묻는다.

## 3단계 — 사용자가 yes 입력 시에만 실행

`deploy_windows.ps1` 은 PowerShell 스크립트다. **레포 루트에서** PowerShell 로 실행한다 (Bash 툴에서는 `powershell.exe -NoProfile -ExecutionPolicy Bypass -File` 로 호출):
```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./deploy_windows.ps1 -Brand common
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./deploy_windows.ps1 -Brand mammoth
```

> 에이전트 셸에서 PowerShell 호출이 거부/실패하면, 사용자에게 **레포 루트의 PowerShell 터미널에서 직접** `.\deploy_windows.ps1 -Brand <브랜드>` 을 실행하도록 안내한다.

### 설치본과 같은 릴리즈를 낼 때는 `-SkipBuild`

같은 버전의 **설치본(Setup.exe)과 OTA ZIP 을 함께 낼 때**는 이 순서로 돌린다:

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./build_installer.ps1 -Brand <브랜드>
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./deploy_windows.ps1 -Brand <브랜드> -SkipBuild
```

두 스크립트가 각각 `flutter build` 를 돌리면 러너 exe 가 두 번 링크되는데, MSVC
링커는 링크마다 PE 헤더의 `TimeDateStamp` 와 PDB 서명 GUID 를 새로 새긴다.
소스가 같아도 두 산출물의 해시가 달라지고(크기는 같다), **Defender 평판은 해시
단위로 쌓이므로** 릴리즈마다 평판 0 인 바이너리가 둘 생겨 오탐 신고도 두 건을
내야 한다. `-SkipBuild` 는 그 두 번째 빌드를 생략해 설치본과 ZIP 이 문자 그대로
같은 exe 를 담게 한다.

> `-SkipBuild` 의 위험은 **낡은 Release 폴더를 새 버전 번호로 올리는 것**이다.
> 그러면 version JSON 은 새 빌드번호를 가리키는데 매장이 받는 바이너리는
> 구버전이라, 업데이트를 받아도 같은 팝업을 계속 본다. 스크립트의
> `1-0) 산출물 버전 검증` 단계가 exe 의 `ProductVersion` 과 `pubspec.yaml` 의
> `version` 을 대조해 업로드 전에 중단시킨다(두 모드 모두에서 동작).

## 실행 후

- 업로드된 ZIP 파일명·버전 JSON(`version=<빌드번호>`)·OTA URL을 요약
- 배포 성공분은 `deploy_windows.ps1` 가 **자동 아카이브**(`archive_windows.ps1`)한다 — `!Project Files/appfit_order_agent/windows/<브랜드>/<버전>/` 에 ZIP + `release_notes.txt` 보관 후 폴더가 열린다
- 오류 발생 시 원인 분석 후 수정 방법 제안
  - `.env` 누락(APPFIT_AES_KEY) 시 환경 변수 안내
  - `pubspec.yaml` 의 `version` 형식 오류(`x.y.z+n` 아님) 시 형식 안내
  - scp 실패 시 PEM 키(`~/.ssh/LightsailDefaultKey-ap-northeast-3.pem`) 경로·서버 접속 안내
  - `"generator platform: x64 does not match"` CMake 에러가 나면 브랜드 전환 캐시 정리가 실패한 것 — `build\windows\x64\CMakeCache.txt`/`CMakeFiles` 를 수동 삭제 후 재시도 안내
- 사용자가 yes 외 다른 입력을 하면 배포를 취소하고 종료한다
