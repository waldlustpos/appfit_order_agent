---
name: feedback-ffi-isolate-boxing
description: USB / hardware FFI 동기 호출은 main thread 를 수초 block 할 수 있음. unawaited 만으로는 부족하고 Isolate.run 으로 boxing 해야 함. handle address 만 cross-isolate 로 넘기는 패턴.
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 0c886ff3-b720-401a-be8a-01949f9ab18b
---

`autoreplyprint.dll` / `serial_port_win32` 같은 USB·하드웨어 FFI 의 동기 호출은 디바이스 미연결 / OS USB stack lag 환경에서 main thread 를 수백ms~수초 block 한다. `unawaited(...)` 로 호출해도 함수 본체의 동기 부분이 event loop 점유. **`Isolate.run<T>(() {...})` 으로 SDK 호출을 boxing** 하고, handle 같은 native pointer 는 raw `address` (int) 만 cross-isolate 로 받아 main isolate 의 instance state 갱신.

autoreplyprint SDK 가 cross-isolate handle 을 받아주는 점은 `WindowsLabelPrinterBackend._doPrintPng` 의 `posQueryPrintResult` Isolate.run 패턴이 검증. 같은 패턴으로 `portEnumUsb` / `portOpenUsb` 도 boxing 가능.

**Why:** 2026-05-20 라벨 USB 미연결 환경에서 앱 시작 / 설정 화면 진입 / 재연결 버튼 → main isolate 가 `portEnumUsb` × 2 + 4종 후보 `portOpenUsb` 순회 동안 block 되어 "앱 응답없음" 사고 (`unawaited(checkConnection())` 라도 동일).

**How to apply:**
- 새 FFI 동기 호출 추가 시 main thread block 가능성 평가 (USB / 하드웨어 / 외부 프로세스 의존이면 위험).
- isolate boxing 패턴: SDK 호출 + raw address 반환 → main 에서 `Pointer<T>.fromAddress(addr)` reconstitute → instance state 갱신. closure 안의 예외는 `(_) {}` 로 흡수하고 fallback 값 반환 (cross-isolate exception 전파는 main 다시 throw).
- 회귀 grep: `lib/services/label_printer/windows/` 또는 `lib/services/com_port_print_service.dart` 안에서 sync FFI 호출이 main isolate path 에 들어가는지. `Isolate.run` 없이 `bindings.port*` / `bindings.printer*` 호출 신규 추가 시 의도성 확인.
- 회귀 위험: 라벨 backend 의 `_enumerateUsbPortsAsync` / `_tryOpenUsbAsync` 를 sync 헬퍼로 되돌리면 [[project-store-printer-topology]] 환경의 모든 매장에서 시작 시 응답없음 재발.
- 관련: [[project-store-printer-topology]], [[feedback-hot-reload-cold-restart]] (변경 후 검증은 cold-restart 권장)
