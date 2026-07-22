# AppFit 주문 에이전트 As-Is 아키텍처

> 버전 0.1 (초판) · 2026-07-03 기준

kokonut_order_agent_v2 의 후속(AppFit 플랫폼 전환) 앱의 현재(As-Is) 아키텍처 스냅샷이다. 세부 흐름·규약의 정본은 [docs/ARCHITECTURE.md](ARCHITECTURE.md) 등 각 문서이며, 본 문서는 전체 조감용 요약이다.

## 1. 개요

| 항목 | 내용 |
| --- | --- |
| 제품명 | AppFit 주문 에이전트 (키오스크·모바일 주문 접수/관리) |
| 저장소 | `appfit_order_agent` (로컬: `/Users/kimsungchun/Documents/GitHub/appfit_order_agent`) |
| 플랫폼 | Android 가로 전용 + Windows 데스크톱 (x64) |
| 주력 기기 | Sunmi D3 MINI, D2s_KDS, Windows POS |
| 앱 모드 | 메인 모드(주문 접수) ↔ KDS 모드(주방 디스플레이) 토글, Windows는 KDS 버블 모드(80x80 플로팅 윈도우) 추가 |
| 기술 스택 | Dart SDK ^3.5.0 · Flutter >=3.19.0 |
| 상태관리 | flutter_riverpod ^2.5.1 + riverpod_annotation ^2.6.1 (riverpod_generator codegen) |
| 실시간 채널 | AppFit Notifier WebSocket (기본) + REST 폴링 폴백 — 적응형(소켓 연결 60s / 끊김 15s, 시작 30s 지연) |
| REST | `appfit_core` Dio 인터셉터 경유 (자동 인증 헤더 + AES-GCM 암호화) |
| i18n | slang standalone CLI — ko(base)/en/ja, 런타임 전환 |
| 모니터링 | Sentry (`MonitoringService`, appfit_core) — Slack 로그 업로드는 미병합 `feature/remote-log-collection` 브랜치 전용, main에는 로컬 로그 파일 기록만(`WindowsLogFileWriter`) |
| 배포 채널 | Lightsail OTA 서버 (`waldpay.kokonutstamp2.com`) — Android APK / Windows ZIP + 버전 JSON |
| 빌드 모델 | **단일 빌드** — flavor·변형 인자 없음. 서버(live/japanLive)는 로그인 화면 런타임 선택 + 매장 ID 프리픽스 자동 전환 (§6.1) |
| 버전 정본 | **단일화**: Android·Windows 모두 `pubspec.yaml`의 `version`(현재 3.0.0+161). `version_windows.txt`는 폐지 |
| 패키지 ID | `co.kr.waldlust.order.receive.appfit` (단일) |

## 2. 앱 아키텍처

### 2.1 디렉터리 구조 (`lib/`)

```
lib/
├── main.dart                # 초기화 시퀀스 (뮤텍스→환경→Sentry→OTA→Firebase→Prefs→테마→runApp)
├── common/                  # 공용 타입
├── config/                  # AppEnv(변형)·OtaConfig·UpdateConfig
├── constants/               # BrandTheme 등 상수
├── core/orders/             # 부수효과: SoundService·BlinkService·OutputService·AlertManager·cache/
├── dev/                     # 개발 전용 도구 (mock_order_generator 등 — 프로덕션과 격리)
├── exceptions/              # 전용 예외 (OrderDetailFetchFailedException 등)
├── i18n/                    # strings_{ko,en,ja}.i18n.json + strings.g.dart (slang 생성)
├── models/                  # 수동 작성 모델 (freezed 금지) + enums/
├── providers/               # Riverpod 프로바이더 (barrel: providers.dart)
│   ├── order/               # OrderProvider 코디네이터 + 6 매니저 + computed providers
│   └── kds/                 # KDS 모드·탭·정렬·추적
├── screens/                 # LoginScreen·HomeScreen·KdsScreen·SettingsScreen 등
├── services/                # ApiService·PreferenceService·OutputQueueService·프린터·OTA 등
│   ├── appfit/              # appfit_core 어댑터
│   ├── label_printer/       # 라벨: Orchestrator·Service(FFI)·LabelPrintData·QR 전략
│   ├── migration/           # V2MigrationService
│   ├── monitoring/          # Sentry 컨텍스트·동기화
│   └── waldpos/             # WaldPOS VAN Bridge (Windows 멤버십 바코드, local TCP :8888)
├── utils/                   # BrandRegistry·BrandAssets·SerialAsyncQueue 등
└── widgets/                 # home/ kds/ order/ common/ product/ membership/ settings/ update/
```

