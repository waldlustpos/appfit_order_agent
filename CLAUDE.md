# CLAUDE.md

## 프로젝트 개요

**AppFit 주문 에이전트** — 카페·음식 업종에서 키오스크/모바일 주문을 접수·관리하는 Flutter 앱. Android 가로 전용, 메인 모드(주문 접수)와 KDS 모드(주방 디스플레이) 토글. 주력 디바이스: Sunmi D3 MINI, D2s_KDS.

- 패키지: `co.kr.waldlust.order.receive`
- Dart SDK: ^3.5.0, Flutter: >=3.19.0
- Android: minSdk 24, targetSdk 35
- 버전: `pubspec.yaml`의 `version` 라인 참조

## 핵심 명령어

- 의존성/코드 생성: `flutter pub get` → `dart run build_runner build --delete-conflicting-outputs`
- 분석: `flutter analyze`
- 릴리즈 빌드/배포: `./build_main.sh`, `./deploy_apk.sh`
- 자세한 명령어·환경설정·다국어 워크플로: [docs/BUILD.md](docs/BUILD.md)

## 절대 규칙

- **생성 파일 직접 수정 금지**: `.g.dart` / `.freezed.dart`는 항상 build_runner 재실행으로 갱신.
- **모델은 수동 작성**: `lib/models/`는 freezed/json_serializable을 **사용하지 않음**. `fromJson`/`toJson`/`copyWith` 직접 구현. Claude가 freezed로 새 모델을 만들지 말 것.
- **API 요청 우회 금지**: 모든 REST 호출은 `appfit_core`의 Dio 인터셉터 경유 (자동 인증 헤더 + AES-GCM 암호화). 직접 `http`/`Dio`로 요청하지 말 것.
- **인증/세션 정리는 단일 진입점**: `Auth.logout()`(`lib/providers/auth_provider.dart`)만 사용. `disconnect()` 호출 후에는 dependency가 outdated되므로 **모든 `ref.read()`는 disconnect 호출 전에 미리 캐시**해야 함. UI 계층은 `Auth.logout()` 호출 + 영업 상태 변경 + `OrderProvider` cleanup + 네비게이션만 담당.

## 상세 문서

- 아키텍처(데이터 흐름·Riverpod·서비스·UI·네이티브·브랜드 테마·주요 패턴): [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- 빌드/배포/환경설정/다국어(Slang): [docs/BUILD.md](docs/BUILD.md)
- Flutter/Dart 코드 스타일·Riverpod·라우팅·로깅·테마·테스트·접근성 규약: [docs/FLUTTER_GUIDELINES.md](docs/FLUTTER_GUIDELINES.md)
