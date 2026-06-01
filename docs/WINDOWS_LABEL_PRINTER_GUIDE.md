# Windows 라벨프린터 통합 가이드 (autoreplyprint.dll)

> Caysn `autoreplyprint.dll` (Win64) 을 호스트 애플리케이션에 통합할 때의 **언어-중립** 아키텍처 가이드. C / C++ / C# / Rust / Go / Dart-FFI 어느 호스트에서도 동일한 invariant 가 성립한다.
>
> 이 코드베이스(`appfit_order_agent`) 의 Dart FFI 참조 구현은 **부록 B** 에서 링크. 본문은 의사코드와 시퀀스로만 기술한다.

---

## 0. 범위

**포함**: DLL 로딩 / 함수 카탈로그 / 콜백 라이프사이클 / 라벨 1장 인쇄 10-step 파이프라인 / 포트 관리 / paper-state machine / 17 invariant.

**제외 (호출자 책임)**:

- 라벨 N장 분해 (주문 1건 → 메뉴별 라벨)
- 큐 직렬화 (여러 주문 동시 도착)
- 최종 실패 retry 정책 / 관찰성(Sentry 등)
- 라벨 캔버스 → PNG 렌더링
- 다른 OS / SDK (Android Caysn SDK 등)

본 백엔드가 호출자에 노출하는 인터페이스는 단 하나:

```
bool print_label(png_bytes, width, height, options, tag);
```

호출자는 PNG·치수·옵션·디버그 태그만 전달하면 된다.

---

## 1. 전제 조건

| 항목      | 값                                                                       |
|---------|-------------------------------------------------------------------------|
| SDK     | Caysn `autoreplyprint.dll` (Win64, ~1.7 MB)                             |
| 검증 디바이스 | VID:0x0FE6,PID:0x811E  # 운영 모델 REXOD RXLA-561 우선 | Caysn D2 / D3 계열 (USB) | 
| ABI     | ANSI C, `__cdecl` / `__stdcall`, 모든 핸들은 불투명 `void*`                     |
| 호스트 언어  | 무관 — DLL 을 dynamically load 할 수 있으면 됨                                   |
| 런타임     | Visual C++ runtime (vcruntime140 / vcruntime140_1 / msvcp140)           |

벤더 트리:

```
external/autoreplyprint/win64/
├── autoreplyprint.dll
├── autoreplyprint.h          # 함수 시그니처 + 비트마스크 매크로
└── autoreplyprint.lib        # 정적 링크용 (FFI/LoadLibrary 시 불필요)
```

**DLL 배치**: 실행 파일(`.exe`) 옆에 `autoreplyprint.dll` 을 둔다. `LoadLibrary("autoreplyprint.dll")` 가 실행 파일 디렉토리를 탐색 경로에 포함하므로 별도 PATH 조정 불필요. 인스톨러(Inno Setup 등) 는 실행 파일 디렉토리를 재귀 복사하면 자동 포함.

---

## 2. SDK 함수 카탈로그

> 헤더 70+ 함수 중 라벨 인쇄에 실제 사용되는 **22 개** 만.

| 그룹 | 함수 | 시그니처 요약 |
|---|---|---|
| Library | `CP_Library_Version` | `() -> const char*` 디버그용 |
| Port | `CP_Port_EnumUsb` | `(buf, size, needed) -> u32` 디바이스 이름 double-null 리스트 |
| Port | `CP_Port_OpenUsb` | `(name, autoReplyMode) -> void*` |
| Port | `CP_Port_Close` | `(handle) -> int` |
| Port | `CP_Port_IsOpened` | `(handle) -> int` |
| Port | `CP_Port_IsConnectionValid` | `(handle) -> int` ← stale 검사용 |
| Label | `CP_Label_EnableLabelMode` | `(handle) -> int` ← 포트당 1회 |
| Label | `CP_Label_DisableLabelMode` | dispose 시 |
| Label | `CP_Label_CalibrateLabel` | 종이 교체 시 **1회만** |
| Label | `CP_Label_FeedLabel` | tear bar 노출 (옵션) |
| Label | `CP_Label_PageBegin` | `(handle, x, y, w, h, rotation)` |
| Label | `CP_Label_PagePrint` | `(handle, copies)` |
| Label | `CP_Label_DrawImageFromData` | PNG/JPG 바이트 직접 (디코드·이진화 SDK 위임) |
| Pos | `CP_Pos_ResetPrinter` | 이전 페이지 잔여 상태 정리 |
| Pos | `CP_Pos_QueryPrintResult` | `(handle, timeoutMs) -> int` ← fallback ACK |
| Printer | `CP_Printer_GetPrinterStatusInfo` | `(handle, errOut, infoOut, tsOut)` |
| Printer | `CP_Printer_ClearPrinterBuffer` | active clear 3종 |
| Printer | `CP_Printer_ClearPrinterError` | active clear 3종 |
| Printer | `CP_Printer_AddOnPrinterStatusEvent` | 상태 콜백 등록 |
| Printer | `CP_Printer_AddOnPrinterPrintedEvent` | ACK 콜백 등록 |
| Printer | `CP_Printer_RemoveOnPrinter*Event` | dispose 시 |

