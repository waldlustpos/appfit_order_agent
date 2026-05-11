# 아키텍처

AppFit 주문 에이전트의 데이터 흐름·상태 관리·서비스 레이어·UI 구조 등 코드 탐색에 필요한 참조 정보입니다. 매 세션 자동 로드되는 [`CLAUDE.md`](../CLAUDE.md)에는 두지 않고, 필요할 때 참조하도록 분리했습니다.

## 데이터 흐름 개요

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

## 상태 관리: Riverpod

모든 상태는 `flutter_riverpod`를 사용하며, 장기 유지가 필요한 상태에는 `@Riverpod(keepAlive: true)`를 적용합니다. 핵심 프로바이더 (`lib/providers/`):

- `authProvider` — 로그인, WebSocket 연결 상태
- `orderProvider` — 주문 생명주기 전체 (조회, 접수, 완료, 취소)
- `kdsUnifiedProviders` — KDS 모드 토글, 탭 인덱스, 정렬 방향, 카드 크기
- `localeNotifierProvider` — 런타임 언어 전환 (ko/en/ja)
- `preferenceProvider` — `PreferenceService`에 대한 반응형 브릿지

추가 프로바이더(`brand_theme`, `kds_order_tracking`, `order_detail`, `order_history`, `membership`, `product`, `currency`, `lifecycle`, `rotation`, `store`, `app_info` 등)는 `lib/providers/`에서 직접 탐색합니다. 화면에서는 `ConsumerWidget` / `ConsumerStatefulWidget`을 사용하여 `ref.watch()` / `ref.read()`로 접근합니다.

## 서비스 레이어 (`lib/services/`)

- **ApiService** — Dio 기반 REST 클라이언트. 모든 요청은 `appfit_core`의 Dio 인터셉터를 경유 (자동 인증 헤더, `AppEnv.aesKey` 통한 AES-GCM 암호화). 엔드포인트 라우트는 `appfit_core`의 `ApiRoutes`에 정의.
- **PreferenceService** — `SharedPreferences` + `FlutterSecureStorage`를 감싸는 싱글톤. 모든 로컬 설정 관리. 최초 init 시 V2 마이그레이션 실행.
- **SecureStorageService** — `FlutterSecureStorage` 직접 래퍼. 자격증명·토큰 등 민감 데이터 저장.
- **PlatformService / PlatformBridgeService** — MethodChannel(`co.kr.waldlust.order.receive.appfit_order_agent`)을 통해 네이티브 Android 호출 (파일 로깅, 화면 회전, 백그라운드 모드, 시스템 UI 제어).
- **PrintService** — Sunmi 내장 / 외부 / 라벨 프린터로의 인쇄 명령 디스패치 (Android 경로).
- **LabelPrinterService** (Windows 전용, `lib/services/label_printer/label_printer_service.dart`) — `autoreplyprint.dll` Dart FFI. 단일 인스턴스(`instance`), 공개 API: `printBitmap` / `warmupOpen` / `calibrateLabel` / `dispose`. `CP_Pos_*` / `CP_Label_*` / `CP_Port_*` 호출 + ACK 콜백 + paperFetch 비콘 폴링(우선)으로 인쇄 완료 판정. main.dart 시작 시 `warmupOpen()` 으로 첫 라벨 지연 제거. (이식 예정 -- contract만 명시)
- **LabelPrintOrchestrator** (Windows 전용, `lib/services/label_printer/label_print_orchestrator.dart`) — `OutputQueueService` 의 `LabelOnlyJob` / `NewOrderJob` 이 dispatch 하는 Windows 측 실행기. 메뉴 `ordrCnt` 만큼 라벨 N장 확장 + 1회 retry(1.5s) + 최종 실패 시 Sentry `LabelPrintMissingException`. static `_inFlightOrderIds` set 으로 동일 주문 dedup, `clearAllInFlight()` 는 logout 정리 경로에서 호출.
- **LabelPrintData** (`lib/services/label_printer/label_print_data.dart`) — 모델-중립 DTO. `OrderModel` 을 라벨 N장으로 분해하는 어댑터(`fromOrder`) + 디버그용 `testSample`.
- **OutputQueueService** — 순차적 출력/인쇄 작업 큐 관리 (로그아웃 시 초기화). 4종 sealed `OutputJob` (`NewOrderJob` / `LabelOnlyJob` / `ReprintJob` / `ReceiptReprintJob`) 양 플랫폼 공통 진입점.
- **OverlayService** — 플로팅 버블 오버레이 윈도우 제어.
- **LocalServerService** — 로컬 HTTP 수신용 경량 서버 (외부 트리거 수용).
- **WindowsBubbleService** (Windows 전용) — KDS 버블 모드(80x80 플로팅 윈도우) 진입/복귀. 본 윈도우 ↔ 버블 윈도우 전환 시 LayoutBuilder가 카드 size 트랜지션을 재생하지 않도록 originalSize를 캐시.
- **WindowsPrintService** / **ComPortPrintService** (Windows 전용) — Windows ESC/POS 인쇄. COM 포트 직결과 윈도우 스풀러 raw 두 갈래 경로.
- **WindowsUpdateService** (Windows 전용) — OTA 자동 업데이트 체크/다운로드/재시작. UI는 `lib/widgets/update/update_progress_dialog.dart`.
- **WindowsLogFileWriter** (Windows 전용) — 시작 시 오래된 로그 파일 자동 삭제.
- `services/appfit/` — `AppFitProviders`, `KokonutAppFitLogger` 등 `appfit_core` 어댑터.
- `services/migration/` — `V2MigrationService` / `V2MigrationLogger` (PreferenceService 최초 init 시 실행되는 V2 마이그레이션).
- `services/monitoring/` — `OrderAgentMonitoringContext` (Sentry 연동), `MonitoringSyncProvider` (사용자/스토어 컨텍스트 동기화).

