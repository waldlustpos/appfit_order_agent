# 출력/프린터 계층 (Printer & Output Flow)

영수증·라벨 출력 경로를 도식화한 문서다. 매장 환경의 일시적 장애(POS 점유, USB 재연결, 느린 부팅)를
**큐 + 지수 백오프**로 흡수하고, **플랫폼별 transport**(Windows COM / Android USB)와 **라벨 FFI**로 분기한다.
주문 흐름과의 접점은 [docs/ORDER_FLOW.md](ORDER_FLOW.md) §6 참고.

> 한 줄 요약: **빌드(ESC/POS) → ExternalReceiptPrinter → PrinterJobQueue(백오프 재시도) → Transport(COM/USB) → 결과 분기 → 최종 실패 콜백**.
> 단일 출력 디바이스에 대한 동시 접근을 큐로 직렬화하고, 결과를 4종으로 분류해 재시도/포기를 판정한다.

---

## 1. 출력 큐 & 지수 백오프

```mermaid
flowchart TD
    BUILD["ReceiptEscPosBuilder<br/>CP949 ESC/POS 바이트"]
    ENQ["PrinterJobQueue.enqueue(job)"]
    WORKER["단일 worker<br/>순차 처리"]
    SEND["transport.send(bytes, jobName)"]
    RESULT{"PrinterTransportResult"}
    OK["PrinterSuccess<br/>future 완료(true)"]
    RETRY["재시도 대기<br/>defaultBackoffs 적용"]
    FINAL["onFinalFailure(job, lastResult)<br/>운영 로깅·UI 피드백"]

    BUILD --> ENQ --> WORKER --> SEND --> RESULT
    RESULT -->|성공| OK
    RESULT -->|Busy / NoDevice / TransportError| RETRY
    RETRY -->|attempt < 7| WORKER
    RETRY -->|7회 소진| FINAL
```

**백오프 타임라인** ([printer_job_queue.dart](../lib/services/printer_job_queue.dart) `defaultBackoffs`)

| 시도 | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 대기 | 즉시 | 2s | 5s | 10s | 20s | 40s | 60s |

- 총 7회, 누적 약 137초. 인덱스 0은 첫 시도(즉시), 1~6이 실제 백오프.
- `PrinterFinalFailureCallback = void Function(PrinterJob job, PrinterTransportResult lastResult)` — 최대 시도 초과 시 호출.
- 테스트는 `backoffsForTest` setter로 지연을 단축.

---

## 2. Transport 플랫폼 분기

```mermaid
flowchart TD
    EXT["ExternalReceiptPrinter<br/>플랫폼-무관 진입점"]
    EXT -->|Windows: deferred import| WIN["ComPortPrintService"]
    EXT -->|Android| AND["AndroidUsbTransport"]

    WIN --> PROBE["DLE EOT 1 프로브<br/>_dleEot1 = 0x10 0x04 0x01"]
    PROBE --> SERIAL["serial_port_win32<br/>openWithSettings / writeBytes"]

    AND --> MC["MethodChannel<br/>printReceiptBytes"]
    MC --> USBJ["UsbReceiptPrinter.java<br/>bulkTransfer 8KB 청크"]
    USBJ --> WR{"WriteResult"}
    WR --> S["SUCCESS"]
    WR --> B["BUSY"]
    WR --> N["NO_DEVICE"]
    WR --> T["TRANSPORT_ERROR"]
```

**결과 4종** ([printer_transport.dart](../lib/services/printer_transport.dart))

| 타입 | 의미 | 재시도 |
| --- | --- | --- |
| `PrinterSuccess` | 출력 성공 | — |
| `PrinterBusy(reason)` | 디바이스 점유(POS 등) | O |
| `PrinterNoDevice(reason)` | 디바이스 없음/미연결 | O |
| `PrinterTransportError(reason)` | 전송 실패 | O |

- **Windows deferred import**: `serial_port_win32`의 정적 initializer가 Android 런타임에서 `kernel32.dll`을 찾으려다 크래시하는 것을 막기 위해 Windows transport를 지연 로드.
- **DLE EOT 1 프로브**: USB-Serial CDC 칩이 프린터 전원 OFF에도 bus power로 살아 있어 발생하는 false-positive("연결됨" 오판)를 차단. `_probeTimeout`(300ms), `_probeMaxAttempts`(5) 등으로 생존을 직접 확인 — 자세한 권위 판정은 메모리 `external_printer_liveness` 참조.
- **Android VID 화이트/블랙리스트**: Posbank(0x1552)·NXP(0x0D28) 허용, ASIX Ethernet(0x0B95) 제외. 청크 `CHUNK_SIZE` 8KB, 타임아웃 5000ms.