> **`CP_Library_*` / `CP_Port_*` / `CP_Label_*` / `CP_Pos_*` / `CP_Printer_*`** 그룹별 prefix 가 일관되므로 자동 룩업 코드 작성이 쉽다.

---

## 3. 콜백 시그니처 2종

```c
// Status: 현재 상태 비트(errStatus / infoStatus) 가 변할 때마다 호출
void on_printer_status(void* handle, int64 errStatus, int64 infoStatus, void* ctx);

// Printed: PagePrint 가 펌웨어에서 완료될 때마다 +1 카운트
void on_printer_printed(void* handle, uint32 printedPageId, void* ctx);
```

- 콜백은 SDK 내부 스레드에서 발화한다. 호스트 언어의 callback bridge(예: `NativeCallable.listener`, `[UnmanagedFunctionPointer]`, `extern "C" fn`) 를 사용하되 **콜백 본체에서 SDK 함수를 재호출하지 말 것** — 일부 펌웨어 빌드에서 재진입 데드락.
- 콜백은 포트와 무관한 SDK 글로벌. 다만 포트를 재오픈할 때는 안전망으로 재등록 flag 만 reset.

---

## 4. 백엔드 상태 모델

라벨 백엔드(싱글톤) 내부 상태:

| 변수 | 의미 |
|---|---|
| `handle` | 현재 USB 포트 핸들 (`void*`, null 이면 미오픈) |
| `currentAutoReplyMode` | 직전 오픈 시 사용한 autoReplyMode (변경 감지) |
| `statusCallbackRegistered` / `printedCallbackRegistered` | 등록 flag — 포트 재오픈 시 reset |
| `labelModeEnabled` | `EnableLabelMode` 호출 여부 — 포트당 1회만 |
| `printedAckCount` | printed 콜백 누적 카운트 (PagePrint 직전 snapshot) |
| `inflight` | 동시 호출 직렬화용 future/promise |
| 8 비콘 캐시 | statusCallback 이 갱신 (다음 §) |

**8 비콘 캐시** (statusCallback 이 매 호출마다 갱신):

```
errorBits        = errStatus  (raw 17 bit 집합)
errorOccurred    = errStatus != 0
errorNoPaper     = errStatus & 0x04
errorCoverUp     = errStatus & 0x80
infoRecvIdle     = infoStatus & 0x80
infoPrintIdle    = infoStatus & 0x40
infoNoPaperCancel= infoStatus & 0x10
infoPaperNoFetch = infoStatus & 0x20   ← "라벨 출력 완료, 사용자가 떼기 대기" — 가장 자주 사용
```

> `paperNoFetch` 비트는 PagePrint 의 펌웨어-측 ACK 대체 신호로도 쓰인다. ACK 콜백이 펌웨어에 따라 미발화일 수 있어 **둘 다 감시** 가 invariant.

비트마스크 매크로는 SDK 헤더 `CP_PRINTERSTATUS_ERROR_*` / `CP_PRINTERSTATUS_INFO_*` 에 정의. 호스트 측에서 동일하게 미러링하여 사용.

---

## 5. 10-step 인쇄 파이프라인

