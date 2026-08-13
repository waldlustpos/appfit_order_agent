---
name: reference_rexod_no_usb_serial
description: REXOD RXLA-561 은 USB iSerialNumber 를 보고하지 않음 (실측) — 동일 기종 2대 동시 운용이 SDK 레벨에서 불가한 근거
metadata: 
  node_type: memory
  type: reference
  originSessionId: d878d032-b8eb-41f1-a0bb-073f3db8a81e
  modified: 2026-08-13T08:16:04.573Z
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

## ❌ 이중 open 우회로도 막혔다 — 실기기 2대로 확정 (2026-08-13)

"첫 번째가 인터페이스를 claim 했으니 두 번째 `CP_Port_OpenUsb` 는 나머지 장치로 떨어지지
않을까" 를 프린터 2대 실물로 시험했고 **실패**했다. 3중 교차 확인:

1. **물리**: 2차 open 전 운영 핸들로 1장 → 6초 → 2차 open 후 프로브 핸들로 1장.
   **두 장이 같은 기계에서** 나왔다(사용자 육안 확인).
2. **상태 귀속**: 30초 폴링 중 사용자가 **2번 기계**의 커버를 열고 닫았는데
   **두 핸들 어디에도 변화가 없었다.** 1번 기계 커버는 프로브 핸들에 즉시 잡혔다
   (`err=0x0084[용지없음][커버열림]`).
3. **탈취**: 2차 open 이 같은 장치를 force-claim 해 **기존 연결이 죽는다.**

⚠️ **죽은 핸들이 곧바로 죽었다고 보이지 않는다** — `CP_Port_IsConnectionValid` 는 한동안
true 를 유지하고 `CP_Printer_GetPrinterStatusInfo` 는 **그 시점 값에 얼어붙은 채** 정상처럼
응답한다(30초 내내 `[안뗌]` 고정). 한참 뒤에야 valid=false 가 된다. 즉 **"살아 있어 보이는
좀비 핸들"** 이 생긴다 — 이중 open 을 시도하는 코드는 조용히 인쇄를 잃는다.

원인은 구조적이다: `NZUSBClientIO.Open(vid,pid,mi,ctx)` 가 `getDeviceList()` 순회 중
**첫 VID/PID 매칭에서 즉시 return** 하고 claim 여부를 보지 않는다. 2번 장치에 도달할
코드 경로가 없다.

`/dev/usb/lp0` (SDK 가 받는 또 다른 포트명 형식) 도 막혔다 — 2대를 꽂아도 노드가 **1개**뿐이고
`crw------- root root` 라 앱이 열 수 없다.

**결론: Caysn SDK 로 동일 기종 2대 지목은 불가능하다.** 남은 길은 Android USB Host API
직접 제어(`UsbDevice` 객체로 지목 → serial 불필요)뿐이다. 프로토콜은 이미 역공학돼 있다
([[project_label_ack_patch]] 의 TSPL BITMAP / paper-state machine / buzzer 비트).

## ✅ USB Host API 로는 된다 — 실기기 2대 실증 (2026-08-13)

`UsbLabelDriver.java` 1차 구현으로 **동일 기종 2대를 독립 제어**하는 데 성공했다.
두 기계가 각각 자기 라벨(`USB-1` / `USB-2`)을 뽑았다.

```
장치1 open=true bus=3 node=/dev/bus/usb/003/005 if=7 out=2 in=130
장치2 open=true bus=5 node=/dev/bus/usb/005/005 if=7 out=2 in=130
```

`if=7`(USB Printer Class) / bulk OUT `0x02` / IN `0x82` — [[project_label_ack_patch]] 의
2026-05 PoC 값과 정확히 일치. **Gate A 는 하드웨어 한계가 아니라 Caysn 포트명 문법의
한계였다.**

**TSPL 은 SIZE/GAP 를 먼저 보내야 인쇄한다.** `CLS`+`TEXT`+`PRINT` 만 보내면 모터
소리만 나고 용지가 안 나온다(실측). 통하는 프리앰블:
```
SIZE 61 mm,75 mm      ← LabelPainter 490×600 dot @203dpi(8 dot/mm) 기준
GAP 2 mm,0 mm
DIRECTION 0
CLS
```

### 장치 매핑 키는 **USB 버스 번호**

`/dev/bus/usb/BBB/DDD` 의 **device 번호(DDD)는 재열거마다 증가**한다(002→003→005 실측).
버스 번호(BBB)는 물리 포트에 대응해 안정적이다. 단 **이건 "포트" 식별이지 "프린터"
식별이 아니다** — 케이블을 다른 포트로 옮기면 매핑이 기계가 아니라 포트를 따라간다.

프린터 고유 식별은 현재 불가: 벤더 유틸의 SYSTEM NAME/SERIAL 은 USB 디스크립터에 안
실리고(전원 재인가 후에도 불변), `CP_Proto_QuerySerialNumber` 는 `rc=-1` 로 실패한다.

### ✅ 해결됨 — IN 채널 비대칭은 Caysn 이 켜는 것이었다

장치1 만 비콘 0건이던 것은 **고장이 아니라** Caysn 의 `CP_Port_OpenUsb(name, 1)` 이
켜 주는 벤더 전용 레이어였다(첫 매칭 한 대만 열리므로 그 한 대만 말한다).
조용한 장치도 **표준 ESC/POS 상태 명령에는 정상 응답**하고, 완료 판정은
`DLE EOT 4` 의 bit2 로 벤더 의존 없이 된다.
상세·판별 절차: [[project_usb_direct_label_pipeline]]

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
