# CLAUDE.md

이 파일은 Claude Code (claude.ai/code)가 이 저장소에서 작업할 때 참고하는 가이드입니다.

## 언어

모든 아티팩트(task.md, implementation_plan.md, walkthrough.md)와 설명은 항상 **한국어**로 작성합니다.

## AI 상호작용 프로토콜

1. 코드를 작성하기 전에 구현 계획을 먼저 제시하고 사용자의 확인을 받은 후 코드를 생성합니다.
2. 코드 수정 시, 변경된 부분만 보내거나 생략하지 않고, 기존 코드와 동일하더라도 파일의 처음부터 끝까지 완전한 코드를 제공합니다.
3. 다음 정보가 누락되어 코드의 정확성이 저해될 경우, 코드를 생성하지 않고 즉시 정보를 요청합니다:
   - 핵심 컴포넌트 (사용자 정의 클래스, 데이터 모델, Riverpod Provider의 전체 정의)
   - 플랫폼 설정 (build.gradle의 targetSdk, compileSdk 등 필수 사양)
   - 외부 라이브러리 (pubspec.yaml의 라이브러리 명과 정확한 버전)
4. 부정확한 컨텍스트로 코드를 추측하여 완성하지 않습니다.

## 프로젝트 개요

**AppFit 주문 에이전트** — 음식점 주문 접수/관리를 위한 Flutter 모바일 앱. Android 전용, 가로(Landscape) 전용, KDS(주방 디스플레이) 터미널 및 POS 기기(Sunmi 하드웨어) 대상.

- 패키지: `co.kr.waldlust.order.receive`
- Dart SDK: ^3.5.0, Flutter: >=3.19.0
- Android: minSdk 24, targetSdk 35
- 현재 버전: `pubspec.yaml`의 version 라인 참조

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

## 아키텍처

### 데이터 흐름 개요

```
WebSocket (실시간) ─────┐
                        ├──► OrderProvider ──► OrderState ──► UI (HomeScreen / KdsScreen)
REST API (폴링)  ───────┘        │
                                 ├── OrderSocketManager (WebSocket 이벤트)
                                 ├── OrderTimerManager (폴링, 자정 새로고침)
                                 ├── OrderQueueManager (배치 처리)
                                 ├── OrderCacheManager (상세/출력 캐시)
                                 ├── OrderSettingsManager (자동 접수, 키오스크 노출)
                                 └── OrderStateManager (상태 변경 헬퍼)
```

주문은 **WebSocket**(기본, 실시간)과 **REST API 폴링**(폴백)으로 수신됩니다. `OrderProvider`는 `lib/providers/order_*.dart` 하위의 매니저 클래스로 분해되어 있습니다. 부수 효과 서비스(알림음, 점멸, 출력)는 `lib/core/orders/`에 위치합니다.

### 상태 관리: Riverpod

모든 상태는 `flutter_riverpod`를 사용하며, 장기 유지가 필요한 상태에는 `@Riverpod(keepAlive: true)`를 적용합니다. 프로바이더는 `lib/providers/`에 위치:

- `authProvider` — 로그인, WebSocket 연결 상태
- `orderProvider` — 주문 생명주기 전체 (조회, 접수, 완료, 취소)
- `kdsUnifiedProviders` — KDS 모드 토글, 탭 인덱스, 정렬 방향, 카드 크기
- `localeNotifierProvider` — 런타임 언어 전환 (ko/en/ja)
- `preferenceProvider` — `PreferenceService`에 대한 반응형 브릿지

화면에서는 `ConsumerWidget` / `ConsumerStatefulWidget`을 사용하여 `ref.watch()` / `ref.read()`로 프로바이더에 접근합니다.

### 서비스 레이어 (`lib/services/`)

- **ApiService** — Dio 기반 REST 클라이언트. 모든 요청은 `appfit_core`의 Dio 인터셉터를 경유 (자동 인증 헤더, `AppEnv.aesKey` 통한 AES-GCM 암호화). 엔드포인트 라우트는 `appfit_core`의 `ApiRoutes`에 정의.
- **PreferenceService** — `SharedPreferences` + `FlutterSecureStorage`를 감싸는 싱글톤. 모든 로컬 설정 관리. 최초 init 시 V2 마이그레이션 실행 (`migration/v2_migration_service.dart`).
- **PlatformService** — MethodChannel(`co.kr.waldlust.order.receive.appfit_order_agent`)을 통해 네이티브 Android 호출. 파일 로깅, 화면 회전, 백그라운드 모드, 시스템 UI 처리.
- **Monitoring** (`monitoring/`) — Sentry 연동. `OrderAgentMonitoringContext`가 `appfit_core`의 `MonitoringContext` 인터페이스 구현.
- **OutputQueueService** — 순차적 출력/인쇄 큐 관리.