## 부수 효과: `lib/core/orders/`

- `SoundService`, `BlinkService`, `OutputService` — 신규 주문 시 알림음·점멸·출력 처리. `printOrderLabels()` 는 `Platform.isWindows` 분기: Windows 는 `LabelPrintOrchestrator` 경유 FFI, Android 는 기존 `MethodChannel printLabel` 유지. `OutputQueueService` 직렬화 + `_inFlightNewOrders` / `_inFlightLabelOnly` / `_inFlightReprints` 3-set in-flight 락은 양 플랫폼 공통.
- `AlertManager` — 알림 표시 라이프사이클 통합
- `OrderQueueService` — 주문 처리 작업 직렬화
- `cache/` — `OrderDetailCache`, `PrintedOrderCache`, `ProcessedOrderCache`, `ActionCache` (인메모리 캐시로 중복 실행 방지)

## 외부 의존성: appfit_core

`../packages/appfit_core` 경로의 로컬 패키지 (path 의존성). 여러 AppFit 앱에서 공유하는 인프라 제공:

- `AppFitConfig` — 환경 enum (`live`, `japanLive`, `dev`, `staging`) 및 base URL 결정
- `AppFitTokenManager` — 보안 토큰 저장 및 갱신
- `AppFitDioProvider` — 인증 인터셉터가 포함된 Dio 인스턴스
- `AppFitLogger` / `SentryAppFitLogger` — 로깅 인터페이스
- `MonitoringService` / `MonitoringContext` — Sentry 래퍼 + 컨텍스트 인터페이스 (`OrderAgentMonitoringContext`가 구현하여 Sentry 초기화·오류 캡처·breadcrumb 단일 진입점 제공)
- `CryptoUtils` — AES-GCM 암호화/복호화
- `ApiRoutes` — 중앙화된 API 엔드포인트 경로

## 네이티브 레이어

### Android

Java 소스 위치: `android/app/src/main/java/co/kr/waldlust/order/receive/`

- `MainActivity.java` — Flutter 엔진 호스트
- `NativeMethodHandler.java` — MethodChannel 핸들러 (인쇄, 로깅, 시스템 제어)
- `util/print/` — Sunmi 내장 프린터(`SunmiPrintHelper`), 외부 프린터, 라벨 프린터(`LabelPrinter`) ESC/POS 명령 사용
- `overlay/FloatingBubbleService.java` — 플로팅 오버레이 윈도우
- `AutoStartReceiver.java` — 부팅 시 자동 시작