### 2.2 레이어별 역할

| 레이어 | 위치 | 역할 |
| --- | --- | --- |
| App Shell | `main.dart` + Routes | 초기화 시퀀스, 명명 라우트 3개(`/login` `/home` `/settings`), 부팅 시 브랜드 테마 1회 적용 |
| Order Core | `providers/order/` | `OrderProvider` 코디네이터 + 6 매니저(Socket/Timer/Queue/Cache/Settings/State) — 주문 생명주기 전체 |
| Output & Print | `services/` + `core/orders/` | `OutputQueueService` 이중 직렬 큐(영수증/라벨), ESC/POS 빌더, `PrinterJobQueue` backoff, `OutputService.printOrderLabels`(라벨 오케스트레이션) |
| KDS | `providers/kds/` + `widgets/kds/` | 5 상태 탭·정렬·카드 애니메이션·버블 모드(모드 공통) — Order Core와 동일 `OrderState` 공유(중복 없음). 카드 치수는 고정 상수(`KdsCardMetrics`) |
| Brand & i18n | `utils/brand_registry.dart` 등 | 3계층 브랜드 처리(§3) + slang 다국어 |
| Auth & Session | `providers/auth_provider.dart` | 로그인·`Auth.logout()` 단일 진입점·세션 복원 |
| Platform & Infra | `android/` `windows/` + `services/` | MethodChannel·C++ 뮤텍스·FFI·OTA·모니터링·LocalServerService(:8080 외부 트리거) |
| 외부 패키지 | `appfit_core` — **git 의존** `github.com/ratm10/appifit_agent_core.git` (`ref: v1.0.15`, path: `appfit_core`) · 로컬 `../packages/appfit_core`는 미러 사본(빌드는 git ref 기준) | AppFitConfig(환경 enum)·TokenManager·DioProvider·CryptoUtils·ApiRoutes·MonitoringService |

### 2.3 상태관리 (Riverpod)

- codegen 사용: `@Riverpod(keepAlive: true)` + `riverpod_generator` (`.g.dart`는 build_runner 로만 갱신).
- 핵심: `authProvider`(로그인·WS 연결), `orderProvider`(주문 생명주기), `kdsUnifiedProviders`(KDS 토글·탭·정렬), `localeNotifierProvider`(언어), `preferenceProvider`(PreferenceService 반응형 브릿지), `currentBrandProvider`(BrandMeta 해석).
- `OrderProvider` 계약: 매니저는 `build()`에서 `late` 필드로 정확히 1회 생성, 부수효과 서비스는 `!_isLoggedOut` 가드, state 변이는 provider 본체에서만.
- 리빌드 비용 규약: 전체 watch 금지 → `select` 또는 컴퓨티드 프로바이더(`orderStatusOrdersProvider`, `kdsTabOrdersProvider`, `orderByIdProvider` family) 경유. 카드 위젯 최외곽 `RepaintBoundary`.

### 2.4 네이밍·절대 규칙 요약

| 규칙 | 내용 |
| --- | --- |
| 생성 파일 | `.g.dart`/`.freezed.dart` 직접 수정 금지 — build_runner 재실행 |
| 모델 | `lib/models/`는 freezed/json_serializable **미사용** — `fromJson`/`toJson`/`copyWith`/`==` 수동 구현 |
| API | 직접 `http`/`Dio` 금지 — `appfit_core` Dio 인터셉터 경유 |
| import | 상대 import 금지 — `package:appfit_order_agent/...`만 (`always_use_package_imports` 린트) |
| 인증 정리 | `Auth.logout()` 단일 진입점. `disconnect()` 전에 모든 `ref.read()` 캐시 |
| 버전 | Android·Windows 모두 `pubspec.yaml`만 수정. PowerShell 스크립트는 UTF-8 BOM |
| 네이티브 소스 | `.cpp`/`.h`/`.cmake`/`.gradle`/`.ps1`/`.bat`은 ASCII만 (MSVC CP949 사고 방지) |
| i18n | slang은 standalone — build_runner로 `strings.g.dart` 갱신 안 됨, `flutter pub run slang` 필수 |

## 3. 브랜드·테넌트 처리 — BrandRegistry 3계층

브랜드는 **매장 ID prefix**로 식별한다. 정본은 `lib/utils/brand_registry.dart` (SSOT).

### 3.1 3계층 구조