### 2.1 Windows 시리얼: 두 연결 형태 · 기본 보레이트 · serial_port_win32 함정

Windows COM 경로는 **두 가지 물리 연결을 동일 코드로 지원**한다 (2026-07 PR800 + NEXT-340PL COM6 실기 검증).

| 연결 형태 | 드라이버 | 특성 |
| --- | --- | --- |
| 프린터 내장 USB → USB-CDC 가상 COM (현장 표준) | usbser.sys 계열 | baud 무시, DSR/CTS 미전달(0x00), 무효 DCB도 관대하게 수용 |
| USB-RS232 어댑터(NEXT-340PL/PL2303 등) → 프린터 시리얼 포트 | ser2pl.sys 등 | DCB 검증 엄격, DSR/CTS 전달(0x30), 실제 wire 속도 존재(9600≈1KB/1.2s) |

**기본 보레이트 115200**: PR800 시리얼 포트 고정값(9600~57600은 DLE EOT 무응답, 115200만 0x16 응답). CDC는 baud를 무시하므로 전 연결타입 공통 기본값으로 안전. prefs 저장값이 항상 우선이며, 기본값 3지점은 함께 유지할 것 — `ComPortPrintService.defaultBaudRate` / `PreferenceService.getComPortBaudRate` / `ExternalPrinterSubSettings._defaultBaudRate`.

**serial_port_win32(1.4.2) 함정과 대응** (구현·근거 정본은 [com_port_print_service.dart](../lib/services/com_port_print_service.dart) 주석):

1. `openWithSettings`의 `StopBits`는 **DCB raw 값(0=1비트, 1=1.5비트, 2=2비트)**. 1을 넘기면 8데이터비트와 무효 조합이 되어 PL2303이 SetCommState에서 거부(open throw). CDC가 관대해 오래 잠복했던 버그 — 반드시 0 사용.
2. 패키지는 DCB를 zero-init 상태로 SetCommState 한다 → `_primeDcb`가 DCBlength/fBinary/Xon≠Xoff + DTR/RTS ENABLE을 선채움.
3. 패키지 open()이 CreateFile 후 SetCommState 등에서 throw 하면 **핸들을 누수**한다(이후 모든 재시도가 ACCESS_DENIED 락아웃). `_recoverLeakedHandle`이 openWithSettings throw 직후에만 회수 — 다른 시점 호출 금지(double-close 위험, 헬퍼 주석 참조).
4. `writeBytesFromUint8List`의 timeout은 시간이 아닌 **루프 반복 횟수**(unawaited delay 결함) → 실제 시리얼에서 write가 pending이기만 해도 false 반환. **write false ≠ 실패 확정** — probe는 RX 응답으로만 판정하고, 데이터 write 후 drain delay(전송시간+200ms)가 조기 close 잘림을 방지.
5. open 직후 `EscapeCommFunction(SETDTR/SETRTS)` assert — DTR/DSR 흐름제어 프린터가 host not-ready로 수신/응답을 보류하는 것을 방지.

**시리얼 무응답 트러블슈팅 순서**: ① COM enumerate 확인(케이블/드라이버) → ② open throw면 위 1·2(DCB) 의심 → ③ probe-timeout이면 보레이트 스윕(115200 우선) → 프린터 전원 → 배선(널모뎀) 순으로 분리. DLE EOT 1(`0x10 0x04 0x01`)의 정상 온라인 응답은 `0x16`.

---

## 3. 라벨 프린터

```mermaid
flowchart TD
    LBL["LabelPrintData<br/>BMP 비트맵 + QR 인코드"]
    LBL -->|Windows| WRT{"WindowsLabelRouter<br/>VID 스캔 (매 인쇄 재평가)"}
    LBL -->|Android| LMC["MethodChannel printLabel"]

    WRT -->|"BIXOLON 0x1504 연결됨 (우선)"| BWB["BixolonWindowsLabelBackend<br/>BXLLAPI_x64.dll FFI"]
    WRT -->|그 외| WB["WindowsLabelPrinterBackend<br/>autoreplyprint FFI"]
    WB --> FFI["autoreplyprint SDK (C DLL)"]
    FFI --> CB["NativeCallable 상태 콜백<br/>비콘 캐시 갱신"]
    CB --> QPR["QueryPrintResult<br/>타임아웃 1000ms"]
    BWB --> BMP["사전 이진화(210) → 임시 BMP<br/>PrintImageLibW + Prints"]
    BMP --> BST["CheckStatus 동기 폴링<br/>(진입 게이트 + 완료 폴링)"]

    LMC --> RT{"VID 라우팅<br/>(매 인쇄 재평가)"}
    RT -->|"BIXOLON 0x1504 연결됨 (우선)"| BXD["BixolonLabelDriver.java<br/>BIXOLON XD5-40d"]
    RT -->|그 외| LJ["LabelPrinter.java<br/>Caysn/REXOD 라벨 프린터"]
    LJ --> LCB["CP_OnPrinterStatusEvent 콜백<br/>volatile 비콘 캐시"]
    BXD --> BST["getStatus 동기 폴링<br/>(진입 게이트 + 완료 폴링)"]
```