### Windows

C++ 소스 위치: `windows/runner/` (`flutter_window.cpp`, `main.cpp`, `CMakeLists.txt`)

- 단일 인스턴스 뮤텍스: `Global\AppfitOrderAgent_SingleInstance_Mutex`. `windows/runner/main.cpp`의 `kSingleInstanceMutexName` 상수와 `installer/appfit_order_agent.iss`의 `AppMutex`가 **반드시 일치**해야 함 (불일치 시 인스톨러의 single-instance 종료 로직과 런타임 가드가 어긋남).
- 빌드 산출물: `build/windows/x64/runner/Release/`
- VC++ 런타임 DLL(`vcruntime140.dll`, `vcruntime140_1.dll`, `msvcp140.dll`)은 빌드 스크립트가 자동 번들링하므로 대상 PC에 Visual C++ Redistributable이 없어도 동작.
- **라벨 프린터 SDK** (이식 예정): `external/autoreplyprint/win64/` 에 `autoreplyprint.dll` (1.7MB) + `autoreplyprint.h` + `autoreplyprint.lib` 벤더링. `windows/runner/CMakeLists.txt` post-build 단계에서 (1) runner exe 디렉토리로 `copy_if_different` (2) Inno Setup `[Files]` 에 포함되도록 `install(FILES ... DESTINATION ... COMPONENT Runtime)` 디렉티브 등록. DLL 누락 시 빌드 경고 + 런타임 `DynamicLibrary.open()` 실패. Dart 측 로딩은 `lib/services/label_printer/autoreplyprint_bindings.dart` 의 `AutoReplyPrintBindings.tryGet()` 가 단일 인스턴스로 캐시.

## 라벨 프린터 파이프라인

ACCEPTED 진입 시 메뉴별 `ordrCnt` 만큼 라벨을 자동 출력. 진입점은 `OutputQueueService` 로 고정 (Android / Windows 동일).

```
주문 수신 ──► OrderProvider ──► OutputQueueService.add(NewOrderJob) ──► OutputService
                                                                            │
                                                              Platform.isWindows
                                                              ┌─────────────┴─────────────┐
                                                              │                           │
                                                          Android                       Windows
                                                              │                           │
                                                  MethodChannel printLabel    LabelPrintOrchestrator
                                                              │                           │
                                                       LabelPrinter.java          LabelPrinterService
                                                              │                           │
                                                          Caysn SDK             autoreplyprint.dll (FFI)
```

플랫폼별 비명시 invariant 카탈로그(11+17개)와 진단 시나리오는 [`.claude/agents/label-printer-inspector.md`](../.claude/agents/label-printer-inspector.md) 참조. **Windows FFI + 백엔드 단독 이식 가이드**(다른 Flutter 프로젝트 대상): [docs/WINDOWS_LABEL_PRINTER_GUIDE.md](WINDOWS_LABEL_PRINTER_GUIDE.md). 핵심 공통 규칙:

- **`OutputQueueService` 단일 진입점**: 4종 sealed `OutputJob` (`NewOrderJob` / `LabelOnlyJob` / `ReprintJob` / `ReceiptReprintJob`) 모두 `add()` 경유. `lib/widgets/settings/settings_label_test_section.dart` 의 라벨 테스트 위젯만 의도적 우회 (자동접수 흐름 영향 차단).
- **3-set in-flight 락**: `_inFlightNewOrders` / `_inFlightLabelOnly` / `_inFlightReprints` 양 플랫폼 공통. 짝(`add` ↔ `whenComplete(remove)`) 깨지면 동일 주문 영구 enqueue 차단 또는 다중 enqueue.
- **`autoReplyMode=1` + 인쇄 완료 ACK/비콘 우선**: Android 는 ACK 콜백 정상 동작, Windows 는 일부 펌웨어/SDK 조합에서 ACK 미발화 -> paperFetch 비콘이 주 신호. 두 신호 모두 등록은 race 안전망으로 필수.
- **paper-out / cover-up = 무한 대기** (운영자 개입 신뢰), **그 외 ERROR = 짧은 게이트 후 retry** (호출자 위임). Windows ERROR 게이트는 0.5초, Android 와 동등.
- **최종 실패 시 Sentry `LabelPrintMissingException`** 송신 -- production observability 의 일부. Windows 는 `LabelPrintOrchestrator` 의 1.5s retry 후 `failedIndices.isNotEmpty` 시 발화, Android 는 `output_service.dart` `_printLabelWithRetry` 후 발화.
- **logout 정리**: `OrderProvider.cleanupOnLogout()` 에서 `_outputQueueService.clear()` + `LabelPrintOrchestrator.clearAllInFlight()` 둘 다 호출.

