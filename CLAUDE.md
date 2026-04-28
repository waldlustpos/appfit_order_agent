# CLAUDE.md

이 파일은 Claude Code (claude.ai/code)가 이 저장소에서 작업할 때 참고하는 가이드입니다. 일반적인 Flutter / Dart 코드 컨벤션은 [docs/FLUTTER_GUIDELINES.md](docs/FLUTTER_GUIDELINES.md)에 있으며, 이 문서는 **본 프로젝트만의 사실(아키텍처·디렉토리·매니저)** 에 집중합니다.

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
- 현재 버전: `pubspec.yaml`의 `version` 라인 참조 (시간에 따라 변경)

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

모든 상태는 `flutter_riverpod`를 사용하며, 장기 유지가 필요한 상태에는 `@Riverpod(keepAlive: true)`를 적용합니다. 핵심 프로바이더 (`lib/providers/`):

- `authProvider` — 로그인, WebSocket 연결 상태
- `orderProvider` — 주문 생명주기 전체 (조회, 접수, 완료, 취소)
- `kdsUnifiedProviders` — KDS 모드 토글, 탭 인덱스, 정렬 방향, 카드 크기
- `localeNotifierProvider` — 런타임 언어 전환 (ko/en/ja)
- `preferenceProvider` — `PreferenceService`에 대한 반응형 브릿지

추가 프로바이더(`brand_theme`, `kds_order_tracking`, `order_detail`, `order_history`, `membership`, `product`, `currency`, `lifecycle`, `rotation`, `store`, `app_info` 등)는 `lib/providers/`에서 직접 탐색합니다. 화면에서는 `ConsumerWidget` / `ConsumerStatefulWidget`을 사용하여 `ref.watch()` / `ref.read()`로 접근합니다.

### 서비스 레이어 (`lib/services/`)

- **ApiService** — Dio 기반 REST 클라이언트. 모든 요청은 `appfit_core`의 Dio 인터셉터를 경유 (자동 인증 헤더, `AppEnv.aesKey` 통한 AES-GCM 암호화). 엔드포인트 라우트는 `appfit_core`의 `ApiRoutes`에 정의.
- **PreferenceService** — `SharedPreferences` + `FlutterSecureStorage`를 감싸는 싱글톤. 모든 로컬 설정 관리. 최초 init 시 V2 마이그레이션 실행.
- **SecureStorageService** — `FlutterSecureStorage` 직접 래퍼. 자격증명·토큰 등 민감 데이터 저장.
- **PlatformService / PlatformBridgeService** — MethodChannel(`co.kr.waldlust.order.receive.appfit_order_agent`)을 통해 네이티브 Android 호출 (파일 로깅, 화면 회전, 백그라운드 모드, 시스템 UI 제어).
- **PrintService** — Sunmi 내장 / 외부 / 라벨 프린터로의 인쇄 명령 디스패치.
- **OutputQueueService** — 순차적 출력/인쇄 작업 큐 관리 (로그아웃 시 초기화).
- **OverlayService** — 플로팅 버블 오버레이 윈도우 제어.
- **LocalServerService** — 로컬 HTTP 수신용 경량 서버 (외부 트리거 수용).
- `services/appfit/` — `AppFitProviders`, `KokonutAppFitLogger` 등 `appfit_core` 어댑터.
- `services/migration/` — `V2MigrationService` / `V2MigrationLogger` (PreferenceService 최초 init 시 실행되는 V2 마이그레이션).
- `services/monitoring/` — `OrderAgentMonitoringContext` (Sentry 연동), `MonitoringSyncProvider` (사용자/스토어 컨텍스트 동기화).

### 부수 효과: `lib/core/orders/`

- `SoundService`, `BlinkService`, `OutputService` — 신규 주문 시 알림음·점멸·출력 처리
- `AlertManager` — 알림 표시 라이프사이클 통합
- `OrderQueueService` — 주문 처리 작업 직렬화
- `cache/` — `OrderDetailCache`, `PrintedOrderCache`, `ProcessedOrderCache`, `ActionCache` (인메모리 캐시로 중복 실행 방지)