- **Windows**: `WindowsLabelRouter`가 SetupAPI VID 스캔(win32, deferred import)으로 벤더를 매 인쇄 재평가 — BIXOLON(0x1504) 연결 시 `BixolonWindowsLabelBackend`(BXLLAPI_x64.dll FFI, 완전 동기·폴링 기반, PNG→사전 이진화 BMP 임시 파일→`PrintImageLibW`+`Prints`), 그 외 `WindowsLabelPrinterBackend`(AutoReplyPrint SDK FFI, Java 패턴 1:1 포팅, `NativeCallable.listener` 상태/완료 콜백, `QueryPrintResult` 타임아웃 1000ms, 라벨 모드는 포트 닫힐 때까지 유지). 두 백엔드 모두 Android 와 동일한 에러 의미론(복구대기·submit-wins) 공유.
- **Android**: MethodChannel `printLabel` → `NativeMethodHandler` 가 연결된 USB VID 로 벤더 분기 — BIXOLON(0x1504) 연결 시 `BixolonLabelDriver.java`(BIXOLON Label SDK, 동기 API), 그 외 `LabelPrinter.java`(Caysn autoreplyprint). 인자 `autoReplyMode`/`useFeedToTear`/`useBackToPrint`/`useCalibrate` 는 Caysn 전용(BIXOLON 경로 무시), `orderNo`/`labelIndex`/`totalLabels` 는 공통. 두 드라이버는 동일한 에러 의미론 공유: 용지없음/커버열림=무한 복구대기, 기타 에러=0.5s 게이트 후 false(Dart 재시도), 전송 완료 후는 submit-wins(중복 인쇄 방지).
- **QR 페이로드**: `qrPayloadStrategyProvider`가 브랜드별 전략 선택(현재 모두 `DefaultQrPayloadStrategy` = `{OrderNo}-{ShopItemId}-{CupIdx}`). 자세한 흐름은 [docs/BRAND_I18N_FLOW.md](BRAND_I18N_FLOW.md).
- FFI Isolate boxing·hot-reload 주의는 메모리 `ffi_isolate_boxing`, `hot_reload_cold_restart` 참조.

### 3.1 Android / Windows 동작 차이 전수 (통일 시 참조)

두 백엔드는 **에러 의미론과 결과 계약(3분류)은 같지만 명령 순서와 대기 시점이 다르다.**
"Windows 는 이 증상이 없다" 를 근거로 쓸 때 어느 차이가 작용했는지 구분하지 않으면 오판한다.

| # | 항목 | Android `LabelPrinter.java` | Windows `windows_label_printer_backend.dart` |
|---|---|---|---|
| ① | feedToTear 위치 | `PagePrint` → **`FeedPaperToTearPosition`** → `QueryPrintResult` (**ACK 대기 창 안**) | ACK 확정 → 떼기 대기 → **그 다음** `labelFeedLabel` (창 밖) |
| ② | 떼기 대기 시점 | `printed` 실패일 때만. 성공 시 **안 기다리고 반환** | 매 인쇄마다 반환 **전에** `_waitPaperFetched` |
| ③ | ACK 획득 방식 | `CP_Pos_QueryPrintResult` 동기 블로킹이 **주 경로** | printed 콜백 카운터 + 폴링이 주 경로, `QueryPrintResult` 는 fallback |
| ④ | `useCalibrate` | 매 라벨마다 `CP_Label_CalibrateLabel` | **의도적 무시** (매 라벨 호출 시 갭센서 정렬로 텀 급증 — 50장 부하 검증). 기본값 `false` 라 현재 실피해 없음 |
| ⑤ | 라벨 간 300ms | `index > 0 && Platform.isAndroid` (`output_service.dart`) | 없음 |
| — | 에러 게이트 / idle 게이트 / 결과 계약 | paper·cover 무한 대기, 그 외 500ms, idle 5000ms, 3분류 | **동일** ✓ |

