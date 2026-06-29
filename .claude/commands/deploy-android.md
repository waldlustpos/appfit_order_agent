---
description: Android 릴리즈 APK 빌드 후 Lightsail 서버에 배포 (update / standalone / 둘다 선택)
---

이 명령어는 **Android** APK를 빌드해 Lightsail 서버에 업로드하는 **비가역적 배포**다.
Windows 배포는 별도 (`deploy_windows.ps1`). 아래 순서를 반드시 지킨다.

## 배포 변형(flavor)

`deploy_apk.sh` 는 변형 인자를 받는다. 변형마다 **별도 OTA 채널**로 업로드된다:

| 변형 | 패키지 | 채널 파일 | 용도 |
| --- | --- | --- | --- |
| `update` | `co.kr.waldlust.order.receive` | `appfit_order_agent_version.json` / `.apk` | 기존 900+ 매장 OTA (구앱 덮어쓰기) |
| `standalone` | `co.kr.waldlust.order.receive.appfit` | `appfit_order_agent_standalone_version.json` / `_standalone.apk` | 구앱과 병존 설치 (사전 설치용) |

OTA URL 분기는 빌드 타임 `--dart-define=APPFIT_VARIANT` 로 결정되며, 스크립트가 flavor에 맞춰 자동 주입한다 (`lib/config/ota_config.dart`).

## 1단계 — 변형 선택

`AskUserQuestion` 으로 어떤 변형을 배포할지 묻는다:
- **update** — 운영 채널 (대부분의 경우)
- **standalone** — 병존 설치 채널
- **둘다** — update 먼저, 성공 시 standalone 순차 배포

## 2단계 — 배포 전 상태 확인

**(a) 커밋 상태** — Bash 툴로 실행해 현재 브랜치 + 최신 커밋 3개를 보여준다:
```
git log --oneline -3
```

**(b) 버전 비교** — 배포할 빌드번호와 현재 서버 버전을 **선택한 변형의 채널별로** 조회해 명시한다:
- 업데이트할 버전: `pubspec.yaml` 의 `version`(예: `3.3.5+148` → 빌드번호 `148`)을 읽는다. (Android 버전 정본 = pubspec.yaml)
- 현재 서버 버전: 변형에 해당하는 버전 JSON을 조회한다 (응답 `{"version": <int>}` = 현재 배포된 빌드번호):
  - update: `curl -fsS --max-time 10 http://waldpay.kokonutstamp2.com/appfit_order_agent_version.json`
  - standalone: `curl -fsS --max-time 10 http://waldpay.kokonutstamp2.com/appfit_order_agent_standalone_version.json`
  - "둘다" 선택 시 두 채널 모두 조회한다.
- 조회 실패(네트워크/404 등) 시: 실패 사실만 알리고 차단하지 않는다(서버에 아직 파일이 없는 첫 배포일 수 있음).

아래 형식으로 변형별 **현재 서버 버전 → 업데이트할 버전** 을 표로 보여준다:

| 변형 | 현재 서버 버전 | 업데이트할 버전 |
| --- | --- | --- |
| update | 147 | 148 |

- 업데이트할 빌드번호가 서버 버전보다 **낮거나 같으면 경고**한다(버전 미상향 — OTA가 안 내려가거나 다운그레이드 위험).

**(c) 확인** — 위 (a)·(b)와 **선택한 변형**을 함께 보여주고,
"이 상태로 `<선택한 변형>` 배포하시겠습니까? (yes 입력 시 진행)" 라고 묻는다.

## 3단계 — 사용자가 yes 입력 시에만 실행

선택에 따라 Bash 툴로 실행한다:
- update: `./deploy_apk.sh update`
- standalone: `./deploy_apk.sh standalone`
- 둘다: `./deploy_apk.sh update` 실행·성공 확인 후 `./deploy_apk.sh standalone`
  - update 단계가 실패하면 standalone 은 실행하지 않고 중단·보고한다.

## 실행 후

- 변형별로 업로드된 APK 파일명·버전 JSON(`version=<빌드번호>`)·OTA URL을 요약
- 배포 성공분은 `deploy_apk.sh` 가 **자동 아카이브**(`archive_apk.sh`)한다 — `!Project Files/appfit_order_agent/apk/<버전>/` 에 APK + `release_notes_<변형>.txt` 보관 후 폴더가 열린다
- 오류 발생 시 원인 분석 후 수정 방법 제안
  - `.env` 누락(APPFIT_AES_KEY) 시 환경 변수 안내
- 사용자가 yes 외 다른 입력을 하면 배포를 취소하고 종료한다
