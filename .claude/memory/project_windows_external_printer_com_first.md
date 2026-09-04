---
name: project-windows-external-printer-com-first
description: Windows 외부 영수증은 COM 우선 — PR800이 복합장치라 usbprint에도 중복 열거되던 것을 VID:PID로 접음
metadata: 
  node_type: memory
  type: project
  originSessionId: 5865ac97-402a-48ad-9acf-844de4c5dda7
  modified: 2026-09-03T23:38:40.532Z
---

Windows 외부 영수증 프린터의 연결 대상 선택을 **COM 우선**으로 바꿨다 (2026-09-04).
정본은 `docs/PRINTER_FLOW.md` §2.2.

**근거는 기술이 아니라 운영이다.** 현장 설치가 오래도록 COM 표기(`COM3` 등)를 보고
세팅해 왔고, 일반 설치 기종이 PR800(COM)이며 usbprint 전용(POSBANK A8)은 예외 설치다.
예외 때문에 일반이 낯설어지면 안 된다.

## 놓치기 쉬운 사실 — PR800은 양쪽에 잡힌다

PR800은 복합 USB 장치(`VID_0D28&PID_4C59`)라 **두 번 열거된다**:
- `MI_00` → usbprint devnode (`\\?\usb#vid_0d28&pid_4c59&mi_00#...`)
- `MI_01` → CDC → `COM3`

그래서 손대지 않으면 ① 설정 드롭다운에 같은 프린터가 두 줄로 나오고 ② 재연결 스캔이
usbprint를 먼저 채택해 설정에 `COM3` 대신 장치 경로가 박혔다. **순서만 뒤집는 걸로는
부족했다** — 중복 자체를 접어야 했다.

짝 판정은 `VID:PID` (`usbIdKeyOrNull`). usbprint는 장치 경로에서, COM은 SetupAPI
`hardwareId`에서 뽑는데 `parseUsbIdsFromDevicePath`가 두 표기를 모두 받는다(이미 폭
프리시드가 쓰던 성질). VID/PID를 못 뽑는 후보(물리 RS-232)는 건드리지 않는다.

## 규율 3가지 (되돌리기 전에 읽을 것)

1. **중복만 없애고 선택지는 줄이지 않는다.** 짝이 없는 usbprint 전용 기종(A8)은 그대로
   남아야 한다 — 예외 설치를 못 쓰게 만들면 안 된다.
2. **자동 이전(migration) 금지.** 이미 usbprint로 잡아 쓰는 단말은 그대로 둔다. 같은
   프린터라도 COM 쪽 드라이버가 죽어 있을 수 있어, 동작 중인 설정을 말없이 바꾸면
   "설정을 만진 적 없는데 출력이 끊긴다"가 된다.
3. **저장 대상은 중복 제거에서도 예외**(`keep` 인자). 지우면 드롭다운이 "미선택"으로
   보이는데 실제로는 멀쩡히 출력되고 있어 더 혼란스럽다.

## 뒤집은 이전 결론

기존 스캔 순서는 **usbprint 먼저**였고 그 근거가 코드 주석·테스트 헤더에 적혀 있었다:
"usbprint 후보는 프린터임이 확실하고 probe가 수 ms, COM 후보에는 캐시드로어·저울이
섞여 있고 포트당 수백 ms — 확실한 쪽을 먼저 훑어 조기 종료하면 무관한 장비를 덜 건드린다."

그 대가를 알고 뒤집었다. 다만 **건드리는 대상 자체가 늘지는 않는다** — usbprint가 못
잡으면 어차피 COM을 전부 훑던 구조라 순서만 바뀐다. 재연결은 수동 버튼이라 지연은 받는다.
(기존 근거를 지우지 말 것 — 되돌릴 때 필요하다.)

관련: [[project_store_printer_topology]] · [[project_external_printer_usbprint_and_width]] ·
[[project_pr800_rs232_serial]] · [[project_g30_windows_escpos_port]]