`print_label()` 한 번 호출 = 라벨 1장. 의사코드:

```
print_label(png, w, h, opts, tag):
    serialize against inflight       # 동시 호출 직렬화
    currentTag = tag                 # 비콘 로그 prefix

    step1  ensurePortOpen()                          # §6
    step2  registerCallbacks(if not yet)             # 두 콜백 모두
    step2A waitErrorGate(tag)        → false ⇒ return false
    step2B waitIdleGate(maxMs=5000)
    step3  (skip CalibrateLabel — 종이 교체 시점에만 외부 호출)
    step4  if !labelModeEnabled: EnableLabelMode; labelModeEnabled = true
    step5  CP_Pos_ResetPrinter(handle)
    step6  rc = CP_Label_PageBegin(handle, 0,0, w, h, ROT_0)
           if rc == 0: return false
    step7  rc = CP_Label_DrawImageFromData(handle, 0,0, w,h,
                  png, len, BINARIZE_THRESHOLD, COMPRESS_NONE)
           if rc == 0: return false

    ackBefore = printedAckCount                      # ★ snapshot 필수
    step8  rc = CP_Label_PagePrint(handle, copies=1)
           if rc == 0: return false

    step9  poll up to 1700ms (interval 30ms):
              if printedAckCount > ackBefore:       break (success)
              if infoPaperNoFetch:                  break (success)
              if infoNoPaperCancel:                 return false
           if !ackArrived && !infoPaperNoFetch:
              # fallback — 별도 스레드/isolate 에서 호출 권장
              rc = CP_Pos_QueryPrintResult(handle, timeout=1000)
              if rc == 0 && still no signal: return false
           if infoPaperNoFetch:
              waitPaperFetched(tag)                  # §8.4 무한 대기

    step10 if opts.useFeedToTear: CP_Label_FeedLabel(handle)

    # post-step: 추가 sleep 절대 금지 (invariant 10)
    return true
```

**상수표** (이 코드베이스 기준 — 펌웨어/디바이스 바뀌면 재튜닝):

| 상수 | 값 | 의미 |
|---|---|---|
| `fastPollTimeoutMs` | 1700 | step9 ACK/비콘 1차 폴링 |
| `fastPollIntervalMs` | 30 | step9 폴링 간격 |
| `queryPrintResultTimeoutMs` | 1000 | step9 fallback `QueryPrintResult` |
| `idleGateMaxMs` | 5000 | step2B idle 게이트 |
| `idleStepMs` | 30 | idle 폴링 간격 |
| `errorQuickGateMs` | 500 | 그 외 ERROR 짧은 게이트 |
| `paperWaitStepMs` | 100 | paper/cover/canceled 폴링 간격 |

---

## 6. 포트 관리

### 6.1 `EnumUsb` 결과 정렬

반환 이름은 두 형식이 섞여 나온다:

- OS 디바이스 인스턴스 경로: `\\?\usb#vid_4b43&pid_3538#...`
- 짧은 형식: `VID:0x4B43,PID:0x3538`

> **invariant**: OS 경로 형식을 먼저 시도. 짧은 형식은 enumerate 결과로 노출되지만 `OpenUsb` 가 거부하는 환경 존재.

### 6.2 빈 결과 fallback

첫 호출이 lazy 라 비어 나올 수 있다 — 200 ms 대기 후 한 번 더 시도.

### 6.3 VID / PID 화이트리스트

enumerate 결과가 비어도 알려진 디바이스 4종을 시도:

```
VID:0x4B43,PID:0x3538       # Caysn D2 계열
VID:0x4B43,PID:0x3830       # Caysn D3 계열
VID:0x0FE6,PID:0x811E       # 운영 모델 REXOD RXLA-561
VID:0x067B,PID:0x2303
```

새 디바이스 모델 추가 시 이 목록에 VID/PID 추가.

### 6.4 stale handle 검사

USB 분리/재삽입 후 `IsOpened` 가 여전히 1 인데 핸들이 죽어 있을 수 있다.

```
portInvalid = handle == null
           OR IsOpened(handle)           == 0
           OR IsConnectionValid(handle)  == 0      # ← OR 조건 필수
```

