---
description: Android 릴리즈 APK 빌드 후 Lightsail 서버에 배포 (common/mammoth 브랜드 선택, 아티팩트당 채널 1세트)
---

이 명령어는 **Android** APK를 빌드해 Lightsail 서버에 업로드하는 **비가역적 배포**다.
Windows 배포는 별도 (`deploy_windows.ps1`). 아래 순서를 반드시 지킨다.

## 2-티어 아티팩트 · 아티팩트당 채널 1세트

Tier 0(공통, 패키지 `co.kr.waldlust.order.receive.appfit`)과 Tier 1(맘모스 전용,
`….appfit.mammoth`)은 같은 코드·같은 버전이고, 다른 것은 applicationId·런처
label/icon·OTA 채널뿐이다(브랜드 로직은 전부 런타임 `BrandRegistry`). 서버
(live/japanLive/staging)는 앱 로그인 화면에서 런타임 선택된다(매장 ID 프리픽스
자동 전환) — 이 배포와 무관하다.

OTA 채널은 아티팩트마다 하나다 (`lib/config/ota_config.dart`):

| 브랜드 | 채널 파일 | 용도 |
| --- | --- | --- |
| common | `appfit_order_agent_release_version.json` / `appfit_order_agent_release.apk` | 공통 아티팩트 |
| mammoth | `appfit_order_agent_mammoth_release_version.json` / `appfit_order_agent_mammoth_release.apk` | 맘모스 전용 아티팩트 |

> ⚠️ **맘모스의 실제 운영 정책은 Sunmi App Store 경로다.** 이 OTA 채널은 (1)
> 향후 Tier 1 브랜드를 위한 구조적 대비, (2) 비-Sunmi 단말·수동 체크 경로의
> 안전망이다. 다만 **빈 채널은 안전망이 아니다** — 404 는 조용히 삼켜진다.
> 맘모스를 선택했다면 이 배포 이후 실제 유통은 `/store-upload mammoth` 로
> 별도 진행해야 한다는 점을 안내한다.

> ⚠️ **한국/일본 동시 롤아웃**: 채널이 하나이므로 업로드 즉시 양국 매장이 같은
> 빌드로 업데이트된다. 지역별 시차 배포는 불가능하다.

> ⚠️ **레거시 채널 동결(FROZEN)**: 무접미 `appfit_order_agent.apk` /
> `appfit_order_agent_version.json` 은 절대 업로드하지 않는다. 구 패키지
> (`co.kr.waldlust.order.receive`)로 설치된 일본 매장 1곳이 이 채널을 폴링 중이라,
> `.appfit` 패키지 APK 를 올리면 **패키지 불일치로 설치가 실패**한다. 해당 매장이
> 신규 패키지로 **수동 재설치**되기 전까지 유지한다. `deploy_apk.sh` 는 업로드
> 직전 `aapt dump badging` 으로 APK 패키지가 그 채널과 맞는지 검증하고 불일치면
> 중단한다. 구 `_japan`/`_korea`/`_appfit` 채널은 폐기(미사용)됐다.

## 1단계 — 브랜드 선택

`AskUserQuestion` 으로 묻는다: **common**(기본)/**mammoth**.

## 2단계 — 배포 전 상태 확인

**(a) 커밋 상태** — Bash 툴로 실행해 현재 브랜치 + 최신 커밋 3개를 보여준다:
```
git log --oneline -3
```

**(b) 버전 비교** — 배포할 빌드번호와 현재 서버 버전을 조회해 명시한다. 선택한
브랜드의 채널 URL을 쓴다:
- 업데이트할 버전: `pubspec.yaml` 의 `version`(예: `3.3.5+148` → 빌드번호 `148`)을 읽는다. (Android/Windows 공통 버전 정본 = pubspec.yaml)
- 현재 서버 버전:
  ```
  curl -fsS --max-time 10 http://waldpay.kokonutstamp2.com/appfit_order_agent_release_version.json          # common
  curl -fsS --max-time 10 http://waldpay.kokonutstamp2.com/appfit_order_agent_mammoth_release_version.json  # mammoth
  ```
  (응답 `{"version": <int>}` = 현재 배포된 빌드번호)
- 조회 실패(네트워크/404 등) 시: 실패 사실만 알리고 차단하지 않는다(서버에 아직 파일이 없는 첫 배포일 수 있음 — 맘모스 채널은 아직 한 번도 채워지지 않았을 수 있다).

아래 형식으로 **현재 서버 버전 → 업데이트할 버전** 을 보여준다:

| 현재 서버 버전 | 업데이트할 버전 |
| --- | --- |
| 147 | 148 |

- 업데이트할 빌드번호가 서버 버전보다 **낮거나 같으면 경고**한다(버전 미상향 — OTA가 안 내려가거나 다운그레이드 위험).

**(c) 확인** — 위 (a)·(b)를 함께 보여주고,
"이 상태로 <브랜드> 배포하시겠습니까? (yes 입력 시 진행)" 라고 묻는다.

## 3단계 — 사용자가 yes 입력 시에만 실행

Bash 툴로 실행한다:
```
./deploy_apk.sh common
./deploy_apk.sh mammoth
```

## 실행 후

- 업로드된 APK 파일명·버전 JSON(`version=<빌드번호>`)·OTA URL을 요약
- 배포 성공분은 `deploy_apk.sh` 가 **자동 아카이브**(`archive_apk.sh`)한다 — `!Project Files/appfit_order_agent/apk/<브랜드>/<버전>/` 에 APK + `release_notes.txt` 보관 후 폴더가 열린다
- 오류 발생 시 원인 분석 후 수정 방법 제안
  - `.env` 누락(APPFIT_AES_KEY) 시 환경 변수 안내
  - `aapt` 패키지 검증 실패(채널·패키지 불일치) 시 어느 브랜드로 배포하려 했는지 재확인 안내 — **강제로 넘기지 않는다**, 되돌릴 수 없는 사고다
- 사용자가 yes 외 다른 입력을 하면 배포를 취소하고 종료한다
