---
description: 릴리즈 APK 빌드 (배포 없이 로컬 빌드만)
---

## 1단계: 현재 OTA 배포 서버 버전 확인
빌드 전에 Bash 툴로 현재 배포 서버에 올라가 있는 버전을 조회해 보고한다:
```
curl -fsS --max-time 10 http://waldpay.kokonutstamp2.com/appfit_order_agent_version.json
```
- 응답은 `{"version": <int>}` 형태(= 현재 배포된 빌드번호).
- `pubspec.yaml` 의 `version`(예: 3.3.5+148, 빌드번호 148)을 함께 읽어, **배포된 버전 vs 빌드할 버전**을 비교해 알려준다.
  - 빌드번호가 배포본보다 낮거나 같으면 경고(버전 올리지 않은 채 빌드 가능성).
- 조회 실패(네트워크/서버 오류) 시: 실패 사실만 알리고 빌드는 계속 진행한다(빌드 차단 X).

## 2단계: APK 빌드
Bash 툴로 실행:
```
./build_main.sh
```

## 3단계: 결과 보고
- 빌드 성공 시 생성된 APK 경로와 파일 크기를 출력
- 빌드 실패 시 오류 메시지를 분석하고 원인과 수정 방법을 제안
- `.env` 파일이 없어서 실패한 경우 필요한 환경 변수 목록(APPFIT_AES_KEY, SENTRY_DSN)을 안내한다