## UI 구조

가로 전용 단일 모드 토글(`HomeScreen` ↔ `KdsScreen`):

1. **일반 모드** (`HomeScreen`) — 주문 현황, 주문 내역, 상품 관리, 멤버십으로 구성된 탭 뷰
2. **KDS 모드** (`KdsScreen`) — 상태별 탭(신규/진행/픽업/완료/취소)을 가진 주방 디스플레이 그리드, 자동 스크롤, 카드 기반 레이아웃. Windows에서는 **버블 모드(80x80 플로팅 윈도우)**로 토글 가능하며, 본 윈도우 ↔ 버블 윈도우 전환 시 카드 사이즈 트랜지션을 막기 위해 originalSize를 캐시(`WindowsBubbleService`).

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

## UI 리빌드 비용 모델

WebSocket 푸시 / 폴링 / 자정 새로고침으로 주문 상태가 빈번히 갱신되는 환경에서 화면 전체 리빌드를 피하기 위한 규약. 새 모델 / 카드 위젯 / 컴퓨티드 프로바이더 추가 시 아래 원칙을 우선 적용한다.

1. **모델 동등성 규칙** — `lib/models/` 는 freezed 금지(CLAUDE.md). `==`/`hashCode` 는 수동 구현.
   - hashCode 키에 **mutable 필드 포함 금지** — `final` 아닌 필드(`OrderModel.userName`/`storeName`), 내부 캐시(`_cachedSpecialProductType`) 제외.
   - 파생 필드(`OrderModel.exceptTaxPrice`/`taxPrice` 같은 `paymentAmount` 파생값)는 키에 넣지 않는다.
   - 리스트 필드는 `listEquals` 사용(`package:flutter/foundation.dart`). 원소 타입이 `==` 미구현이면 identity 폴백되어 효과 반감 — 원소 모델에도 `==` 정의 필수.

2. **시간 필드 자동 갱신 금지** — `copyWith` 의 `updateTime` 같은 시간 필드는 **명시 전달이 있을 때만 갱신**. `updateTime: updateTime ?? this.updateTime` 패턴. `DateTime.now()` 자동 주입은 `==` 비교를 무력화해 select / listEquals 효과를 모두 잃는다.

3. **`copyWith` early-return 가드** — 모든 인자가 기존값과 동일하면 `this` 그대로 반환. `error` 같이 `null` 로 의도적 reset 이 필요한 필드는 `const _unset = Object();` sentinel 패턴으로 "전달됨" vs "기본값" 을 구분(`OrderState.copyWith` 참고).

4. **리스트 참조 안정성** — 상태 업데이트 시 동일 내용이면 기존 List 참조 유지. `state.copyWith(orders: ...)` 직접 호출보다 헬퍼(`_setOrders`) 경유로 `identical` / `listEquals` 가드 통일.

5. **Riverpod watch 정책**
   - `ref.watch(orderProvider)` 같은 **전체 watch 금지**. `select` 또는 컴퓨티드 프로바이더(`orderStatusOrdersProvider`, `kdsTabOrdersProvider` 등) 경유.
   - Map / List 를 watch 하는 자식 위젯은 부모와 같은 provider 를 다시 전체 watch 하지 않는다 — 카드 단위는 `select((map) => map[orderId])` 패턴.
   - 카드 위젯이 부모로부터 모델 prop 을 받는 대신 `orderByIdProvider(id)` family 로 직접 구독하면 부모 리빌드와 디커플링.