### 외부 의존성: appfit_core

`../packages/appfit_core` 경로의 로컬 패키지 (path 의존성). 여러 AppFit 앱에서 공유하는 인프라 제공:
- `AppFitConfig` — 환경 enum (`live`, `japanLive`, `dev`, `staging`) 및 base URL 결정
- `AppFitTokenManager` — 보안 토큰 저장 및 갱신
- `AppFitDioProvider` — 인증 인터셉터가 포함된 Dio 인스턴스
- `AppFitLogger` / `SentryAppFitLogger` — 로깅 인터페이스
- `MonitoringService` — Sentry 래퍼
- `CryptoUtils` — AES-GCM 암호화/복호화
- `ApiRoutes` — 중앙화된 API 엔드포인트 경로

### 네이티브 Android 레이어

Java 소스 위치: `android/app/src/main/java/co/kr/waldlust/order/receive/`
- `MainActivity.java` — Flutter 엔진 호스트
- `NativeMethodHandler.java` — MethodChannel 핸들러 (인쇄, 로깅, 시스템 제어)
- `util/print/` — Sunmi 내장 프린터(`SunmiPrintHelper`), 외부 프린터, 라벨 프린터(`LabelPrinter`) ESC/POS 명령 사용
- `overlay/FloatingBubbleService.java` — 플로팅 오버레이 윈도우
- `AutoStartReceiver.java` — 부팅 시 자동 시작

### UI 구조

가로 전용의 두 가지 메인 화면 모드:
1. **일반 모드** (`HomeScreen`) — 주문 현황, 주문 내역, 상품 관리, 멤버십으로 구성된 탭 뷰
2. **KDS 모드** (`KdsScreen`) — 상태별 탭(신규/진행/픽업/완료/취소)을 가진 주방 디스플레이 그리드, 자동 스크롤, 카드 기반 레이아웃

위젯은 `lib/widgets/` 하위에 기능별로 정리 (home, kds, order, common, product, membership).

### 다국어 지원 (Slang)

- 설정 파일: `slang.yaml`
- 소스 파일: `lib/i18n/strings_ko.i18n.json` (기본), `strings_en.i18n.json`, `strings_ja.i18n.json`
- 생성 파일: `lib/i18n/strings.g.dart` 및 로캘별 파일
- 사용법: `t.common.confirm`, `t.order.status.new_order` 등
- `.i18n.json` 파일 편집 후 반드시 build_runner로 재생성

### 환경 설정

빌드 타임 시크릿은 `--dart-define-from-file=.env`로 주입 (파일은 커밋하지 않음):
- `APPFIT_AES_KEY` — API 암호화용 32바이트 AES 키
- `SENTRY_DSN` — Sentry 오류 추적 엔드포인트
- `IS_ROTATED_180` — 선택적 180도 화면 회전

런타임 환경(서버 대상)은 로그인 시 선택되며 `PreferenceService`를 통해 저장됩니다. `main.dart`에서 `AppFitConfig.configure()` 호출 전에 결정됩니다.

### 주요 패턴

- **모델**: `lib/models/`에 수동 작성된 클래스 (freezed 아님), 수동 `fromJson`/`toJson`. `OrderModel`이 핵심 데이터 객체.
- **Enum**: `lib/models/enums/` — `OrderStatus`, `OrderAction` 등.
- **Order Provider 분해**: `Order` 프로바이더(`order_provider.dart`)는 매니저 클래스(`OrderSocketManager`, `OrderTimerManager`, `OrderQueueManager`, `OrderCacheManager`, `OrderSettingsManager`, `OrderStateManager`)에 위임하여 메인 프로바이더를 가볍게 유지.
- **캐싱**: `lib/core/orders/cache/` — 주문 상세, 출력 완료, 처리 완료, 액션 중복 방지를 위한 인메모리 캐시.
- **알림음/점멸/출력**: `lib/core/orders/` — `SoundService`, `BlinkService`, `OutputService`가 알림 부수 효과 처리.
- **라우팅**: 세 개의 명명된 라우트: `/login`, `/home`, `/settings`.