### 6.5 `OpenUsb(NULL, ...)` 절대 금지

NULL name 호출 시 access violation. 명시적 디바이스 이름 필수.

### 6.6 `warmupOpen`

앱 초기화 단계에서 USB enumerate + OpenUsb 를 미리 수행. 누락 시 첫 라벨 진입에서 USB enumerate 가 발생해 첫 라벨이 1.5~2 초 늦게 나온다. 실패해도 throw 하지 말고 false 반환 — 앱 시작을 차단하지 않기 위함.

### 6.7 블로킹 격리 (호스트 언어 권장 사항)

`EnumUsb` / `OpenUsb` 는 USB 미연결 환경에서 수십~수백 ms 블로킹할 수 있다. UI 가 있는 호스트(데스크톱 앱) 라면 별도 스레드/isolate 에서 호출하고 핸들 raw address 만 main 으로 가져오는 패턴을 권장. step9 fallback `QueryPrintResult` 도 동일.

---

## 7. 콜백 라이프사이클

1. **등록 (포트 오픈 후 1회)** — `AddOnPrinterStatusEvent` / `AddOnPrinterPrintedEvent`. 호스트 언어의 native callback bridge 로 함수 포인터 생성 후 등록.
2. **statusCallback 본체** — 8 비콘 캐시 갱신. 추가로 **연속 동일 errorBits 는 dedup 로깅** (디스크 로그 폭주 방지). 정상→ERROR / ERROR→정상 전환만 기록.
3. **printedCallback 본체** — `printedAckCount += 1`. 다른 일 금지.
4. **포트 재오픈 시** — `statusCallbackRegistered` / `printedCallbackRegistered` / `labelModeEnabled` 모두 reset 후 새 핸들에 재진입.
5. **dispose 시** — `RemoveOnPrinter*Event` → native callback bridge close → `DisableLabelMode` → `Port_Close`. 누락 시 콜백 함수 포인터 누수 + USB 핸들 잔존.

---

## 8. paper-state machine

상태 머신은 3 개 wait 함수로 구현된다.

### 8.1 ERROR 게이트 (3 분기)

```
waitErrorGate(tag):
    if !errorOccurred: return true

    # 분기 1: paper-out / cover-up / noPaperCanceled → 무한 대기
    if errorNoPaper or errorCoverUp or infoNoPaperCancel:
        loop every 100ms:
            track sawUserAction = entry 시점 비트와 차이 발생 여부
            run active clear if stuck (§8.3)
            exit when 모든 비트 해제
        return true

    # 분기 2: 그 외 ERROR (engine / voltage / cutter / overheat 등)
    sleep 500ms
    return false        # 호출자 retry 위임
```

> **invariant 7**: 두 분기를 합치지 말 것. 모두 무한 = 진짜 H/W 에러 시 큐 영구 정체. 모두 짧게 = 운영자 cover 닫기 전 retry 폭주.

### 8.2 idle 게이트 (분기 3)

```
waitIdleGate(maxMs=5000):
    while !(infoRecvIdle && infoPrintIdle && !infoNoPaperCancel):
        if elapsed >= maxMs: break       # 비콘 미수신 환경 통과
        sleep 30ms
```

피크타임 race 완화.

### 8.3 active clear (Windows 전용)

cover / noPaper 모두 해제됐는데 `noPaperCanceled` 만 stuck 인 케이스 — Windows Caysn 펌웨어가 자동 해제 안 함.

```
if !clearTried && sawUserAction && !errorCoverUp && !errorNoPaper && elapsed >= 200ms:
    CP_Printer_ClearPrinterError(handle)      # 3종 모두
    CP_Printer_ClearPrinterBuffer(handle)
    CP_Pos_ResetPrinter(handle)
    clearTried = true
    clearTime  = elapsed

if clearTried && elapsed - clearTime >= 1500ms:
    break                                      # 펌웨어 비트 stuck 안전망
```

> **invariant 15·16**: 3종 모두 호출 + 1회만 + 1500 ms timeout. 셋 중 하나라도 빠지면 큐 영구 정체.

### 8.4 PAPERNOFETCH wait (떼기 무한 대기)