6. **`RepaintBoundary` 정책** — 화면을 N분할하는 카드 / 타일 위젯의 **최외곽**에 적용. 일반모드(`OrderCardWidget`)·KDS(`KdsOrderCard`) 동일.

7. **`ListView.builder` 아이템 키** — 정렬 / 필터 변경 가능성이 있는 리스트는 `ValueKey(item.id)` 부여. 미적용 시 정렬 변경 후 InkWell 상태 / 애니메이션이 이웃 아이템과 뒤바뀜.

8. **build 중 부수효과 금지** — `WidgetsBinding.instance.addPostFrameCallback` 으로 외부 호출(상세 fetch 등) 등록은 `initState` / `didUpdateWidget` / `ref.listen` 으로 이동. build 마다 콜백이 큐잉되어 누적된다.

### 적용된 컴퓨티드 프로바이더 (`lib/providers/order_computed_providers.dart`)

| Provider | 반환 | 캐싱 조건 | 사용처 |
|---|---|---|---|
| `orderStatusOrdersProvider` | record (4탭 — `newOrders` / `confirmedOrders` / `pickupedOrders` / `completedOrders`) | `orderProvider.orders` 미변경 시 캐싱(P0 equality) | `OrderStatusScreen` |
| `kdsTabOrdersProvider` | record (5탭 리스트 + 5탭 카운트) | `orders` + `kdsTabSortDirectionsProvider` 미변경 시 캐싱 | `KdsScreen` 메인 빌드 |
| `kdsHistoryAllOrdersProvider` | record (`orders`, `isLoading`) | `orderHistoryProvider` + 전체 탭 정렬 방향 미변경 시 캐싱 | 과거 날짜 KDS 전체 탭 |
| `ordersByIdProvider` | `Map<String, OrderModel>` 인덱스 | `orders` 미변경 시 캐싱 | `orderByIdProvider` 백킹 |
| `orderByIdProvider` family (autoDispose) | `OrderModel?` | `map[id]` 동일 시 캐싱(P0 OrderModel equality) | 카드 단위 1주문 조회 |

### 카드 위젯 카탈로그

| 위젯 | 파일 | 책임 |
|---|---|---|
| `OrderCardWidget` (`ConsumerStatefulWidget`) | [lib/widgets/home/order_card_widget.dart](lib/widgets/home/order_card_widget.dart) | 일반모드 주문 카드. `orderByIdProvider(orderId)` 로 자기 주문만 watch. `initState`/`didUpdateWidget` 에서 상세 fetch. `RepaintBoundary` 적용. `isKdsMode` prop 으로 KDS 전체 탭 그리드(KDS 모드)에서도 재사용. |
| `KdsOrderCard` (`ConsumerStatefulWidget`) | [lib/widgets/kds/kds_order_card.dart](lib/widgets/kds/kds_order_card.dart) | KDS 5탭 카드. `_buildSimpleCard` / `_buildScrollableCard` 모두 `RepaintBoundary` 적용. 스크롤 버튼 표시는 `kdsScrollButtonStatesProvider.select((map) => map[orderId])`. |
| `KdsScrollUpButtonWidget` / `KdsScrollDownButtonWidget` | [lib/widgets/kds/kds_scroll_button_widget.dart](lib/widgets/kds/kds_scroll_button_widget.dart) | `kdsScrollButtonStatesProvider.select((map) => map[orderId]?.canScrollUp/Down ?? false)` 로 자기 카드의 스크롤 가능성만 watch. |

### `OrderModel` equality 키 (확정본 — [order_model.dart](lib/models/order_model.dart))

**포함**: `orderNo`, `shopOrderNo`, `displayOrderNo`, `orderStatus`, `status`, `orderedAt`, `updateTime`, `totalAmount`, `paymentAmount`, `discountAmount`, `paymentType`, `paymentCode`, `paidAt`, `note`, `orderCount`, `ordererName`, `kioskId`, `source`, `orderType`, `kdsOrderType`, `isDetailLoaded`, `storeId`, `userId`, `customerName`, `tel`, `discountTypes`(listEquals), `menus`(listEquals).