### 기획 문서

기능 기획서 및 설계 문서는 `docs/` 디렉토리에 위치 (PLAN-*.md 파일). 진행 중인 작업의 인수인계 문서도 여기에 있습니다.

---

## Flutter 개발 가이드라인

### 코드 스타일 및 네이밍

- **네이밍**: 클래스는 `PascalCase`, 변수/함수/enum 값은 `camelCase`, 파일은 `snake_case`
- **줄 길이**: 80자 이하 권장
- **간결성**: 선언적이고 함수형 패턴을 선호하며, 코드는 명확하면서도 최대한 짧게 작성
- **SOLID 원칙**: 단일 책임, 개방-폐쇄, 리스코프 치환, 인터페이스 분리, 의존성 역전 원칙 적용
- **합성 우선**: 상속보다 합성(composition)을 선호하여 복잡한 위젯과 로직 구성
- **약어 지양**: 축약어를 피하고, 의미 있고 일관성 있는 이름 사용
- **화살표 함수**: 단순한 한 줄 함수에는 화살표(`=>`) 구문 사용

### Dart 모범 사례

#### Null Safety
- Dart의 null safety를 적극 활용하며 sound null-safe 코드 작성
- `!` 연산자는 값이 non-null임이 보장될 때만 사용, 남용 금지
- `int.tryParse()`, `double.tryParse()` 등 안전한 타입 변환 사용

#### 비동기 처리
- 비동기 작업에는 `Future`와 `async`/`await`를 사용하고, 반드시 오류 처리 포함
- 비동기 이벤트 시퀀스에는 `Stream` 사용
- UI 스레드 차단을 피하기 위해 무거운 계산은 `compute()`로 별도 Isolate에서 실행

#### 패턴 매칭 및 Switch
- 코드를 간결하게 만드는 곳에서 패턴 매칭 활용
- 가능한 경우 exhaustive `switch` 표현식 사용 (`break` 불필요)
- 여러 값을 반환해야 할 때 Record 타입 사용 고려

#### 예외 처리
- `try-catch` 블록으로 예외를 처리하고, 상황에 적합한 예외 타입 사용
- 프로젝트 고유 상황에는 커스텀 예외 사용 (`lib/exceptions/api_exceptions.dart` 참조)
- 코드가 조용히 실패하지 않도록 에러를 적절히 처리

### Flutter 모범 사례

#### 위젯 구성
- 위젯(특히 `StatelessWidget`)은 불변으로 유지
- 큰 `build()` 메서드는 작은 private Widget 클래스로 분리 (헬퍼 메서드가 아닌 별도 Widget 클래스 사용)
- 가능한 모든 곳에서 `const` 생성자 사용하여 불필요한 리빌드 감소
- `build()` 메서드 내에서 네트워크 호출, 복잡한 계산 등 비용이 큰 작업 수행 금지

#### 리스트 성능
- 긴 리스트에는 `ListView.builder` 또는 `SliverList`로 지연 로딩 구현
- KDS 카드 그리드 등 대량 데이터 표시 시 특히 중요

### 프로젝트별 패턴

#### Riverpod 사용 규칙
- 새 프로바이더는 `@Riverpod` 어노테이션 + `riverpod_generator` 사용
- 앱 생명주기 동안 유지해야 하는 상태에는 `@Riverpod(keepAlive: true)` 적용
- 간단한 상태에는 `StateProvider` 사용 가능 (예: `homeTabIndexProvider`)
- 비동기 데이터 로딩에는 `AsyncValue` 타입으로 로딩/에러 상태를 명확히 처리
- UI에서의 구분: 상태 구독은 `ref.watch()`, 일회성 읽기는 `ref.read()` 사용
- 프로바이더 생성 후 반드시 `dart run build_runner build --delete-conflicting-outputs` 실행

