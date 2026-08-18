---
description: 릴리즈 APK 빌드 (배포 없이 로컬 빌드만) — common/mammoth/all 브랜드 선택
---

## 1단계: 브랜드 선택

`AskUserQuestion` 으로 브랜드를 묻는다: **common**(기본, Tier 0 공통)/**mammoth**
(Tier 1 전용, 패키지 `….appfit.mammoth`)/**all**(둘 다 같은 커밋으로 연속 빌드).

## 2단계: 현재 OTA 배포 서버 버전 확인

빌드 전에 Bash 툴로 현재 배포 서버에 올라가 있는 버전을 조회해 보고한다.
채널은 브랜드에 종속되므로 선택에 맞는 URL을 쓴다:
```
curl -fsS --max-time 10 http://waldpay.kokonutstamp2.com/appfit_order_agent_release_version.json          # common
curl -fsS --max-time 10 http://waldpay.kokonutstamp2.com/appfit_order_agent_mammoth_release_version.json  # mammoth
```
(`all` 이면 둘 다 조회)
- 응답은 `{"version": <int>}` 형태(= 현재 배포된 빌드번호).
- `pubspec.yaml` 의 `version`(예: 3.3.5+148, 빌드번호 148)을 함께 읽어, **배포된 버전 vs 빌드할 버전**을 비교해 알려준다. 두 브랜드가 버전 정본을 공유하므로 빌드번호는 동일해야 정상이다.
  - 빌드번호가 배포본보다 낮거나 같으면 경고(버전 올리지 않은 채 빌드 가능성).
- 조회 실패(네트워크/서버 오류) 시: 실패 사실만 알리고 빌드는 계속 진행한다(빌드 차단 X).

## 3단계: APK 빌드

2-티어 아티팩트 모델 — 같은 코드·같은 버전이고 다른 것은 applicationId·런처
label/icon·OTA 채널뿐이다(브랜드 로직은 전부 런타임 `BrandRegistry`). 서버는
로그인 화면에서 런타임 선택되므로 국가는 이 축과 무관하다. Bash 툴로 실행:
```
./build_main.sh common
./build_main.sh mammoth
./build_main.sh all       # 같은 커밋으로 common → mammoth 연속 빌드
```
`build_main.sh` 는 `aapt dump badging` 으로 package/versionCode/label 을
출력한다. **`all` 을 선택했다면 출력에서 두 APK 의 versionCode 가 동일한지
반드시 확인**하고 보고한다(정본은 `pubspec.yaml` 하나이므로 다르면 이상 징후).

OTA 채널은 아티팩트마다 하나다(`lib/config/ota_config.dart`): 공통은
`_release`, 맘모스는 `_mammoth_release`.

> ⚠️ 레거시 무접미 채널(`appfit_order_agent_version.json` / `.apk`)은 동결(구 패키지 일본 매장 전용). 이 릴리즈 산출물을 그 채널로 업로드 금지.

## 4단계: 결과 보고

- 빌드 성공 시 생성된 APK 경로·파일 크기·`aapt` 출력(package/versionCode/label)을 브랜드별로 출력
- 빌드 성공분은 `build_main.sh` 가 **자동 아카이브**(`archive_apk.sh`)한다 — `!Project Files/appfit_order_agent/apk/<브랜드>/<버전>/` 에 APK + `release_notes.txt` 보관 후 폴더가 열린다
- 빌드 실패 시 오류 메시지를 분석하고 원인과 수정 방법을 제안
- `.env` 파일이 없어서 실패한 경우 필요한 환경 변수 목록(APPFIT_AES_KEY, SENTRY_DSN)을 안내한다
- `aapt` 를 찾을 수 없어 패키지 검증을 건너뛴 경우 `ANDROID_HOME` 설정을 안내한다
