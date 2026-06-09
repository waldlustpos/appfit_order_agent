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

주문은 **WebSocket**(기본, 실시간)과 **REST API 폴링**(폴백)으로 수신됩니다. `OrderProvider`는 `lib/providers/order/order_*.dart` 하위의 매니저 클래스로 분해되어 있습니다. 부수 효과 서비스(알림음, 점멸, 출력)는 `lib/core/orders/`에 위치합니다.

신규 주문 수신 시 상세조회(`getOrder`)가 서버오류·인터넷 순단으로 실패하면 소켓 호출부 재시도 → 폴링 안전망 트리거로 **주문 누락(silent drop)** 을 막고, 출력이 누락된 주문은 메뉴 복구 시 **복구 큐**가 자동 재발행합니다(아래 [주요 패턴](#주요-패턴) "상세조회 실패 대응 + 복구 큐" 참조).

## 상태 관리: Riverpod

모든 상태는 `flutter_riverpod`를 사용하며, 장기 유지가 필요한 상태에는 `@Riverpod(keepAlive: true)`를 적용합니다. 프로바이더는 도메인별 하위 폴더로 분리됩니다 — 주문 생명주기 매니저는 `lib/providers/order/`, KDS 모드·추적은 `lib/providers/kds/`, 그 외 단일 프로바이더는 `lib/providers/` 직하. `lib/providers/providers.dart` 는 공개 표면 barrel(**export 전용**)이며, 인라인 프로바이더/상태/확장 정의는 `lib/providers/misc_providers.dart` 에 둡니다. 핵심 프로바이더:

- `authProvider` — 로그인, WebSocket 연결 상태
- `orderProvider` — 주문 생명주기 전체 (조회, 접수, 완료, 취소)
- `kdsUnifiedProviders` — KDS 모드 토글, 탭 인덱스, 정렬 방향, 카드 크기
- `localeNotifierProvider` — 런타임 언어 전환 (ko/en/ja)
- `preferenceProvider` — `PreferenceService`에 대한 반응형 브릿지

추가 프로바이더(`brand_theme`, `kds_order_tracking`, `order_detail`, `order_history`, `membership`, `product`, `currency`, `lifecycle`, `rotation`, `store`, `app_info` 등)는 `lib/providers/` 와 그 하위(`order/` · `kds/`)에서 직접 탐색합니다. 화면에서는 `ConsumerWidget` / `ConsumerStatefulWidget`을 사용하여 `ref.watch()` / `ref.read()`로 접근합니다.

> 개발 전용 코드(`mock_order_generator`, `socket_burst_test` 등 출고 빌드에 불필요한 도구)는 프로덕션 코드와 섞지 않고 `lib/dev/` 에 격리합니다.

## 서비스 레이어 (`lib/services/`)

- **ApiService** — Dio 기반 REST 클라이언트. 모든 요청은 `appfit_core`의 Dio 인터셉터를 경유 (자동 인증 헤더, `AppEnv.aesKey` 통한 AES-GCM 암호화). 엔드포인트 라우트는 `appfit_core`의 `ApiRoutes`에 정의.
- **PreferenceService** — `SharedPreferences` + `FlutterSecureStorage`를 감싸는 싱글톤. 모든 로컬 설정 관리. 최초 init 시 V2 마이그레이션 실행.
- **SecureStorageService** — `FlutterSecureStorage` 직접 래퍼. 자격증명·토큰 등 민감 데이터 저장.
- **PlatformService / PlatformBridgeService** — MethodChannel(`co.kr.waldlust.order.receive.appfit_order_agent`)을 통해 네이티브 Android 호출 (파일 로깅, 화면 회전, 백그라운드 모드, 시스템 UI 제어).
- **PrintService** — Sunmi 내장 / 외부 / 라벨 프린터로의 인쇄 명령 디스패치 (Android 경로).
- **LabelPrinterService** (Windows 전용, `lib/services/label_printer/label_printer_service.dart`) — `autoreplyprint.dll` Dart FFI. 단일 인스턴스(`instance`), 공개 API: `printBitmap` / `warmupOpen` / `calibrateLabel` / `dispose`. `CP_Pos_*` / `CP_Label_*` / `CP_Port_*` 호출 + ACK 콜백 + paperFetch 비콘 폴링(우선)으로 인쇄 완료 판정. main.dart 시작 시 `warmupOpen()` 으로 첫 라벨 지연 제거. (이식 예정 -- contract만 명시)
- **LabelPrintOrchestrator** (Windows 전용, `lib/services/label_printer/label_print_orchestrator.dart`) — `OutputQueueService` 의 `LabelOnlyJob` / `NewOrderJob` 이 dispatch 하는 Windows 측 실행기. 메뉴 `ordrCnt` 만큼 라벨 N장 확장 + 1회 retry(1.5s) + 최종 실패 시 Sentry `LabelPrintMissingException`. static `_inFlightOrderIds` set 으로 동일 주문 dedup, `clearAllInFlight()` 는 logout 정리 경로에서 호출.
- **LabelPrintData** (`lib/services/label_printer/label_print_data.dart`) — 모델-중립 DTO. `OrderModel` 을 라벨 N장으로 분해하는 어댑터(`fromOrder`) + 디버그용 `testSample`.
- **OutputQueueService** — 순차적 출력/인쇄 작업 큐 관리 (로그아웃 시 초기화). 4종 sealed `OutputJob` (`NewOrderJob` / `LabelOnlyJob` / `ReprintJob` / `ReceiptReprintJob`) + 내부 tail (`_NewOrderLabelTail`) 양 플랫폼 공통 진입점. **영수증/라벨 두 직렬 큐 분리**(`_receiptQueue` / `_labelQueue`) — 라벨 떼기(PAPERNOFETCH) 무한 대기와 영수증 PrinterJobQueue 의 backoff(최대 137s)가 서로를 막지 않도록 worker 별개. 같은 `NewOrderJob` 안의 라벨 부분은 **영수증 await 보다 먼저** `_labelQueue` 로 enqueue 되어 두 프린터가 진짜 병렬 동작 (영수증→라벨 순서는 보장하지 않음 — 라벨이 영수증보다 먼저 나올 수 있음).
- **OverlayService** — 플로팅 버블 오버레이 윈도우 제어.
- **LocalServerService** — 로컬 HTTP 수신용 경량 서버 (외부 트리거 수용).
- **WindowsBubbleService** (Windows 전용) — KDS 버블 모드(80x80 플로팅 윈도우) 진입/복귀. 본 윈도우 ↔ 버블 윈도우 전환 시 LayoutBuilder가 카드 size 트랜지션을 재생하지 않도록 originalSize를 캐시.
- **ComPortPrintService** / **WindowsTransport** (Windows 전용) — Windows ESC/POS 외부 영수증 프린터. **COM 포트 단일 경로** (Winspool 폴백 의도적으로 배제 — 사용자가 명시 설정하지 않은 OS default 프린터에 영수증이 잘못 송출되는 사고 차단). `comPort` 미설정이면 즉시 `PrinterNoDevice`, 설정 시 USB-Serial CDC re-enumerate lag 와 패키지 cache 잔재까지 능동 방어(enumerate polling + failure-cooldown settle + 안전 close). false-success 방어는 DLE EOT 1 probe 가 담당. 8가지 사유로 분류된 `_lastFailureReason` 을 `WindowsTransport` 가 PrinterBusy / PrinterNoDevice / PrinterTransportError 결과 타입에 매핑.
- **WindowsUpdateService** (Windows 전용) — OTA 자동 업데이트 체크/다운로드/재시작. UI는 `lib/widgets/update/update_progress_dialog.dart`.
- **WindowsLogFileWriter** (Windows 전용) — 시작 시 오래된 로그 파일 자동 삭제.
- `services/appfit/` — `AppFitProviders`, `KokonutAppFitLogger` 등 `appfit_core` 어댑터.
- `services/migration/` — `V2MigrationService` / `V2MigrationLogger` (PreferenceService 최초 init 시 실행되는 V2 마이그레이션).
- `services/monitoring/` — `OrderAgentMonitoringContext` (Sentry 연동), `MonitoringSyncProvider` (사용자/스토어 컨텍스트 동기화).

## 부수 효과: `lib/core/orders/`

- `SoundService`, `BlinkService`, `OutputService` — 신규 주문 시 알림음·점멸·출력 처리. `printOrderLabels()` 는 `Platform.isWindows` 분기: Windows 는 `LabelPrintOrchestrator` 경유 FFI, Android 는 기존 `MethodChannel printLabel` 유지. `OutputQueueService` 직렬화 + `_inFlightNewOrders` / `_inFlightLabelOnly` / `_inFlightReprints` 3-set in-flight 락은 양 플랫폼 공통.
- `AlertManager` — 알림 표시 라이프사이클 통합
- `OrderQueueService` — 주문 처리 작업 직렬화
- `cache/` — `OrderDetailCache`, `ProcessedOrderCache` (인메모리 캐시로 중복 실행 방지)

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

- **`OutputQueueService` 단일 진입점**: 4종 sealed `OutputJob` (`NewOrderJob` / `LabelOnlyJob` / `ReprintJob` / `ReceiptReprintJob`) 모두 `add*()` 경유. `lib/widgets/settings/settings_label_test_section.dart` 의 라벨 테스트 위젯만 의도적 우회 (자동접수 흐름 영향 차단).
- **이중 큐 진짜 병렬화**: `_receiptQueue` / `_labelQueue` 가 별개 `SerialAsyncQueue<OutputJob>` worker 로 돌고, `NewOrderJob` 의 라벨 부분(`_NewOrderLabelTail`) 은 **영수증 await 보다 먼저** 라벨 큐로 enqueue. 이게 깨지면 외부 영수증 backoff 137s 동안 라벨 출력이 막히는 사고 직행. 로그 prefix `[ReceiptQueue]` / `[LabelQueue]` 로 큐별 추적.
- **3-set in-flight 락**: `_inFlightNewOrders` / `_inFlightLabelOnly` / `_inFlightReprints` 양 플랫폼 공통. 짝(`add` ↔ `whenComplete(remove)`) 깨지면 동일 주문 영구 enqueue 차단 또는 다중 enqueue.
- **`autoReplyMode=1` + 인쇄 완료 ACK/비콘 우선**: Android 는 ACK 콜백 정상 동작, Windows 는 일부 펌웨어/SDK 조합에서 ACK 미발화 -> paperFetch 비콘이 주 신호. 두 신호 모두 등록은 race 안전망으로 필수.
- **paper-out / cover-up = 무한 대기** (운영자 개입 신뢰), **그 외 ERROR = 짧은 게이트 후 retry** (호출자 위임). Windows ERROR 게이트는 0.5초, Android 와 동등.
- **최종 실패 시 Sentry `LabelPrintMissingException`** 송신 -- production observability 의 일부. Windows 는 `LabelPrintOrchestrator` 의 1.5s retry 후 `failedIndices.isNotEmpty` 시 발화, Android 는 `output_service.dart` `_printLabelWithRetry` 후 발화.
- **logout 정리**: `OrderProvider.cleanupOnLogout()` 에서 `_outputQueueService.clear()` + `LabelPrintOrchestrator.clearAllInFlight()` 둘 다 호출.

## 프린터 구현 매트릭스 (OS × 용도)

외부 영수증 프린터 + 라벨 프린터를 Android / Windows 양 OS 에서 어떻게 구현하는지 4 케이스 비교. 비명시적 invariant 카탈로그와 진단 시나리오는 [`external-receipt-printer-inspector`](../.claude/agents/external-receipt-printer-inspector.md) / [`label-printer-inspector`](../.claude/agents/label-printer-inspector.md) agent 참조.

### 4 케이스 transport 경로

|  | 외부 영수증 프린터 | 라벨 프린터 |
|---|---|---|
| **Android** | `ExternalReceiptPrinter._sendBytes` → `PrinterJobQueue.enqueue` → `AndroidUsbTransport.send` → MethodChannel `printReceiptBytes` → `NativeMethodHandler.java` → `UsbReceiptPrinter.java` → `bulkTransfer` (3-tier endpoint 선택 + 4-tier 후보 판정) | `OutputService.printOrderLabels` → MethodChannel `printLabel` → `LabelPrinter.java` → Caysn AutoReplyPrint Java SDK (PNG bytes) |
| **Windows** | `ExternalReceiptPrinter._sendBytes` → `PrinterJobQueue.enqueue` → `WindowsTransport.send` → `ComPortPrintService.sendRaw` → `serial_port_win32` SerialPort (COM 단일 경로, DLE EOT 1 probe) | `OutputService.printOrderLabels` → `LabelPrintOrchestrator.printOrderLabels` → `WindowsLabelPrinterBackend.printPng` → `autoreplyprint.dll` Dart FFI (`CP_Port_OpenUsb` / `CP_Label_PageBegin` / `DrawImageFromData` / `PagePrint`) |
| **Dart 진입점** | `ExternalReceiptPrinter` ([external_receipt_printer.dart](../lib/services/external_receipt_printer.dart)) | `PrintService.printLabel` ([print_service.dart](../lib/services/print_service.dart)) — 내부에서 `Platform.isWindows` 분기 |

### 공통화된 부분 (양 OS 동일 코드 경로)

큐 / 결과 분류 / 운영 observability / 바이트 빌더 — Dart 측에서 일원화.

- **이중 직렬 큐**: `OutputQueueService._receiptQueue` / `_labelQueue` 별개 `SerialAsyncQueue` worker. `NewOrderJob` 의 라벨 tail 은 영수증 await **이전** 에 라벨 큐로 enqueue 되어 진짜 병렬 동작 (양 OS 동일).
- **영수증 backoff 큐**: `PrinterJobQueue` 글로벌 직렬 큐 — backoff 7회 (0/2/5/10/20/40/60s, 누적 137s) + `onFinalFailure` 콜백. AndroidUsbTransport / WindowsTransport 가 같은 `PrinterTransport` 인터페이스 구현, 결과 타입 sealed (`PrinterSuccess` / `PrinterBusy` / `PrinterNoDevice` / `PrinterTransportError`).
- **라벨 in-flight 락**: 3-set (`_inFlightNewOrders` / `_inFlightLabelOnly` / `_inFlightReprints`) — 동일 주문 다중 enqueue 방지.
- **라벨 retry**: `OutputService._printLabelWithRetry` 1.5s 1회 (양 OS 동일). autoReplyMode=1 정착 후 실제 발화 시 거의 진짜 실패.
- **라벨 누락 보고**: Sentry `LabelPrintMissingException` — Windows 는 `LabelPrintOrchestrator` 의 1.5s retry 후, Android 는 `OutputService` 의 `_printLabelWithRetry` 후.
- **라벨 진입 게이트 정책**: paper-out / cover-up / NoPaperCanceled → **무한 대기** (운영자 개입 신뢰), 그 외 ERROR → 0.5s 짧은 게이트 후 false (호출자 retry). 양 OS 동등 의도.
- **`autoReplyMode=1` invariant**: 양 OS 모두 라벨 출력 진입 직전 ACK 콜백 등록 + autoReplyMode=1. 0 회귀 시 동일 라벨 2장 인쇄 사고.
- **ESC/POS 바이트 빌더**: `ReceiptEscPosBuilder` ([receipt_escpos_builder.dart](../lib/services/receipt_escpos_builder.dart)) — 영수증/주문서/테스트 페이지 ESC/POS CP949 byte stream 생성. Android USB + Windows COM 양쪽 동일 바이트 입력 (hex dump 1:1 일치).
- **라벨 PNG 빌더**: `LabelPainter` 가 라벨 1장 PNG bytes 생성, Android Caysn SDK 와 Windows autoreplyprint.dll 양쪽 동일 PNG 입력.
- **로그 prefix**: `[ReceiptQueue]` / `[LabelQueue]` / `[PrinterQueue]` / `[Label]` 양 OS 동일.
- **UI 트리거 fire-and-forget**: 영수증/라벨 재출력 / 주문 취소 영수증 / 신규 주문 자동 출력 모두 큐 enqueue 만, 호출자 await 안 함 (양 OS 동일).

### OS 본질 분기되는 부분

| 항목 | Android | Windows |
|---|---|---|
| **외부 영수증 transport** | USB 범용 (`UsbManager` + `bulkTransfer`) | COM 시리얼 (`serial_port_win32`) |
| **외부 영수증 디바이스 enumerate** | `UsbManager` 통한 VID/PID + product name 패턴 | `SerialPort.getAvailablePorts()` |
| **외부 영수증 권한** | `ACTION_USB_PERMISSION` BroadcastReceiver + 시스템 다이얼로그 | 없음 (COM 포트 점유 충돌만 존재) |
| **외부 영수증 false-success 방지** | `verifyConnection` (ESC `@` probe) | `_probePrinter` (DLE EOT 1 ping → `cbInQue` 폴링 300ms) |
| **외부 영수증 endpoint 선택** | 3-tier endpoint (NXP CDC tier 0 → USB Printer class tier 1 → vendor specific tier 2 → bulk OUT tier 3) + 4-tier 후보 판정 (BLOCKLIST/STRICT/WHITELIST/RELAXED) | N/A — COM 포트 단일 destination |
| **외부 영수증 점유/lag 방어** | USB 권한 / 좀비 detach 미발생 안전망 (`reconnectExternalPrinter`) | `serial_port_win32` cache 잔재 + USB-Serial CDC re-enumerate lag + 외부 프로세스 점유 (close 후 enumerate polling, 3-way settle warm/cold/failure-cooldown, 8가지 사유 분류) |
| **외부 영수증 결과 차단 정책** | N/A | Winspool RAW 폴백 의도적 배제 (사용자 합의: OS default 프린터에 영수증 송출 사고 차단) |
| **라벨 transport** | Caysn AutoReplyPrint Java SDK (`autoreplyprint.aar`) | `autoreplyprint.dll` Dart FFI (`AutoReplyPrintBindings`) |
| **라벨 디바이스 open** | `LabelPrinter.printBitmap()` 안에서 SDK 가 enumerate + open 일임 | `CP_Port_EnumUsb` + `CP_Port_OpenUsb` (VID:PID 4종 화이트리스트, OS 디바이스 경로 `\\?\usb#...` 우선 정렬) |
| **라벨 ACK / 비콘 신호** | `statusCallback` (PrintedEvent + InfoStatus 통합) | `printerAddOnStatus` + `printerAddOnPrinted` 별개 등록, paperFetch 비콘이 주 신호 (ACK race 안전망) |
| **라벨 stuck 자동 복구** | 펌웨어가 비트 자동 해제 (active clear 불필요) | `printerClearError` + `printerClearBuffer` + `posResetPrinter` 3종 active clear (Windows Caysn 펌웨어 한계 대응, `noPaperCanceled` stuck 케이스) |
| **라벨 떼기(PAPERNOFETCH) 안전망** | 펌웨어가 자동 해제 | `portIsConnectionValid==0` 시 wait 종료 → 다음 호출에서 reconnect (status 비콘 stream 끊긴 USB 케이블/허브 이상 시그널) |
| **라벨 FFI block 회피** | N/A — MethodChannel 이 native 별도 thread (`receiptPrintExecutor`) 에서 처리 | `Isolate.run` boxing (`_enumerateUsbPortsAsync` / `_tryOpenUsbAsync`) — handle raw `address` 만 cross-isolate 로 받아 main isolate 의 instance state 갱신 |
| **deferred import** | N/A | `external_receipt_printer_windows.dart` 를 `deferred as win_transport` 로 import — Android 런타임이 `win32` / `serial_port_win32` 패키지의 native static initializer (`kernel32.dll` lookup) 를 트리거하지 않도록 격리 |

### 의도적으로 통합하지 않은 부분

- **`PrintBackend` 추상화 미도입**: 두 OS 의 디바이스 enumerate / 권한 / 콜백 모델이 본질적으로 달라 통합 시 가독성 ↓ + Android 회귀 위험 ↑. 의도적으로 transport 인터페이스 (`PrinterTransport`) 만 공통, 그 위층 (서비스 호출, 콜백 등록, FFI vs MethodChannel) 은 OS별 클래스 그대로 유지.
- **라벨 backend instance state 위치 (Windows)**: `WindowsLabelPrinterBackend` 는 main isolate 의 singleton — `_hPrinter` / 콜백 플래그 / status beacon 모두 main 에 보관. FFI 호출만 isolate 로 boxing 하고 instance state 는 main 에 두는 패턴 (handle address cross-isolate 로 marshal). 전체 backend 를 isolate 로 옮기면 instance state 동기화 / SDK 글로벌 콜백 라이프사이클이 복잡해져 회피.
- **로그/큐 prefix는 공통, 진단성 분류는 OS별**: `[ReceiptQueue]` / `[LabelQueue]` / `[PrinterQueue]` prefix 는 공통이지만, 실패 사유 분류는 OS 특성에 맞춤 — Windows 는 `_lastFailureReason` 8가지 (COM 환경 특유), Android 는 `PlatformException.code` (BUSY / NO_DEVICE / TRANSPORT_ERROR).

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

### 적용된 컴퓨티드 프로바이더 (`lib/providers/order/order_computed_providers.dart`)

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

## 브랜드 (식별·자산·테마·커스텀 기능)

브랜드는 **매장 ID prefix**(`TPCP`/`MHST`/`MATA`)로 식별되며, 3계층으로 다룹니다.

**Layer 1 — SSOT 레지스트리**: `lib/utils/brand_registry.dart`의 `BrandRegistry`가 단일 출처. prefix → `BrandMeta`(자산 폴더/영수증로고/테마/통화/서버환경/`features`)를 해석합니다. prefix 매칭 로직은 이곳에만 존재하며, `PreferenceService.isTPCPStoreId` 등 레거시 헬퍼와 `BrandAssets`(자산 경로)는 모두 레지스트리에 위임합니다.
- `BrandRegistry.resolveOrNull(id)` → 미매칭이면 **null** (capability·통화·환경 판단용 — "미지의 브랜드 = 기능 없음" 보장).
- `BrandRegistry.resolve(id)` → 미매칭이면 **fallback=tokyoplatz** (라벨/영수증 로고는 항상 필요하므로 자산 경로 전용).
- `currentBrandProvider`(`lib/providers/brand_provider.dart`)는 무상태로 매번 prefs를 읽어 `BrandMeta?`를 반환 → 로그아웃/서버전환 시 outdated 문제 없음.

**Layer 2 — Capability 게이팅**: `enum BrandFeature`(`labelCategoryFilter`, `soundGraphSend`, `japanEnvironment`, `autoUpdateForce`)로 UI show/hide·로직 enable/disable을 `brand.has(feature)`로 일관 처리. 산재된 `isTpcpStore`/`isMammothStore` 분기를 대체합니다.

**Layer 3 — 동작 seam**: 게이팅이 아니라 **동작이 갈리는** 소수 지점만 얇은 인터페이스로 분리(비대상 브랜드는 NoOp).
- 파이프라인 **변환** → `LabelFilterStrategy`(`lib/services/label_printer/label_filter_strategy.dart`). `labelFilterStrategyProvider`가 capability로 `TpcpLabelFilterStrategy`/`NoOpLabelFilterStrategy` 선택. `LabelPrintData.fromOrder(strategy: ...)`가 메뉴 필터/옵션 분류를 위임.
- 라이프사이클 **외부 통합** → `SoundGraphHook`(`lib/services/soundgraph_hook.dart`). `soundGraphHookProvider`가 capability로 `MhstSoundGraphHook`/`NoOpSoundGraphHook` 선택. `OrderProvider`의 자동접수 성공 후 `onAutoAccepted(order)` 호출. 비-MHST 매장은 NoOp → 크로스-브랜드 전송 누수 차단.

**테마**: `lib/constants/brand_theme.dart`의 `BrandTheme` enum이 색상·로그인 배경·로고를 정의(레지스트리의 `BrandMeta.theme`가 prefix→테마 매핑). `main()`에서 `AppStyles.applyBrand(savedBrand)`로 부팅 시 1회 고정하며 색상 교체는 **앱 재시작 후** 반영(런타임 즉시 변경 X).

**새 브랜드/기능 추가**: 브랜드는 `BrandRegistry._all`에 `BrandMeta` 한 항목(+ 자산·`BrandTheme`·pubspec) 추가가 핵심. 새 브랜드 전용 기능은 `BrandFeature` 추가 → 해당 브랜드 `features`에 등록 → (단순 게이팅이면) capability 체크, (동작이 다르면) Strategy/Hook 구현체 추가. 자산 절차는 [docs/BRAND_ASSETS.md](BRAND_ASSETS.md).

## 주요 패턴

- **모델**: `lib/models/`에 수동 작성된 클래스 (freezed 아님), 수동 `fromJson`/`toJson`. `OrderModel`이 핵심 데이터 객체.
- **Enum**: `lib/models/enums/` — `OrderStatus`, `OrderAction` 등.
- **Order Provider 분해**: `Order` 프로바이더(`order_provider.dart`)는 매니저 클래스(`OrderSocketManager`, `OrderTimerManager`, `OrderQueueManager`, `OrderCacheManager`, `OrderSettingsManager`, `OrderStateManager`)에 위임하여 메인 프로바이더를 가볍게 유지. `OrderSocketManager`는 `appfit_core` v1.0.8의 `SocketEventDispatcher` / `RecentRemovalsCache` / `OrderEventIgnorePolicy`로 위임하여 WebSocket 이벤트 라우팅과 자동접수 race / 상태 다운그레이드 방지를 일원화.
- **자동접수 출력 enqueue 순서 = 주문번호 정렬 순서 (직렬화 보장)**: `OrderQueueManager` 는 NEW 주문을 1초 버퍼링 후 `shopOrderNo` 로 정렬([`compareByShopOrderNo`](../lib/providers/order/order_queue_manager.dart) — 정렬 정책 single source of truth)하여 throttle(250/500ms) 로 한 건씩 `await` 방출한다. 자동접수 3경로(소켓 `_processNewOrder` / 폴링 `_processPollingNewOrders` / 새로고침 `_processNewOrdersWhenRefresh`)는 모두 **PUT(`updateOrderStatus`)→`_outputQueueService.add()` 를 `await` 로 직렬화**한다 — 폴링/새로고침은 루프 진입 전에 `OrderQueueManager.sortByShopOrderNo` 로 정렬. 따라서 `_receiptQueue` enqueue 호출 순서 = 정렬된 주문번호 순서가 보장된다. **이전 회귀**: 자동접수가 `Future.microtask(updateOrderStatus).then(add)` 로 분리돼 `add()` 가 per-order 네트워크 PUT 응답 도착 순서로 호출 → bulk 부하 시 인접 주문 주문서 인쇄 순서 역전(720-721-**723-725-724**-726). 큐(`SerialAsyncQueue`)는 엄격 FIFO 라 무결했고, enqueue **순서**가 비결정적인 것이 원인이었음. 주의: 이 직렬화는 [아래](#주요-패턴) "UI 트리거는 큐 enqueue 만 (fire-and-forget)" 과 별개 — 호출자는 여전히 출력 *완료* 를 await 하지 않으며, 자동접수 단계에서 `add()` *호출 시점* 만 정렬 순서로 묶는다.
- **캐싱**: `lib/core/orders/cache/` — 주문 상세, 출력 완료, 처리 완료, 액션 중복 방지를 위한 인메모리 캐시.
- **알림음/점멸/출력**: `lib/core/orders/` — `SoundService`, `BlinkService`, `OutputService`, `AlertManager`가 알림 부수 효과 처리.
- **라벨 프린터 플랫폼 분기**: `OutputService.printOrderLabels()` 에서 `Platform.isWindows` 로 갈라짐. Windows = `LabelPrintOrchestrator` -> `LabelPrinterService` (FFI), Android = `MethodChannel printLabel` -> `LabelPrinter.java`. `OutputQueueService` 직렬화 + 3-set in-flight 락 + Sentry `LabelPrintMissingException` 은 양 플랫폼 공통. 자세한 흐름은 [라벨 프린터 파이프라인](#라벨-프린터-파이프라인) 섹션.
- **UI 트리거는 큐 enqueue 만 (fire-and-forget)**: 영수증/라벨 재출력, 주문 취소 영수증, 신규 주문 자동 출력 등 사용자 가시적 트리거는 모두 `outputQueueServiceProvider.add*()` 호출 후 즉시 리턴. `PrinterJobQueue` 의 backoff(최대 137s) 와 `onFinalFailure` 콜백이 출력 결과/재시도 책임을 가지므로 호출자는 결과를 await 하면 안 됨. await 회귀 시 다이얼로그가 137s 까지 안 닫히는 사고. 설정 화면 "테스트 출력" 같이 결과 표시가 필요한 경우만 짧은 timeout(8s) + 시간 초과 시 백그라운드 진행 안내.
- **상세조회 실패 대응 + 출력 누락 자동 재발행 (복구 큐)**: 서버오류(5xx)·타임아웃·인터넷 순단으로 신규 주문 상세조회(`getOrder`)가 실패할 때의 다층 방어.
  1. **재시도** — `OrderSocketManager._fetchOrderDetailWithRetry` 가 transient(`isTransientError`: connection/receive/send timeout·connectionError·5xx)만 짧은 backoff(`[0, 0.5s, 1.5s]`, 3회)로 재시도, 4xx/취소/파싱은 즉시 실패. 호출자(소켓 상세조회) 한정 래퍼라 `getOrder` 전역/자동접수 PUT 흐름에는 영향 없음.
  2. **폴링 안전망** — 재시도 소진 시 catch(1차·fallback)는 `_processNewOrder` 를 **직접 호출하지 않고**(부분데이터 state 진입·dedup 우회 방지) `_reportDetailFetchFailureAndRecover` 로 `OrderDetailFetchFailedException`(전용 마커 예외 — Sentry 5분 쿨다운 키 분리) 보고 + `onRefreshOrders`(=`refreshOrders`) 즉시 트리거. 폴링이 `getNewOrders` 목록으로 주문을 복구해 state 진입. 폴링 catch·출력 큐 onError 도 `captureError` 로 가시화.
  3. **부분 데이터 차단** — 메뉴를 끝내 못 가져온 주문은 빈 영수증/라벨을 출력하지 않고 스킵(`OutputService` 영수증 분기 catch / `printOrderLabels` 의 `_prepareOrderForPrinting` throw·메뉴 생략). 프린터 하드웨어 출력 실패(`LabelPrintMissingException` 등)와는 별개 경로.
  4. **복구 큐** — 스킵된 주문을 `Order._pendingDetailReprint` Set 에 `markPendingReprint` 로 마킹했다가, `fetchOrderDetail` 의 **API 성공 분기**(캐시 히트 분기 제외)에서 메뉴 확보 시 `_outputQueueService.add(playSound:false)` 로 영수증+라벨을 **1회** 자동 재발행. 중복 출력 0 = `_pendingDetailReprint.remove()` 동기 원자성(첫 remove 만 true) + `_inFlightNewOrders` 가드 + `menus.isNotEmpty`(빈 메뉴 재발행 차단). stale 정리는 `cleanupOnLogout` 의 `_pendingDetailReprint.clear()` + `refreshOrders` 의 `retainWhere`. 개발 재현: 개발자 옵션 "상세조회 강제 실패"(`lib/dev/order_detail_fault_injector.dart`, `kDebugMode` 게이트로 release 무해).
- **라벨 backend FFI Isolate boxing**: Windows `WindowsLabelPrinterBackend` 의 `portEnumUsb` / `portOpenUsb` 같은 동기 SDK 호출은 USB 미연결 환경에서 main thread 를 수백ms~수초 block 한다. `_enumerateUsbPortsAsync` / `_tryOpenUsbAsync` 가 `Isolate.run` 으로 boxing 하고 handle 의 raw `address` 만 cross-isolate 로 받아 main isolate 의 instance state(`_hPrinter` / 콜백 플래그 / status beacon) 를 갱신. autoreplyprint SDK 가 cross-isolate handle 을 받아주는 점은 `_doPrintPng` 의 `posQueryPrintResult` Isolate.run 패턴이 운영에서 검증.
- **모니터링**: `OrderAgentMonitoringContext`가 `appfit_core`의 `MonitoringContext`를 구현하여 Sentry 초기화·오류 캡처·breadcrumb를 단일 진입점에서 처리. `MonitoringSyncProvider`가 사용자/스토어 변경 시 컨텍스트를 동기화.
- **순차 비동기 큐**: `lib/utils/serial_async_queue.dart`의 `SerialAsyncQueue<T>`로 USB 프린터·TTS 등 공유 자원 경쟁을 방지. `appfit_core`의 동일 클래스(v1.0.6 deprecated)에서 자체 구현으로 이전됨. `OutputQueueService`가 대표 사용처.
- **인증/세션 정리**: `Auth.logout()`(`lib/providers/auth_provider.dart`)이 credentials/JWT/SecureStorage(projectId·apiKey)/SharedPreferences/WebSocket을 정리하는 **단일 진입점**. UI 계층(예: `HomeScreen`)은 이 메서드만 호출하고 영업 상태 변경·`OrderProvider` cleanup·네비게이션을 담당. `disconnect()` 후 dependency가 outdated되므로 모든 `ref.read()`는 disconnect 호출 전에 미리 캐시. `unauthenticate()`는 환경 변경 시 WebSocket만 끊고 로그인 화면으로 복귀.
- **라우팅**: 세 개의 명명된 라우트: `/login`, `/home`, `/settings`.