| 계층 | 구성요소 | 역할 |
| --- | --- | --- |
| Layer 1 — SSOT 레지스트리 | `BrandRegistry` → `BrandMeta` | prefix → 자산 폴더·영수증 로고·테마·통화·서버환경·features 해석. `resolveOrNull()`(미매칭=null, capability·통화·환경용) vs `resolve()`(미매칭=fallback tpcp, 자산 경로 전용) 2단 해석 |
| Layer 2 — Capability 게이팅 | `enum BrandFeature` | `labelCategoryFilter`·`soundGraphSend`·`japanEnvironment`·`sunmiAppStoreUpdate` — `brand.has(feature)`로 UI show/hide·로직 on/off |
| Layer 3 — 동작 seam | Strategy/Hook 인터페이스 | 동작이 갈리는 소수 지점만 분리: `LabelFilterStrategy`(TPCP 라벨 메뉴 필터), `SoundGraphHook`(MHST 자동접수 후 전송), `qrPayloadStrategyProvider`(라벨 QR 페이로드) — 비대상 브랜드는 NoOp |

### 3.2 등록 브랜드 (prefix 표)

| BrandKey | prefix | 자산 폴더 | 테마 | 통화 | 서버 환경 | features |
| --- | --- | --- | --- | --- | --- | --- |
| `tpcp` (fallback) | `TPCP` | tokyoplatz | appfitDefault | JPY | japanLive | labelCategoryFilter, japanEnvironment |
| `mhst` | `MHST` | mammoth | mammothCoffee | KRW | live | soundGraphSend, sunmiAppStoreUpdate |
| `mata` | `MATA` | mahataste | mata | KRW | live | (없음) |
| `paik` | `PAIK` | paik | paik | JPY | japanLive | japanEnvironment |

- 테마는 `main()`의 `AppStyles.applyBrand()`로 부팅 시 1회 고정 — 색상 변경은 앱 재시작 후 반영.
- `currentBrandProvider`는 무상태로 매번 prefs를 읽어 `BrandMeta?` 반환 → 로그아웃/서버전환 시 outdated 문제 없음.
- 새 브랜드 추가 = `BrandKey` enum + `BrandRegistry._all` 항목 + 자산 + `BrandTheme`(선택) + pubspec + `qrPayloadStrategyProvider` switch. 절차: [BRAND_ASSETS.md](BRAND_ASSETS.md) / `/add-brand` 스킬.

## 4. 핵심 도메인 흐름

### 4.1 주문 수신 · 자동접수

| 단계 | 트리거 | 경로 | 가드 | 결과 |
| --- | --- | --- | --- | --- |
| 수신 | WSS `ORDER_*` 이벤트 / 적응형 폴링(연결 60s·끊김 15s) / 수동 새로고침 | `OrderSocketManager` / `OrderTimerManager` / `refreshOrders` — 3경로 각자 dedup | `ProcessedOrderCache`, `RecentRemovals` | 신규 주문 후보 확보 |
| 버퍼·정렬 | 신규 주문 도착 | `OrderQueueManager` 1000ms 버퍼 → `shopOrderNo` 정렬 → 250/500ms throttle 방출 | 정렬 정본은 `orderedAt`(상태), 출력 순서는 `compareByShopOrderNo` | 한 건씩 순차 처리 |
| 자동접수 판정 | 방출된 주문 | 메인 `isAutoReceipt` / KDS `isKdsAcceptOrders` | 4중 가드: `_autoAcceptingOrderIds`·`ProcessedOrderCache`·`_selfAcceptedOrderIds`·`RecentRemovals` | `updateOrderStatus(PREPARING)` PUT |
| 상세조회 | 접수 대상 주문 | `getOrder` — transient 오류만 backoff [0, 0.5s, 1.5s] 3회 재시도 | 4xx/파싱은 즉시 실패. 실패 시 `_processNewOrder` 직접 호출 금지 | 실패 시 Sentry 보고 + 폴링 안전망(`refreshOrders`)으로 주문 누락 차단 |
| 출력·UI | PUT await 완료 | `_outputQueueService.add(NewOrderJob)` — PUT→add를 await로 직렬화 | enqueue 순서 = 주문번호 정렬 순서 보장 | 카드 표시 + 사운드 + 블링크 |
| 복구 | 메뉴 없는 주문 스킵 후 상세 복구 | `_pendingDetailReprint` Set → `fetchOrderDetail` API 성공 분기에서 1회 재발행 | `remove()` 원자성 + `_inFlightNewOrders` + `menus.isNotEmpty` | 출력 누락 자동 재발행, 중복 0 |

