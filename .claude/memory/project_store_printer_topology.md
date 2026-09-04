---
name: project-store-printer-topology
description: "매장 디바이스 환경 합의 — 외부 영수증 프린터는 COM 시리얼, 라벨 프린터는 USB, 둘은 별개 본체. Winspool fallback 의도적 배제."
metadata: 
  node_type: memory
  type: project
  originSessionId: 0c886ff3-b720-401a-be8a-01949f9ab18b
  modified: 2026-09-03T07:38:15.700Z
---

매장 운영 환경의 프린터 토폴로지 (사용자 합의, 2026-05-19 ~):

- **외부 영수증 프린터**: 시리얼 / COM 포트 (USB-Serial CDC 가상 COM 포함, PR800·D3MINI 등). PreferenceService 의 `getComPortName()` 명시 설정 시만 동작.
- **라벨 프린터**: USB 직결, 지원 2기종 — REXOD RXLA-561(Caysn autoreplyprint SDK, CP_Port_OpenUsb, 갭 라벨) + BIXOLON G30(연속용지+커터. Android=UPOS/JavaPOS SDK, Windows=usbprint 직결 ESC/POS — [[project-g30-windows-escpos-port]]). Caysn D2/D3 는 화이트리스트 잔류. VID:PID 자동감지 라우팅(NativeMethodHandler, G30 판정이 좁아 먼저). 구 BIXOLON XD5-40d 는 2026-09-01 지원 종료 — 남은 BIXOLON 자산의 소유권은 [[project-bixolon-xd5-removal-residue]].
- **별개 본체**: 두 프린터는 다른 물리 디바이스. USB 스택 자원 공유 없음 → 영수증/라벨이 진짜 병렬 동작 가능해야 함.

**Why:** Winspool RAW fallback 이 OS default 프린터를 외부 영수증으로 잘못 잡아 라벨 프린터 또는 "Microsoft Print to PDF" 같은 디바이스에 영수증을 송출하는 운영 사고를 차단하기 위해 사용자가 명시적으로 배제 합의. 외부=COM 단일 경로.

**How to apply:**
- Windows 외부 영수증 프린터 코드에서 Winspool / `getDefaultPrinterName()` / `getWindowsPrinterName()` / `winspool_raw_client.dart` 부활 금지. COM 미설정이면 즉시 `PrinterNoDevice`.
- 라벨/영수증 두 프린터의 큐·자원·UI 분기는 독립으로 설계. 한쪽 backoff 가 다른쪽을 막지 않아야 함 (현재 `OutputQueueService._receiptQueue` / `_labelQueue` 분리 + `NewOrderJob` 라벨 tail 의 영수증 await 이전 enqueue).
- 사용자에게 "외부 프린터 사용 ON 인데 COM 미설정" 상태가 의심되면 안내: UI 가 "연결안됨" 으로 표시되도록 보장(`external_receipt_printer_windows.dart`).
- 관련: [[feedback-queue-enqueue-timing]], [[feedback-ffi-isolate-boxing]]