**②가 운영자 체감 차이를 만든다 — Android 는 비프음이 울리고 Windows 는 안 울린다.**
Android 는 앞 라벨을 안 뗀 상태로 다음 `PagePrint` 를 펌웨어에 보내고, 펌웨어가 buzzer 를
울리며 보류한다(`INFO_PAPERNOFETCH` 를 진입 게이트에서 **의도적 제외**한 결과). Windows 는
현재 인쇄 호출 안에서 떼기까지 블로킹하므로 다음 `PagePrint` 가 애초에 펌웨어에 닿지 않는다.

2026-08-07 실기기(D2s_KDS_STGL + REXOD RXLA-561) 확인:

```
09:07:53.155 #2 [0005] 출력시작
09:07:53.593 #2 [0005] 떼기대기 (PAPERNOFETCH, buzzer 활성)   ← 앞 라벨 안 뗌
```

> **통일 방향 원칙 — Android 쪽으로 맞춘다.** ②를 *Windows 기준*으로 맞추면(= Android 에
> PAPERNOFETCH 선행 게이트 추가) **비프음이 조용히 사라진다.** 비프음은 버그가 아니라 점주
> 알림 기능이다. 불변식: **"떼지 않은 상태에서 다음 `PagePrint` 가 펌웨어에 도달한다."**
> ③은 통일하지 않는다 — D2s_KDS_STGL 에서 printed 콜백이 fire 0건이라(2026-05-04 부하 테스트)
> 기기 제약에서 온 정당한 divergence다. 계약(3분류)이 같으므로 상위 계층은 이미 동일하다.

---

## 4. PrintService 초기화·연결 점검

```mermaid
flowchart LR
    BOOT["앱 부트"]
    INIT["PrintService._initPrinterQueue()<br/>microtask"]
    INJECT["PrinterJobQueue.setTransport(...)<br/>플랫폼별 transport 주입"]
    REG["onFinalFailure 콜백 등록"]
    CHK["checkConnection(external, label)<br/>+ _probeBuiltinPrinter (Android)"]
    BOOT --> INIT --> INJECT --> REG --> CHK
```

- 앱 시작 시 transport를 큐에 주입하고 `onFinalFailure`를 등록해 최종 실패를 운영 로깅·UI로 노출.
- `checkConnection`이 외부/라벨/내장 프린터 상태를 갱신(`printerStatusProvider`, `builtinPrinterAvailableProvider`).

---

## 5. 핵심 파일 색인

| 파일 | 역할 |
| --- | --- |
| [printer_job_queue.dart](../lib/services/printer_job_queue.dart) | 출력 큐·지수 백오프(`defaultBackoffs`)·`onFinalFailure` |
| [printer_transport.dart](../lib/services/printer_transport.dart) | `PrinterTransportResult` 4종, `AndroidUsbTransport` |
| [external_receipt_printer.dart](../lib/services/external_receipt_printer.dart) | 플랫폼-무관 진입점, Windows deferred 로드 |
| [external_receipt_printer_windows.dart](../lib/services/external_receipt_printer_windows.dart) | Windows COM transport(deferred) |
| [com_port_print_service.dart](../lib/services/com_port_print_service.dart) | COM 포트·DLE EOT 1 프로브·`serial_port_win32` |
| [receipt_escpos_builder.dart](../lib/services/receipt_escpos_builder.dart) | CP949 ESC/POS 바이트 빌드 |
| [print_service.dart](../lib/services/print_service.dart) | transport 주입·연결 점검·MethodChannel 호스트 |
| [windows_label_router.dart](../lib/services/label_printer/windows/windows_label_router.dart) | 라벨 Windows 벤더 라우터 (VID 자동감지) |
| [windows_label_printer_backend.dart](../lib/services/label_printer/windows/windows_label_printer_backend.dart) | 라벨 Windows FFI 백엔드 (Caysn/REXOD) |
| [bixolon_windows_label_backend.dart](../lib/services/label_printer/windows/bixolon_windows_label_backend.dart) | 라벨 Windows FFI 백엔드 (BIXOLON XD5-40d) |
| [qr_payload_strategy.dart](../lib/services/label_printer/qr_payload_strategy.dart) | 라벨 QR 페이로드 브랜드 전략 |
| [UsbReceiptPrinter.java](../android/app/src/main/java/co/kr/waldlust/order/receive/util/print/UsbReceiptPrinter.java) | Android USB bulkTransfer·`WriteResult` |
| [LabelPrinter.java](../android/app/src/main/java/co/kr/waldlust/order/receive/util/print/LabelPrinter.java) | Android 라벨 프린터 (Caysn/REXOD) |
| [BixolonLabelDriver.java](../android/app/src/main/java/co/kr/waldlust/order/receive/util/print/BixolonLabelDriver.java) | Android 라벨 프린터 (BIXOLON XD5-40d) |