### 4.2 출력 파이프라인 (영수증 + 라벨)

| 단계 | 트리거 | 경로 | 가드 | 결과 |
| --- | --- | --- | --- | --- |
| 진입 | UI/자동접수의 fire-and-forget `add*()` | `OutputQueueService` — sealed `OutputJob` 4종(NewOrder/LabelOnly/Reprint/ReceiptReprint) 단일 진입점 | 4-set in-flight 락(`_inFlightNewOrders`·`_inFlightLabelTail`·`_inFlightLabelOnly`·`_inFlightReprints`) | `_receiptQueue`/`_labelQueue` **이중 직렬 큐** 분리 배분 |
| 라벨 선-enqueue | `NewOrderJob` 분해 | 라벨 tail을 영수증 await **이전에** `_labelQueue`로 enqueue | 라벨 PAPERNOFETCH 무한대기 ↔ 영수증 backoff 137s 상호 차단 방지 | 두 프린터 진짜 병렬 (영수증→라벨 순서 비보장) |
| 영수증 | `_receiptQueue` worker | `ReceiptEscPosBuilder`(CP949) → `ExternalReceiptPrinter` → `PrinterJobQueue` | backoff 7회(0/2/5/10/20/40/60s, 누적 137s) + sealed 결과 타입(Success/Busy/NoDevice/TransportError) | Android USB bulkTransfer / Windows COM DLE EOT probe |
| 라벨 | `_labelQueue` worker | `OutputService.printOrderLabels` → `LabelPrintData.fromOrder`(메뉴 `qty`만큼 N장 확장) → Android `MethodChannel printLabel` / Windows `WindowsLabelPrinterBackend`(FFI 직접 호출) | retry 1회(1.5s), paper-out/cover-up은 무한 대기(운영자 개입) | 최종 실패 시 Sentry `LabelPrintMissingException` |
| 정리 | 로그아웃 | `OrderProvider.cleanupOnLogout()` | — | `outputQueueService.clear()`(이중 큐 + in-flight 4-set) + 소켓·캐시·가드 Set 일괄 clear |

### 4.3 인증 · 세션

| 단계 | 트리거 | 경로 | 가드 | 결과 |
| --- | --- | --- | --- | --- |
| 로그인 | LoginScreen (storeId·password + 환경 선택) | `Auth.login` → prefix 전환 감지/정리 → `AppFitTokenManager.getValidToken` → `getProjectInfo`(projectId + AES apiKey) | 환경은 `AppFitConfig.configure()`로 main에서 선결정 | SecureStorage 저장 → `Store.setStoreModel` → WebSocket connect |
| 세션 복원 | 앱 재시작 | main 초기화 → 저장된 환경/자격증명 읽기 | 저장된 오더 토글로 영업 상태 복원 | `/home` 진입 |
| 로그아웃 | UI(HomeScreen 등) | **`Auth.logout()` 단일 진입점** — credentials/JWT/SecureStorage/SharedPreferences/WebSocket 정리 | `disconnect()` 후 dependency outdated → 모든 `ref.read()`는 호출 전 캐시 | UI 계층은 영업 상태 변경 + `OrderProvider` cleanup + 네비게이션만 담당 |
| 환경 변경 | 설정/로그인 화면 | `unauthenticate()` — WebSocket만 절단 | 전체 로그아웃과 구분 | 로그인 화면 복귀 |

### 4.4 OTA 자가 업데이트

| 단계 | 트리거 | 경로 | 가드 | 결과 |
| --- | --- | --- | --- | --- |
| Windows 체크 | 앱 시작(release) | `runStartupUpdateFlow()` → `WindowsUpdateService` → 채널 version JSON 비교 | 변형별 채널 URL 분리 (`UpdateConfig`) | 신규 버전 감지 |
| Windows 적용 | 신규 버전 존재 | ZIP 다운로드 → `updater.bat`(taskkill·robocopy) → `exit(0)` | 임시 폴더도 변형별 분리(동시 업데이트 충돌 방지) | 재시작으로 교체 완료. 사용자 설정(`%APPDATA%\co.kr.waldlust.order\...`)은 보존 |
| Android | 업데이트 확인 | `OtaConfig` → APK 다운로드 → app_installer | 변형별 version JSON/APK 파일명 분리 | APK 설치 |

## 5. 플랫폼 분기 (Android vs Windows)