```
waitPaperFetched(tag):
    while infoPaperNoFetch:
        if IsConnectionValid(handle) == 0: return    # USB stale 안전망
        sleep 100ms
```

> **invariant 12·17**: polling 자체에 timeout 없음 — 펌웨어가 큐 보관해 라벨 누락 0 보장. 단 USB stale 종료 분기로 status stream 끊긴 경우 wait 탈출.

---

## 9. 17 invariant 카탈로그

| # | invariant | 위반 시 사고 |
|---|---|---|
| 1 | `autoReplyMode=1` + PrintedEvent 콜백 둘 다 등록 | `QueryPrintResult` timeout → retry → N장 인쇄 |
| 2 | 인쇄 완료 신호 우선순위: paperFetch 비콘 > ACK 콜백 (**둘 다** 감시) | 펌웨어에 따라 ACK 미발화 — 한쪽만 보면 timeout |
| 3 | PagePrint 직전 `ackBefore = printedAckCount` snapshot | set 됐는데도 retry → 2장 인쇄 |
| 4 | 떼기 감지 후 두 번째 `QueryPrintResult` 호출 금지 (폴링 timeout 후 fallback 1회만 허용) | race-prone false → retry → 2장 인쇄 |
| 5 | `EnumUsb` 결과: OS 경로(`\\?\usb#...`) 우선, `VID:PID` 짧은 형식 후순위 | 첫 시도 실패 → 1.5 s retry → 첫 라벨 1.5초 지연 |
| 6 | `Port_OpenUsb(NULL, ...)` 절대 금지 | access violation |
| 7 | ERROR 게이트 두 분기 금지 합침 (paper/cover = 무한, 그 외 = 0.5초 후 false) | 큐 영구 정체 / retry 폭주 |
| 8 | `EnableLabelMode` 포트당 1회만 (`labelModeEnabled` flag 가드) | 50장 부하 시 모드 전환 명령 50회 누적 텀 |
| 9 | `CalibrateLabel` 매 라벨 호출 금지 (종이 교체 시 1회) | 매 라벨 갭 센서 정렬 → 라벨 사이 텀 큰 증가 |
| 10 | PagePrint 후 추가 sleep 금지 | 50장 × 100 ms = 5초 누적 텀 |
| 11 | `ensurePortOpen` 검사: `IsOpened==0` OR `IsConnectionValid==0` 둘 다 OR | stale handle 자동 reconnect 안 됨 |
| 12 | `paperNoFetch` / ERROR 게이트 polling step = 100 ms | 200 ms 시 떼기 감지 지연 누적 |
| 13 | SDK 호출 자체는 zero overhead (step5/6/8/10 ≈ 0 ms, step7 1.17 MB PNG ≈ 78 ms) | 95% 펌웨어 + 사용자 요인 — 마이크로 최적화 함정 |
| 14 | 커버열림(`errStatus & 0x80`) = paper-out 등가 무한 대기 분기 | 짧은 게이트 시 운영자 닫기 전 false → 라벨 누락 |
| 15 | `noPaperCanceled` stuck 시 active clear 3종 모두 + `clearTried` 1회만 | 일부만 호출 → 비트 미해제 → 큐 영구 정체 |
| 16 | active clear 후 1500 ms timeout 강제 break | 펌웨어 비트 stuck 시 큐 영구 정체 |
| 17 | `paperNoFetch` wait 중 `IsConnectionValid==0` 종료 분기 | 죽은 status stream 에서 비트 영구 1 → 무한 대기 |

> **검증 환경**: Caysn D2 / D3 + autoreplyprint.dll ~1.7 MB. 다른 펌웨어 / 디바이스로 옮기면 §11 검증 체크리스트 필수 재실행. 특히 #2 (paperFetch 우선), #15-17 (active clear / stale) 은 펌웨어별 동작 차이가 가장 크다.

---

## 10. 트러블슈팅 시나리오

### Win-A: 첫 라벨 1.5초 지연

`EnumUsb` 정렬(invariant 5) → `warmupOpen` 호출 여부 → 직전 dispose / USB 분리 이벤트 순으로 검사.

### Win-B: 동일 라벨 2장 인쇄

