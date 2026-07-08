---
description: 릴리즈 APK 빌드 (배포 없이 로컬 빌드만)
---

## 1단계: 현재 OTA 배포 서버 버전 확인
빌드 전에 Bash 툴로 현재 배포 서버에 올라가 있는 버전을 조회해 보고한다:
```
curl -fsS --max-time 10 http://waldpay.kokonutstamp2.com/appfit_order_agent_japan_version.json
```
- 응답은 `{"version": <int>}` 형태(= 현재 배포된 빌드번호).
- `pubspec.yaml` 의 `version`(예: 3.3.5+148, 빌드번호 148)을 함께 읽어, **배포된 버전 vs 빌드할 버전**을 비교해 알려준다.
  - 빌드번호가 배포본보다 낮거나 같으면 경고(버전 올리지 않은 채 빌드 가능성).
- 조회 실패(네트워크/서버 오류) 시: 실패 사실만 알리고 빌드는 계속 진행한다(빌드 차단 X).

## 2단계: APK 빌드
단일 패키지(`co.kr.waldlust.order.receive.appfit`)로 통합됐고, flavor 없이
`--dart-define=APPFIT_VARIANT` 로만 국가를 구분한다. 기본은 `japan` 이다.
korea 빌드가 필요하면 사용자에게 확인한다. Bash 툴로 실행:
```
./build_main.sh              # japan (기본)
# ./build_main.sh korea      # 한국 채널
```
변형마다 `--dart-define=APPFIT_VARIANT` 가 자동 주입돼 OTA 채널이 분기된다. 1단계 조회 URL은 japan 신규 채널(`_japan`)이며, korea 는 `appfit_order_agent_korea_version.json` 이다.

> ⚠️ 레거시 무접미 채널(`appfit_order_agent_version.json` / `.apk`)은 동결(구 패키지 일본 매장 전용). 이 릴리즈 산출물을 그 채널로 업로드 금지.

## 3단계: 결과 보고
- 빌드 성공 시 생성된 APK 경로와 파일 크기를 출력
- 빌드 성공분은 `build_main.sh` 가 **자동 아카이브**(`archive_apk.sh`)한다 — `!Project Files/appfit_order_agent/apk/<버전>/` 에 APK + `release_notes_<변형>.txt` 보관 후 폴더가 열린다
- 빌드 실패 시 오류 메시지를 분석하고 원인과 수정 방법을 제안
- `.env` 파일이 없어서 실패한 경우 필요한 환경 변수 목록(APPFIT_AES_KEY, SENTRY_DSN)을 안내한다
