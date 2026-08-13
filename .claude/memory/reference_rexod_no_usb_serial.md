---
name: reference_rexod_no_usb_serial
description: REXOD RXLA-561 은 USB iSerialNumber 를 보고하지 않음 (실측) — 동일 기종 2대 동시 운용이 SDK 레벨에서 불가한 근거
metadata: 
  node_type: memory
  type: reference
  originSessionId: d878d032-b8eb-41f1-a0bb-073f3db8a81e
  modified: 2026-08-13T03:35:01.128Z
---

2026-08-13 실측 (D2s_KDS_STGL `DK1925AJ40349` + REXOD RXLA-561, `adb shell dumpsys usb`).

```
vendor_id=4070          # 0x0FE6
product_id=33054        # 0x811E
manufacturer_name=Manufacture
product_name=Virtual PRN
serial_number=null      # ← iSerialNumber 디스크립터 자체가 없음
```

## 왜 이게 "동일 기종 2대 불가" 인가

Caysn SDK(`autoreplyprint`)가 이해하는 USB 포트명은 4종뿐이다
(`libautoreplyprint.so` 문자열 실측):

```
VID:0x%04X,PID:0x%04X            ← 동일 기종 2대가 같은 문자열
VID:0x%04X,PID:0x%04X,MI:%02d    ← MI 는 장치 인덱스가 아니라 인터페이스 번호
%s/%s                            ← productName/serialNumber ★ 유일한 구분 수단
%s/%s,MI:%02d
```

serial 이 없으면 두 대가 `Virtual PRN/null` 로 **같은 키**가 되어 지목이 불가능하다.
`NZUSBClientIO.Open(vid,pid,mi,ctx)` 는 `getDeviceList()` 순회 중 **첫 매칭에서 즉시 반환**
하고, `getDeviceList()` 는 HashMap 이라 재부팅·재연결마다 순서가 바뀔 수 있다.

## null 이 권한 마스킹이 아니라는 판별법 (재확인할 때 이 방법을 쓸 것)

`UsbDevice.getSerialNumber()` 는 Android 10+ 에서 권한 게이트가 있어 "null=부재" 로 바로
읽으면 오판한다. **같은 `dumpsys usb` 출력 안의 다른 장치를 대조군으로 쓰면 갈린다** —
루트 허브(`vendor_id=7531` = 0x1D6B)들이 `serial_number=fd880000.usb` / `xhci-hcd.1.auto`
처럼 실제 값을 보고하므로 이 출력 경로는 serial 을 가리지 않는다. 따라서 REXOD 의 null 은
진짜 부재다. `manufacturer_name`/`product_name` 이 정상 노출되는 것도 문자열 디스크립터
읽기 자체는 되고 있다는 방증.

sysfs `/sys/bus/usb/devices/*/serial` 은 shell 권한 거부라 교차 확인 불가.

**앱 내에서 USB 권한을 쥔 상태로 재확인 완료** (같은 날, warm-up 로그):
`[CONNECT] warmup 성공 ... 권한=있음 포트명=Virtual PRN/null`. 권한 게이트를 통과한
읽기에서도 null 이므로 디스크립터 부재가 확정이다. dumpsys 대조군보다 이쪽이 결정적.

## 콜백 핸들은 유효하다 (다중화 시 쓸 수 있음)

`CP_Printer_AddOnPrinterStatusEvent` 는 프로세스 전역 등록이지만, 콜백 첫 인자
`Pointer h` 에 **실제 포트 핸들이 온다** — 실측 `cb=native@0xa66d2e50
cur=native@0xa66d2e50 일치=true`. 따라서 프린터가 여러 대가 되면 이 핸들로 비콘을
프린터별로 귀속시킬 수 있고, 핸들 스코프 폴링 API(`CP_Printer_GetPrinterStatusInfo` /
`CP_Pos_QueryRTStatus`)로 갈아탈 필요가 없다.
⚠️ 단 이건 **필요조건만 확인한 것** — 1대 환경이라 `h == hPrinter` 가 자명하다.
"2대일 때 각자 자기 핸들로 온다" 는 충분조건은 실기기 2대 없이는 검증 불가.

**Why:** 관찰값이 "없음" 일 때 그것이 진짜 부재인지 관찰 수단의 한계인지 먼저 갈라야 한다.
같은 출력 안의 대조군을 찾는 게 가장 싼 방법이었다
([[reference_rexod_label_printer_signals]] 의 같은 원칙 — 관찰 불가한 것은 없는 것과 같다).

**How to apply:** 라벨 프린터 2대 운용 요구가 다시 오면 이 메모부터 볼 것.
남은 경로는 ① 벤더 유틸로 serial/device name 각인 ② 벤더 유틸로 PID 변경(되면 오히려
`PORT_CANDIDATES` 한 줄 추가로 끝나 가장 쌈) ③ LAN 옵션 모델 + `CP_Port_OpenTcp`
④ 기기 2대 구성. 상세 설계·공수는 계획서 `~/.claude/plans/rexod-memoized-deer.md`.

**대신 ④를 쓸 수 있게 만들어 두었다** (2026-08-13, 실기기 확인 완료): `LabelTarget` /
`LabelTargetPolicy`(`lib/services/label_printer/label_target.dart`) + 설정 화면
"라벨 구역 지정". 카테고리→구역 배정(매장 정책)과 이 단말이 출력할 구역(단말별 배치)을
나눠 저장해, **단말 여러 대 × 프린터 1대씩** 구성에서 각 단말이 담당 구역만 인쇄한다.
한 단말에 2대를 붙이는 길이 열리면 배정은 그대로 두고 `localTargets` 대신 타깃별 프린터
핸들로 분기하면 된다. ⚠️ 이때 **필터 모드를 두 번 돌려 나누는 방식은 쓰지 말 것** —
TPCP 세트 상품은 mode 1·2 양쪽에서 true 라 양쪽 프린터에 중복 인쇄된다.

관련: [[reference_rexod_label_printer_signals]], [[project_store_printer_topology]],
[[project_label_printer_platform_divergence]]
