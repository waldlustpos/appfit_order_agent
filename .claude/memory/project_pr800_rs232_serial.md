---
name: project_pr800_rs232_serial
description: "PR800(OK POS) RS-232 직결 검증 완료 — 시리얼측 baud는 115200 고정(9600 아님), NEXT-340PL(PL2303) 케이블 OK. 진단은 raw Win32 baud 스윕 스크립트로."
metadata: 
  node_type: memory
  type: project
  originSessionId: 3df75ea7-d5d8-42c0-8cf6-aabd3c9176aa
---

PR800(OK POS) 영수증 프린터를 **RS-232 시리얼 포트로 직결**하는 구성 검증 완료 (2026-07-02, NEXT-340PL USB-RS232 케이블 = Prolific PL2303, COM6).

- **PR800 시리얼 포트 기본 보레이트는 115200** — 9600/19200/38400/57600에서는 DLE EOT 무응답, 115200에서만 0x16 응답. 이에 따라 **양 앱의 보레이트 기본값도 115200으로 변경됨**(2026-07-02, 서비스 상수·PreferenceService·설정 UI 3지점씩). 단 이미 prefs에 baud를 저장한 기기는 저장값 우선 — 구형 기기에서 9600이 저장돼 있으면 설정에서 115200 재선택 필요. CDC는 baud 무시라 어느 값이든 무해.
- RS-232 직결에서는 DSR/CTS가 0x30(high)으로 전달됨 (CDC 경로와 반대 — [[reference_external_printer_liveness]]).
- 양 프로젝트(appfit_order_agent, kokonut_order_agent_v2)의 `com_port_print_service.dart`에 RS-232 어댑터 하드닝 적용됨(2026-07-02): StopBits DCB raw값 버그(1=1.5stop → 0), DCB prime, DTR/RTS assert, open 핸들누수 회수, probe write false 비치명화, (kokonut) drain delay. 근거·상세는 해당 파일 주석이 정본.

**Why:** 시리얼 프린터 신규 설치/트러블슈팅 때 보레이트·케이블 판단을 반복 조사하지 않기 위함.

**How to apply:** 시리얼 프린터 무응답 디버깅 시 ① 보레이트 스윕(115200 우선) ② DLE EOT 1(0x10 0x04 0x01) 응답 확인 ③ 응답 바이트 0x16=온라인. 진단은 raw Win32 FFI Dart 스크립트(CreateFile 비-overlapped + GetCommState→SetCommState(StopBits=0) + WriteFile/ReadFile 동기)로 패키지 층을 우회해 에러코드를 직접 확인하는 방식이 유효했음. PL2303은 SetCommState 검증이 엄격(무효 DCB 거부), usbser.sys(CDC)는 관대 — "CDC에서 되는데 어댑터에서 안 되면" DCB 값부터 의심.