| 관심사 | Android | Windows |
| --- | --- | --- |
| 네이티브 레이어 | Java (`android/.../receive/`) — MainActivity·NativeMethodHandler(MethodChannel `co.kr.waldlust.order.receive.appfit_order_agent`) | C++ (`windows/runner/`) — main.cpp 단일 인스턴스 뮤텍스 `Global\AppfitOrderAgent_SingleInstance_Mutex` |
| 내장 영수증 | Sunmi `SunmiPrintHelper` (ESC/POS) | 없음 |
| 외부 영수증 transport | USB 범용 — `bulkTransfer` (3-tier endpoint 선택 + 4-tier 후보 판정) | COM 시리얼 단일 경로 (`serial_port_win32`) — Winspool 폴백 의도적 배제 |
| 외부 영수증 false-success 방지 | `verifyConnection` (ESC `@` probe) | DLE EOT 1 probe (`cbInQue` 폴링 300ms) |
| 라벨 transport | Caysn AutoReplyPrint Java SDK (`autoreplyprint.aar`) — MethodChannel `printLabel` | `autoreplyprint.dll` Dart FFI (vendored `external/autoreplyprint/win64/`) — `WindowsLabelPrinterBackend` 직접 호출 |
| 라벨 ACK 신호 | `statusCallback` ACK 정상 동작 | ACK 미발화 펌웨어 존재 → paperFetch 비콘이 주 신호. stuck 시 3종 active clear |
| FFI/스레드 격리 | MethodChannel이 native 별도 thread 처리 | 동기 SDK 호출은 `Isolate.run` boxing (handle raw address만 cross-isolate) |
| 크래시 격리 | — | `external_receipt_printer_windows.dart`를 deferred import — Android 런타임의 win32 static initializer 크래시 방지 |
| KDS 버블 | `FloatingBubbleService` (오버레이) | `WindowsBubbleService` (80x80 플로팅 윈도우, originalSize 캐시) |
| 클라우드 동기화 | Firebase/Firestore (Android 전용) | 없음 |
| 자동 시작 | `AutoStartReceiver` (부팅 시) | 인스톨러/OS 설정 |
| 멤버십 바코드 | — | WaldPOS VAN Bridge (local TCP :8888) |
| 공통(통합된 부분) | `OutputQueueService` 이중 큐·`PrinterJobQueue` backoff·`ReceiptEscPosBuilder` 바이트·라벨 PNG 빌더·in-flight 락·Sentry 보고 — Dart 측 일원화 (transport 인터페이스만 공통, 그 위층은 의도적으로 OS별 유지) | (좌동) |

## 6. 배포 · OTA

### 6.1 단일 빌드 · 런타임 서버선택

단일 패키지(`co.kr.waldlust.order.receive.appfit`)·단일 exe(`appfit_order_agent.exe`)·**단일 빌드**가 한국/일본을 모두 서빙한다. 빌드 변형(`APPFIT_VARIANT` dart-define)은 제거됐다.

| 항목 | 내용 |
| --- | --- |
| 서버 결정 | 런타임 — 저장값(`appfit_environment`, 기본 `live`) + 로그인 화면 배지(KR/JP) 탭 선택(릴리즈 live/japanLive 2종) + 매장 ID 프리픽스 자동 전환(`BrandRegistry.serverEnvironment`: TPCP·PAIK→japanLive, MHST·MATA→live) |
| 미등록 프리픽스 | 명시 선택 이력 없으면 로그인 시 서버선택 다이얼로그 1회 강제 (`appfit_environment_manual_override` 기록) |
| Android 채널 | `appfit_order_agent_release_version.json` / `appfit_order_agent_release.apk` (단일) |
| Windows 채널 | `appfit_order_agent_windows_version.json` / `appfit_order_agent_windows.zip` (레거시 무접미 = 단일 채널, 기존 설치본 자연 업데이트) |
| 병존 설치 | 불가 (머신당 1개, 재설치 시 in-place 업그레이드) |

- 전환 시퀀스는 `login_screen.dart _applyEnvironment` — WebSocket 해제 → 환경 저장 → `AppFitConfig.configure` → 자격증명 정리 → tokenManager/dio invalidate (`appFitNotifierServiceProvider` invalidate 금지, 순서 변경 금지).
- **Android 레거시 무접미 채널 동결(FROZEN)**: 구 패키지(`co.kr.waldlust.order.receive`)로 설치된 일본 매장 1곳 전용 — 업로드 금지(수동 재설치 시까지). 구 `_japan`/`_korea` 채널은 폐기(미사용). 채널이 하나이므로 업로드 즉시 한국/일본 동시 롤아웃된다.
- 공통 OTA base URL: `http://waldpay.kokonutstamp2.com/`. 타임아웃: connect 15s / check 10s / download 10m.