**제외 — 이유**:
- `userName`, `storeName` — `final` 아님(mutable).
- `_cachedSpecialProductType` — 내부 캐시.
- `exceptTaxPrice`, `taxPrice` — `paymentAmount` 파생값.

`copyWith` 의 `updateTime` 은 명시 전달 없으면 `this.updateTime` 보존(`DateTime.now()` 자동 주입 X).

## 브랜드 테마

`lib/constants/brand_theme.dart`의 `BrandTheme` enum(예: `appfitDefault`, `mammothCoffee`)이 매장별 색상·로그인 배경·로고를 정의. `main()`에서 `AppStyles.applyBrand(savedBrand)`로 정적 색상 값을 부팅 시 1회 고정합니다. `BrandThemeNotifier`(`lib/providers/brand_theme_provider.dart`)의 `selectTheme()`은 `PreferenceService`에만 저장하며, 색상 교체는 **앱 재시작 후** 반영됩니다(런타임 즉시 변경 X).

## 주요 패턴

- **모델**: `lib/models/`에 수동 작성된 클래스 (freezed 아님), 수동 `fromJson`/`toJson`. `OrderModel`이 핵심 데이터 객체.
- **Enum**: `lib/models/enums/` — `OrderStatus`, `OrderAction` 등.
- **Order Provider 분해**: `Order` 프로바이더(`order_provider.dart`)는 매니저 클래스(`OrderSocketManager`, `OrderTimerManager`, `OrderQueueManager`, `OrderCacheManager`, `OrderSettingsManager`, `OrderStateManager`)에 위임하여 메인 프로바이더를 가볍게 유지. `OrderSocketManager`는 `appfit_core` v1.0.8의 `SocketEventDispatcher` / `RecentRemovalsCache` / `OrderEventIgnorePolicy`로 위임하여 WebSocket 이벤트 라우팅과 자동접수 race / 상태 다운그레이드 방지를 일원화.
- **캐싱**: `lib/core/orders/cache/` — 주문 상세, 출력 완료, 처리 완료, 액션 중복 방지를 위한 인메모리 캐시.
- **알림음/점멸/출력**: `lib/core/orders/` — `SoundService`, `BlinkService`, `OutputService`, `AlertManager`가 알림 부수 효과 처리.
- **라벨 프린터 플랫폼 분기**: `OutputService.printOrderLabels()` 에서 `Platform.isWindows` 로 갈라짐. Windows = `LabelPrintOrchestrator` -> `LabelPrinterService` (FFI), Android = `MethodChannel printLabel` -> `LabelPrinter.java`. `OutputQueueService` 직렬화 + 3-set in-flight 락 + Sentry `LabelPrintMissingException` 은 양 플랫폼 공통. 자세한 흐름은 [라벨 프린터 파이프라인](#라벨-프린터-파이프라인) 섹션.
- **모니터링**: `OrderAgentMonitoringContext`가 `appfit_core`의 `MonitoringContext`를 구현하여 Sentry 초기화·오류 캡처·breadcrumb를 단일 진입점에서 처리. `MonitoringSyncProvider`가 사용자/스토어 변경 시 컨텍스트를 동기화.
- **순차 비동기 큐**: `lib/utils/serial_async_queue.dart`의 `SerialAsyncQueue<T>`로 USB 프린터·TTS 등 공유 자원 경쟁을 방지. `appfit_core`의 동일 클래스(v1.0.6 deprecated)에서 자체 구현으로 이전됨. `OutputQueueService`가 대표 사용처.
- **인증/세션 정리**: `Auth.logout()`(`lib/providers/auth_provider.dart`)이 credentials/JWT/SecureStorage(projectId·apiKey)/SharedPreferences/WebSocket을 정리하는 **단일 진입점**. UI 계층(예: `HomeScreen`)은 이 메서드만 호출하고 영업 상태 변경·`OrderProvider` cleanup·네비게이션을 담당. `disconnect()` 후 dependency가 outdated되므로 모든 `ref.read()`는 disconnect 호출 전에 미리 캐시. `unauthenticate()`는 환경 변경 시 WebSocket만 끊고 로그인 화면으로 복귀.
- **라우팅**: 세 개의 명명된 라우트: `/login`, `/home`, `/settings`.