1순위는 `ackBefore` snapshot 회귀 (#3). 다음 fallback `QueryPrintResult` 의 false-success, 호출자 retry 로그, `autoReplyMode=1` 여부.

### Win-C: native crash

`OpenUsb(NULL, ...)` 잔존(#6) → DLL 누락 / 로드 실패 후 null-deref → stale handle (#11) → crash dump PDB 매칭.

### Win-D: 50장 부하에서 텀 누적

`EnableLabelMode` 1회만 호출되는지(#8) → PagePrint 후 sleep 잔존 여부(#10) → `CalibrateLabel` 매 라벨 호출 여부(#9) → step9 fallback 발화율 (정상치 0 회).

### Win-E: USB 분리/재삽입 후 라벨 누락

`IsConnectionValid==0` OR 조건(#11) → 콜백 재등록 → 호출자 큐의 in-flight set 정리 흐름.

### Win-F: 커버열림 후 큐 정체

무한 대기 분기 진입 로그 → `sawUserAction` 감지 → `noPaperCanceled` stuck → active clear 3종(#15) 로그 → 1500 ms timeout break(#16) → PAPERNOFETCH USB stale(#17).

---

## 11. 검증 체크리스트

이식 직후 다음 순서로 실행한다. 각 항목은 새 환경(다른 펌웨어/디바이스)에서 invariant 가 그대로 유효한지 확인하는 골든 패스.

### 빌드 산출물
- [ ] `<runner>/autoreplyprint.dll` 존재
- [ ] 인스톨러 출력에 DLL 포함

### 라이브러리 로딩
- [ ] `LoadLibrary` 성공 + `CP_Library_Version` 반환값 정상

### 포트 오픈
- [ ] `EnumUsb` 결과 1개 이상
- [ ] `포트 오픈 성공: <name>` 로그
- [ ] status / printed 콜백 등록 rc ≠ 0

### 라벨 1장 — step 시퀀스 로그
- [ ] step1 → step5 → step6 → step7 → step8 → `step9 poll done: ack=true` → step10 순
- [ ] step7 ≤ ~150 ms (1.17 MB PNG ~78 ms 정상)

### 5장 부하
- [ ] 라벨 사이 텀 < 200 ms
- [ ] step9 fallback `QueryPrintResult` 발화 없음

### 50장 부하 (invariant 8·10 검증)
- [ ] `EnableLabelMode (first-time)` 로그 1회만
- [ ] PagePrint 후 추가 sleep 로그 없음

### 커버 열고 닫기 (invariant 15 검증)
- [ ] `종이없음/커버열림 — 무한 대기 진입` 발화
- [ ] 닫힘 후 `stuck 감지 ... -> ClearError + ClearBuffer + ResetPrinter` 발화
- [ ] 이후 PagePrint 정상 진행

### USB 케이블 분리/재삽입 (invariant 11 검증)
- [ ] 다음 호출에서 `ensurePortOpen → 포트 오픈 성공` 로그
- [ ] 새 핸들로 콜백 재등록

---

## 부록 A. 호출자(상위 계층) 의무

본 백엔드는 **라벨 1장 인쇄** 만 책임진다.

- **N장 분해**: 호출자가 메뉴별/수량별 N회 호출. `print_label()` 가 false 반환하면 1.5 초 retry 1회 권장.
- **큐 직렬화**: 백엔드 내부 `inflight` 는 동시 호출 race 만 막는다. 비즈니스 큐(주문 단위 그룹, 여러 출력 소스 병렬 등) 는 별도 디스패처가 필요. 영수증/라벨이 별도 디바이스라면 **이중 큐 + 병렬 enqueue + fire-and-forget** 으로 한쪽 backoff 가 다른 쪽을 막지 않게 분리.
- **관찰성**: 최종 실패 시 Sentry 등에 송신. 라벨 누락은 사용자 즉시 인지가 어려운 사고이므로 production observability 가 사실상 필수.
- **logout / 종료**: 큐 정리 → `dispose()` 호출 의무. 누락 시 콜백 포인터 누수 + USB 핸들 잔존.

---

## 부록 B. 이 코드베이스의 Dart FFI 참조 구현

이 가이드의 의사코드를 Flutter Windows 데스크톱에 매핑한 실구현은 다음 파일에 있다. 다른 호스트 언어로 이식할 때 시그니처·순서·상수 비교용으로만 참고.

| 파일 | 역할 |
|---|---|
| [`lib/services/label_printer/windows/autoreplyprint_bindings.dart`](../lib/services/label_printer/windows/autoreplyprint_bindings.dart) | C ABI → Dart typedef 2단(`Native` / `Dart-facing`), 함수 룩업, 안전 로딩(`tryGet()`) |
| [`lib/services/label_printer/windows/autoreplyprint_constants.dart`](../lib/services/label_printer/windows/autoreplyprint_constants.dart) | 비트마스크 / enum 미러링 |
| [`lib/services/label_printer/windows/windows_label_printer_backend.dart`](../lib/services/label_printer/windows/windows_label_printer_backend.dart) | 10-step 파이프라인, paper-state, active clear, 콜백 lifecycle |
| [`windows/runner/CMakeLists.txt`](../windows/runner/CMakeLists.txt) | DLL POST_BUILD copy + install 디렉티브 |
| [`.claude/agents/label-printer-inspector.md`](../.claude/agents/label-printer-inspector.md) | 진단용 agent — invariant + 트러블슈팅 |

### Dart 한정 메모

- 콜백 등록: `NativeCallable<...>.listener` — main isolate 에 디스패치되어 race 부담 감소. dispose 시 `.close()` 의무.
- 블로킹 격리: `Isolate.run` 으로 `EnumUsb` / `OpenUsb` / `QueryPrintResult` 를 boxing. 핸들은 raw address(`int`) 로 cross-isolate 반환 후 `Pointer<Void>.fromAddress` 로 재구성.
- 안전 로딩: `DynamicLibrary.open` 실패 시 throw 대신 `tryGet()` 가 null 반환 — 라벨 기능을 비활성화하되 앱 진행은 계속.

### 변경 이력 (참고)

- `b38eefe` — 초판 (FFI 통합 + 17 invariant 정착)
- `3f819d9` — active clear 3종 + 1500 ms timeout (#15·16 정착)
- `2b68380` — 외부 큐 이중화·fire-and-forget·FFI Isolate boxing
- (현재) — 본 가이드를 언어-중립 형식으로 리라이트

---

## 부록 C. 이 코드베이스의 라벨 PNG 레이아웃

본 백엔드의 `print_label()` 가 받는 PNG 는 호출자가 캔버스에 그려서 만든다. 이 코드베이스에서 실제 사용 중인 레이아웃은 다음과 같다. 다른 디자인을 쓰려면 §0 "PNG 렌더링은 호출자 책임" 원칙대로 호출자만 교체하면 되고, 백엔드는 PNG 바이트와 width/height 만 받는다.

### C.1 캔버스 사양

| 항목 | 값 |
|---|---|
| 캔버스 | 490 × 600 px (PNG, 흰 배경) |
| 좌우 margin | 60 px |
| 폰트 | Pretendard (한국어 / Latin 통일) |
| 출력 매핑 | autoreplyprint SDK 가 PNG 디코드 + thresholding 이진화 후 펌웨어 전송 (≈ 1.17 MB → ~78 ms) |
| 글로벌 보정 | `offsetX=0, offsetY=-30` — 우측 쏠림 / 상단 여백 조정 |
| 로고 | `BrandAssets.labelLogoPath` 우선 → 실패 시 `labelLogoFallbackPath` (tokyoplatz). 한 번 로드 후 캐시 |

### C.2 4 영역 구조

위에서 아래로 4개 영역이 수평 구분선으로 분리된다.

```
┌──────────────────────────────────────────────┐
│ 14:32     ┌─LOGO─┐               1/3         │  Header
│ 03/14     └──────┘                            │
│ ──────────────────────────────────────────── │
│                    Regular / HOT / Standard  │  Body — SubInfo
│                                  카페라떼     │       메뉴명 (28pt bold, 우)
│  ▓▓▓▓                                         │
│  ▓ QR▓                              #0247    │       QR(좌) / 주문번호(우 85pt)
│  ▓▓▓▓                                         │
│ ──────────────────────────────────────────── │
│                     option                    │  Options
│  · 샷 추가           · 시럽 빼고               │       2열 × 최대 6개
│  · 휘핑 추가         · 얼음 적게               │
│ ──────────────────────────────────────────── │
│         detail              ▓▓▓▓             │  Detail
│  창가 자리에                  ▓ QR▓           │       메모(좌) / QR(우, 옵션)
│  부탁드립니다                 ▓▓▓▓            │
└──────────────────────────────────────────────┘
```

| 영역 | 좌측 | 중앙 | 우측 |
|---|---|---|---|
| **Header** | 주문시간 (16 pt, 2 줄, max 120 px) | 로고 (50 × 50, 캐시) | `N/M` 라벨 인덱스 (22 pt bold) |
| **Body** | QR (90 × 90, errorCorrection=L) | — | SubInfo 한 줄(22 pt, " / " 구분) + 메뉴명(28 pt bold) + 주문번호 `#NNNN`(85 pt bold) |
| **Options** | — | "option" 타이틀(22 pt bold) + 2열 그리드(21 pt, 최대 6개, 초과분 잘림) | — |
| **Detail** | 메모(22 pt, max 2 줄) | "detail" 타이틀(22 pt bold) | 보조 QR (75 × 75, `showDetailQr` 옵션) |

### C.3 입력 필드

`generateLabelImage()` 가 받는 필드(모두 nullable, 비어있으면 해당 영역 생략):

| 필드 | 용도 |
|---|---|
| `menuName` | 메뉴명 (Body 메인) |
| `options` | 옵션 리스트 — 2열 그리드, 7번째부터 무시 |
| `shopOrderNo` | 주문번호 — `#` prefix + 85 pt bold |
| `orderTime` | 주문시각 — Header 좌측 |
| `beanType` / `temperature` / `sizeOption` | SubInfo 한 줄 — 비어있는 항목은 자동 생략 + 구분자 재배치 |
| `qrData` | QR 데이터 — Body 좌측 QR + (`showDetailQr=true` 시) Detail 우측 QR |
| `memo` | 주문 메모 — Detail 좌측, 2 줄 ellipsis |
| `orderIndex` / `orderTotal` | `1/3` 형식 라벨 인덱스 |
| `showDetailQr` | Detail 영역 QR 표시 여부 |

### C.4 레이아웃 invariant (라벨-측)

- **세로 흐름은 누적 Y** 로 계산 (`_drawHeader` → `_drawBody` → `_drawOptions` → `_drawDetail` 가 다음 영역 Y 반환). 영역 추가/삭제 시 반환 Y 누락 주의.
- **로고 없을 때도 Header divider Y 는 동일** (`logoWidthDefault=50`) — 로고 유무로 본문이 위아래로 흔들리지 않게 고정.
- **Options 7번째부터 잘림** (`if (i >= 6) break`) — 7개 이상 옵션은 사용 케이스 없음. 필요 시 행 수 산정 로직(`row = i / 2`) 과 Detail 영역 시작 Y 연동 필요.
- **SubInfo 는 우측에서 좌측으로 그림** — `_drawSubInfoPart` 가 `rightX - painter.width` 로 자체 우측 정렬. 추가 항목 끼우려면 `_drawSubInfo` 의 `items` 리스트만 수정.
- **QR errorCorrection=L** — 음식점 라벨은 빠른 인쇄·작은 사이즈 우선. 매장 환경에서 L 로 충분 검증.

### C.5 참고 파일

- [`lib/utils/label_painter.dart`](../lib/utils/label_painter.dart) — 캔버스 페인터 + `generateLabelImage()` PNG 생성 진입점
- [`lib/services/label_printer/label_print_orchestrator.dart`](../lib/services/label_printer/label_print_orchestrator.dart) — 주문 1건 → 라벨 N장 분해 + 위 painter 호출 → 백엔드 `print_label()` 전달
- [`lib/utils/brand_assets.dart`](../lib/utils/brand_assets.dart) — 브랜드별 로고 path 분기 (`labelLogoPath` / `labelLogoFallbackPath`)