### 외부 의존성: appfit_core

`../packages/appfit_core` 경로의 로컬 패키지 (path 의존성). 여러 AppFit 앱에서 공유하는 인프라 제공:
- `AppFitConfig` — 환경 enum (`live`, `japanLive`, `dev`, `staging`) 및 base URL 결정
- `AppFitTokenManager` — 보안 토큰 저장 및 갱신
- `AppFitDioProvider` — 인증 인터셉터가 포함된 Dio 인스턴스
- `AppFitLogger` / `SentryAppFitLogger` — 로깅 인터페이스
- `MonitoringService` / `MonitoringContext` — Sentry 래퍼 + 컨텍스트 인터페이스 (`OrderAgentMonitoringContext`가 구현하여 Sentry 초기화·오류 캡처·breadcrumb 단일 진입점 제공)
- `CryptoUtils` — AES-GCM 암호화/복호화
- `ApiRoutes` — 중앙화된 API 엔드포인트 경로

### 네이티브 Android 레이어

Java 소스 위치: `android/app/src/main/java/co/kr/waldlust/order/receive/`
- `MainActivity.java` — Flutter 엔진 호스트
- `NativeMethodHandler.java` — MethodChannel 핸들러 (인쇄, 로깅, 시스템 제어)
- `util/print/` — Sunmi 내장 프린터(`SunmiPrintHelper`), 외부 프린터, 라벨 프린터(`LabelPrinter`) ESC/POS 명령 사용
- `overlay/FloatingBubbleService.java` — 플로팅 오버레이 윈도우
- `AutoStartReceiver.java` — 부팅 시 자동 시작

## UI 구조

가로 전용 단일 모드 토글(`HomeScreen` ↔ `KdsScreen`):

1. **일반 모드** (`HomeScreen`) — 주문 현황, 주문 내역, 상품 관리, 멤버십으로 구성된 탭 뷰
2. **KDS 모드** (`KdsScreen`) — 상태별 탭(신규/진행/픽업/완료/취소)을 가진 주방 디스플레이 그리드, 자동 스크롤, 카드 기반 레이아웃

기타 화면 (`lib/screens/`):
- `LoginScreen` — 로그인 + 환경 선택
- `SettingsScreen` — 환경설정 (인쇄·알림·자동 접수 등)
- `OrderHistoryScreen`, `OrderStatusScreen` — 주문 내역/현황 단독 화면 진입
- `ProductManagementScreen` — 상품 관리
- `MembershipScreen` — 멤버십 관리
- `AppfitTestScreen` — 내부 테스트/디버그 진입점

라우트는 `MaterialApp.routes`에 3개만 명명 정의:

| 라우트 | 화면 |
| --- | --- |
| `/login` | `LoginScreen` |
| `/home` | `HomeScreen` (KDS 토글 포함) |
| `/settings` | `SettingsScreen` |

위젯은 `lib/widgets/` 하위에 기능별로 정리: `home/`, `kds/`, `order/`, `common/`, `product/`, `membership/`, `settings/`.

### 브랜드 테마

`lib/constants/brand_theme.dart`의 `BrandTheme` enum(예: `appfitDefault`, `mammothCoffee`)이 매장별 색상·로그인 배경·로고를 정의. `main()`에서 `AppStyles.applyBrand(savedBrand)`로 정적 색상 값을 부팅 시 1회 고정합니다. `BrandThemeNotifier`(`lib/providers/brand_theme_provider.dart`)의 `selectTheme()`은 `PreferenceService`에만 저장하며, 색상 교체는 **앱 재시작 후** 반영됩니다(런타임 즉시 변경 X).

## 다국어 지원 (Slang)

- 설정 파일: `slang.yaml`
- 소스 파일: `lib/i18n/strings_ko.i18n.json` (기본), `strings_en.i18n.json`, `strings_ja.i18n.json`
- 생성 파일: `lib/i18n/strings.g.dart` 및 로캘별 파일
- 사용법: `t.common.confirm`, `t.order.status.new_order` 등
- `.i18n.json` 파일 편집 후 반드시 build_runner로 재생성