#### 수동 JSON 직렬화
- 모델 클래스는 `lib/models/`에 수동 작성 (freezed/json_serializable 코드 생성 미사용)
- 각 모델에 `factory fromJson(Map<String, dynamic> json)` 팩토리 생성자 구현
- `toJson()` 메서드와 `copyWith()` 메서드 수동 구현
- JSON 파싱 실패에 대비한 `try-catch`, `tryParse()` 등 안전한 파싱 적용
- Enum은 `fromCode()` 팩토리로 서버 코드와 매핑 (예: `OrderStatus.fromCode('2003')`)

#### Navigator 라우팅
- `MaterialApp`의 `routes` 맵에 고정 라우트 정의 (`/login`, `/home`, `/settings`)
- 화면 전환: `Navigator.pushReplacementNamed()`, `Navigator.pushNamedAndRemoveUntil()` 사용
- `PopScope`로 뒤로가기 버튼 동작 제어
- go_router는 사용하지 않음

#### 로깅
- 전역 `logger` 인스턴스 사용 (`lib/utils/logger.dart`)
- 레벨별 사용: `logger.d()` (디버그), `logger.i()` (정보), `logger.w()` (경고), `logger.e()` (에러)
- 모듈별 태그 활용: `logToFile(tag: LogTag.API, message: '...')`
- 파일 로깅은 Whitelist 태그 기반 필터링 적용 (UI_ACTION, SYSTEM, PLATFORM, WEBSOCKET, LIFECYCLE 등)
- `print()` 대신 항상 `logger` 사용

#### 테마 및 스타일
- `lib/constants/app_styles.dart`의 `AppStyles` 클래스에 색상, 폰트 크기, 버튼 스타일 등 중앙화
- 새 스타일 추가 시 `AppStyles`에 정적 상수/팩토리 메서드로 추가
- Material 3 활성화 (`useMaterial3: true`)
- 커스텀 폰트: `SpoqaHanSansNeo` (기본), `Pretendard` 사용
- 하드코딩된 색상/크기 값은 `AppStyles` 상수로 추출하여 일관성 유지

### 레이아웃 모범 사례

#### Row/Column 구성
- **`Expanded`**: 남은 공간을 채워야 할 때 사용
- **`Flexible`**: 축소는 가능하되 확장은 불필요할 때 사용 (같은 Row/Column에서 `Expanded`와 혼용 금지)
- **`Wrap`**: Row/Column에서 오버플로가 발생할 때 다음 줄로 넘기기 위해 사용

#### 스크롤 및 리스트
- **`SingleChildScrollView`**: 고정 크기의 콘텐츠가 뷰포트보다 클 때 사용
- **`ListView.builder`**: 긴 리스트에 지연 로딩 적용
- **`LayoutBuilder`**: 반응형 레이아웃을 위해 가용 공간 기반 의사결정 시 사용

#### 오버플로 방지
- **`FittedBox`**: 자식 위젯을 부모 크기에 맞게 스케일링
- 텍스트 오버플로 시 `TextOverflow.ellipsis`, `maxLines` 활용

### 테스트 가이드라인

- **단위 테스트**: `package:test`로 도메인 로직, 서비스 레이어 테스트
- **위젯 테스트**: `package:flutter_test`로 UI 컴포넌트 테스트
- **통합 테스트**: `package:integration_test`로 전체 사용자 흐름 검증
- **패턴**: AAA(Arrange-Act-Assert) 또는 Given-When-Then 패턴 준수
- **Mock 선호도**: Mock보다 Fake/Stub 우선 사용, 필요 시 `mocktail` 활용
- **테스트 실행**: `flutter test` 또는 `flutter test test/<파일_경로>`

### 접근성 (A11Y)

- **색상 대비**: 텍스트와 배경 간 최소 **4.5:1** 대비율 유지 (WCAG 2.1 기준)
- **동적 텍스트 크기**: 시스템 글꼴 크기 변경 시 UI가 정상 작동하는지 확인
- **시맨틱 레이블**: `Semantics` 위젯으로 UI 요소에 명확한 설명 제공
- **스크린 리더**: TalkBack (Android) 테스트 권장

### 문서화 규칙

- 모든 공개 API에 `///` dartdoc 주석 작성
- 첫 문장은 마침표로 끝나는 간결한 요약
- 복잡하거나 명확하지 않은 코드에만 주석 작성 — 코드 자체로 설명되는 경우 주석 불필요
- 뒤따르는(trailing) 주석 금지
- 코드가 **무엇을** 하는지가 아니라 **왜** 그렇게 하는지 설명