### 6.2 버전 정본 이원화

| 플랫폼 | 정본 | 소비자 | 비고 |
| --- | --- | --- | --- |
| Android | `pubspec.yaml`의 `version` | `build_main.sh` / `deploy_apk.sh` / OTA APK | 현재 `3.0.0+161` |
| Windows | `pubspec.yaml`의 `version` (동일 정본) | `build_windows.ps1` / `deploy_windows.ps1` / `build_installer.ps1` / `archive_windows.ps1` — 파싱 후 `--build-name`/`--build-number`로 주입 | 현재 `3.0.0+161`. 구 `version_windows.txt`는 폐지(두 정본이 어긋나 OTA 사고 유발) |

### 6.3 빌드·배포 절차

| 대상 | 명령 | 산출/동작 |
| --- | --- | --- |
| 코드 생성 | `flutter pub run build_runner build --delete-conflicting-outputs` → `flutter pub run slang` | `.g.dart` + `strings.g.dart` (slang은 build_runner와 별개) |
| Android 로컬 빌드 | `./build_main.sh [standalone]` | 클린 + 릴리즈 APK (`.env`의 `APPFIT_AES_KEY`·`SENTRY_DSN` 필요) |
| Android 배포 | `./deploy_apk.sh [standalone]` | 빌드 + Lightsail SCP + 버전 JSON 갱신 |
| Windows 로컬 빌드 | `.\build_windows.ps1 [-Variant standalone]` | release 빌드 (zip 산출 X) |
| Windows OTA 배포 | `.\deploy_windows.ps1 [-Variant standalone]` | 빌드 + VC++ DLL 번들 + zip + SCP + version JSON 갱신 |
| Windows 인스톨러 | `.\build_installer.ps1 [-Variant standalone]` | Inno Setup 6 → `dist\AppfitOrderAgent-Setup-<semver>.exe` (신규 설치 전용, OTA 미사용) |

- Inno Setup: `installer/appfit_order_agent.iss` — `AppId` 영구 GUID 재생성 금지, `AppMutex`는 `main.cpp`의 뮤텍스 상수와 반드시 일치.
- VC++ 런타임 DLL(vcruntime140 등)은 빌드 스크립트가 자동 번들링.

## 7. 참고 자료

| 문서 | 내용 |
| --- | --- |
| [docs/ARCHITECTURE.md](ARCHITECTURE.md) | 데이터 흐름·Riverpod·서비스·UI·네이티브·브랜드·주요 패턴 (정본) |
| [docs/ORDER_FLOW.md](ORDER_FLOW.md) | 주문 수신·자동접수 흐름 도식 |
| [docs/PRINTER_FLOW.md](PRINTER_FLOW.md) | 출력/프린터 파이프라인 도식 |
| [docs/AUTH_FLOW.md](AUTH_FLOW.md) | 인증/세션 흐름 도식 |
| [docs/BRAND_I18N_FLOW.md](BRAND_I18N_FLOW.md) | 브랜드 해석·테마·i18n 파이프라인 도식 |
| [docs/BUILD_VARIANTS.md](BUILD_VARIANTS.md) | update/standalone 분기·채널 분리·버전 이원화 도식 |
| [docs/BUILD.md](BUILD.md) | 빌드/배포/환경/다국어 명령어 |
| [docs/BRAND_ASSETS.md](BRAND_ASSETS.md) | 브랜드 자산(BMP/PNG) 사양·추가 절차 |
| [docs/FLUTTER_GUIDELINES.md](FLUTTER_GUIDELINES.md) | 코드 스타일·Riverpod·라우팅·로깅 규약 |
| [docs/TESTING.md](TESTING.md) | characterization 전략·fake 패턴 |
| [docs/REFACTORING.md](REFACTORING.md) | 리팩토링 로드맵 (Phase 0~3) |
| [docs/WINDOWS_LABEL_PRINTER_GUIDE.md](WINDOWS_LABEL_PRINTER_GUIDE.md) | Windows 라벨 FFI 이식 가이드 |
| [CLAUDE.md](../CLAUDE.md) | 절대 규칙·핵심 명령어 |

신규 C4 모델(작성 예정) 폴더 경로: `/Users/kimsungchun/Documents/GitHub/appfit_order_agent/agentc4model`