## 환경 설정

빌드 타임 시크릿은 `--dart-define-from-file=.env`로 주입 (파일은 커밋하지 않음):
- `APPFIT_AES_KEY` — API 암호화용 32바이트 AES 키
- `SENTRY_DSN` — Sentry 오류 추적 엔드포인트
- `IS_ROTATED_180` — 선택적 180도 화면 회전

런타임 환경(서버 대상)은 로그인 시 선택되며 `PreferenceService`를 통해 저장됩니다. `main.dart`에서 `AppFitConfig.configure()` 호출 전에 결정됩니다.

## 주요 패턴

- **모델**: `lib/models/`에 수동 작성된 클래스 (freezed 아님), 수동 `fromJson`/`toJson`. `OrderModel`이 핵심 데이터 객체.
- **Enum**: `lib/models/enums/` — `OrderStatus`, `OrderAction` 등.
- **Order Provider 분해**: `Order` 프로바이더(`order_provider.dart`)는 매니저 클래스(`OrderSocketManager`, `OrderTimerManager`, `OrderQueueManager`, `OrderCacheManager`, `OrderSettingsManager`, `OrderStateManager`)에 위임하여 메인 프로바이더를 가볍게 유지.
- **캐싱**: `lib/core/orders/cache/` — 주문 상세, 출력 완료, 처리 완료, 액션 중복 방지를 위한 인메모리 캐시.
- **알림음/점멸/출력**: `lib/core/orders/` — `SoundService`, `BlinkService`, `OutputService`, `AlertManager`가 알림 부수 효과 처리.
- **모니터링**: `OrderAgentMonitoringContext`가 `appfit_core`의 `MonitoringContext`를 구현하여 Sentry 초기화·오류 캡처·breadcrumb를 단일 진입점에서 처리. `MonitoringSyncProvider`가 사용자/스토어 변경 시 컨텍스트를 동기화.
- **순차 비동기 큐**: `lib/utils/serial_async_queue.dart`의 `SerialAsyncQueue<T>`로 USB 프린터·TTS 등 공유 자원 경쟁을 방지. `appfit_core`의 동일 클래스(v1.0.6 deprecated)에서 자체 구현으로 이전됨. `OutputQueueService`가 대표 사용처.
- **인증/세션 정리**: `Auth.logout()`(`lib/providers/auth_provider.dart`)이 credentials/JWT/SecureStorage(projectId·apiKey)/SharedPreferences/WebSocket을 정리하는 **단일 진입점**. UI 계층(예: `HomeScreen`)은 이 메서드만 호출하고 영업 상태 변경·`OrderProvider` cleanup·네비게이션을 담당. `disconnect()` 후 dependency가 outdated되므로 모든 `ref.read()`는 disconnect 호출 전에 미리 캐시. `unauthenticate()`는 환경 변경 시 WebSocket만 끊고 로그인 화면으로 복귀.
- **라우팅**: 세 개의 명명된 라우트: `/login`, `/home`, `/settings`.

## 기획 문서

기능 기획서 및 설계 문서는 `docs/` 디렉토리에 위치합니다 (`PLAN-*.md` 파일과 `handoff*.md` 인수인계 문서).

새 작업물은 단계별 워크플로 디렉토리에 보관:
- `docs/01-plan/` — 기획
- `docs/02-design/` — 설계
- `docs/03-analysis/` — 분석
- `docs/04-report/` — 보고
- `docs/05-qa/` — QA

## Flutter / Dart 일반 가이드라인

코드 스타일·네이밍·null safety·위젯 구성·Riverpod 규칙·로깅·테마·레이아웃·테스트·접근성·문서화 규약은 [docs/FLUTTER_GUIDELINES.md](docs/FLUTTER_GUIDELINES.md)에서 관리합니다.
