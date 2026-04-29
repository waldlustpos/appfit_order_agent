# 빌드 / 배포 / 환경 / 다국어

빌드 명령어, 환경 변수, 다국어(Slang) 워크플로 등 작업 시점에만 필요한 참조 정보입니다.

## 빌드 및 실행 명령어

```bash
# 의존성 설치
flutter pub get

# 코드 생성 (freezed, json_serializable, riverpod_generator, slang i18n)
dart run build_runner build --delete-conflicting-outputs

# 정적 분석
flutter analyze

# 릴리즈 APK 빌드 (.env 파일에 APPFIT_AES_KEY, SENTRY_DSN 필요)
flutter build apk --release --dart-define-from-file=.env

# 전체 클린 + 빌드
./build_main.sh

# 빌드 + Lightsail 서버 배포 (SCP 업로드 + 버전 JSON 업데이트)
./deploy_apk.sh

# 전체 테스트 실행
flutter test

# 단일 테스트 파일 실행
flutter test test/<파일_경로>
```

**중요**: 모델(`freezed`/`json_serializable`), 프로바이더(`riverpod_generator`), i18n JSON 파일을 변경한 후에는 반드시 `dart run build_runner build --delete-conflicting-outputs`를 재실행해야 합니다. `.g.dart` 또는 `.freezed.dart`로 끝나는 생성된 파일은 절대 직접 수정하지 않습니다.

## 환경 설정

빌드 타임 시크릿은 `--dart-define-from-file=.env`로 주입 (파일은 커밋하지 않음):

- `APPFIT_AES_KEY` — API 암호화용 32바이트 AES 키
- `SENTRY_DSN` — Sentry 오류 추적 엔드포인트
- `IS_ROTATED_180` — 선택적 180도 화면 회전

런타임 환경(서버 대상)은 로그인 시 선택되며 `PreferenceService`를 통해 저장됩니다. `main.dart`에서 `AppFitConfig.configure()` 호출 전에 결정됩니다.

## 다국어 지원 (Slang)

- 설정 파일: `slang.yaml`
- 소스 파일: `lib/i18n/strings_ko.i18n.json` (기본), `strings_en.i18n.json`, `strings_ja.i18n.json`
- 생성 파일: `lib/i18n/strings.g.dart` 및 로캘별 파일
- 사용법: `t.common.confirm`, `t.order.status.new_order` 등
- `.i18n.json` 파일 편집 후 반드시 build_runner로 재생성
