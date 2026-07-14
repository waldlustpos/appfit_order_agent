---
name: project-store-printer-topology
description: "매장 디바이스 환경 합의 — 외부 영수증 프린터는 COM 시리얼, 라벨 프린터는 USB, 둘은 별개 본체. Winspool fallback 의도적 배제."
metadata: 
  node_type: memory
  type: project
  originSessionId: 0c886ff3-b720-401a-be8a-01949f9ab18b
---

매장 운영 환경의 프린터 토폴로지 (사용자 합의, 2026-05-19 ~):

- **외부 영수증 프린터**: 시리얼 / COM 포트 (USB-Serial CDC 가상 COM 포함, PR800·D3MINI 등). PreferenceService 의 `getComPortName()` 명시 설정 시만 동작.
- **라벨 프린터**: USB 직결 (autoreplyprint SDK 의 CP_Port_OpenUsb). VID:PID 4종 화이트리스트.
- **별개 본체**: 두 프린터는 다른 물리 디바이스. USB 스택 자원 공유 없음 → 영수증/라벨이 진짜 병렬 동작 가능해야 함.

**Why:** Winspool RAW fallback 이 OS default 프린터를 외부 영수증으로 잘못 잡아 라벨 프린터 또는 "Microsoft Print to PDF" 같은 디바이스에 영수증을 송출하는 운영 사고를 차단하기 위해 사용자가 명시적으로 배제 합의. 외부=COM 단일 경로.

**How to apply:**
- Windows 외부 영수증 프린터 코드에서 Winspool / `getDefaultPrinterName()` / `getWindowsPrinterName()` / `winspool_raw_client.dart` 부활 금지. COM 미설정이면 즉시 `PrinterNoDevice`.
- 라벨/영수증 두 프린터의 큐·자원·UI 분기는 독립으로 설계. 한쪽 backoff 가 다른쪽을 막지 않아야 함 (현재 `OutputQueueService._receiptQueue` / `_labelQueue` 분리 + `NewOrderJob` 라벨 tail 의 영수증 await 이전 enqueue).
- 사용자에게 "외부 프린터 사용 ON 인데 COM 미설정" 상태가 의심되면 안내: UI 가 "연결안됨" 으로 표시되도록 보장(`external_receipt_printer_windows.dart`).
- 관련: [[feedback-queue-enqueue-timing]], [[feedback-ffi-isolate-boxing]]
