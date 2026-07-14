---
name: reference_external_printer_liveness
description: Windows 외부 영수증 프린터 연결/생존 판정은 DLE EOT 1 핑이 권위 신호. PR800은 DSR/CTS 미전달(0x00).
metadata: 
  node_type: memory
  type: reference
  originSessionId: 5c97c095-ffc8-4a88-aa63-9cee81c38176
---

Windows 외부 영수증 프린터(COM 시리얼, ESC/POS)의 "연결됨"/출력 생존 판정 권위 신호는 **DLE EOT 1 핑**(`ComPortPrintService._probePrinter`). 포트 enumerate 존재만으로 판정하면 USB-Serial CDC 칩이 본체 전원 OFF에도 살아 false-positive(항상 초록)가 난다.

현장 검증 결과(주력 PR800 + USB-Serial CDC):
- **모뎀 신호 DSR/CTS는 0x00 — 안 잡힌다.** `GetCommModemStatus`로 읽어도 전부 false. 따라서 DSR/CTS 기반 감지는 이 하드웨어에선 무용. (`_readModemAlive`는 raw 비트 진단 로깅 전용으로만 남김. 판정에 쓰면 DSR/CTS를 high로 고정하는 싸구려 어댑터에서 false-positive 재발.)
- 단, 같은 PR800이라도 **RS-232 직결(NEXT-340PL/PL2303 어댑터) 경유면 DSR/CTS가 0x30으로 전달됨** (2026-07 실기). 즉 0x00은 CDC 경로 한정 특성. 판정은 여전히 DLE EOT만 사용. 상세: [[project_pr800_rs232_serial]]
- **DLE EOT 1에는 응답한다** — 단, 프린터가 멈춤(wedge)/오프라인 상태면 `probe-timeout`으로 무응답. 이때는 **프린터 전원 사이클**로 회복되면 다시 응답 시작. 멈춤 자체는 큐 backoff/재연결로도 자동 회복 시도됨.

연결 검증 진입점: [[project_store_printer_topology]]의 외부=COM 경로. `external_receipt_printer_windows.dart`의 `isConnected()` → `ComPortPrintService.probeConnection()`(open→DLE EOT 핑 재시도→close, sendRaw와 포트 락 공유). checkConnection은 주기 타이머 아님(앱 시작 1회·설정 화면·사용자 액션).

**How to apply:** 외부 프린터 "연결 안됨"/"출력 안됨" 디버깅 시 먼저 로그의 `[ComPortPrint] ... reason=probe-timeout`과 `모뎀상태 0x..` 줄 확인. probe-timeout이면 하드웨어 wedge 의심 → 전원 사이클 안내. DSR/CTS 기반 자동감지 제안은 이 현장에선 불가(0x00)임을 기억.
