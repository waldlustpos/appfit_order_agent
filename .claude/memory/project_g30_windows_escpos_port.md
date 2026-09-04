---
name: project-g30-windows-escpos-port
description: G30 Windows 이식은 BXLPAPI 아닌 usbprint 직결 ESC/POS 로 끝났다 — 계획 문서가 전제한 벤더 SDK 가 불필요했던 사례
metadata: 
  node_type: memory
  type: project
  originSessionId: 5865ac97-402a-48ad-9acf-844de4c5dda7
  modified: 2026-09-03T23:11:00.480Z
---

BIXOLON G30 라벨 프린터의 Windows 지원(2026-09-03). `docs/PRINTER_FLOW.md` §3.8 이 정본.

**결론: 벤더 DLL 없이 끝났다.** 문서·라우터 주석·메모리 3곳이 모두 "Windows 는 BXLPAPI 로
명령셋이 또 다르다"고 적어 두었지만, 실제로는 G30 이 usbprint devnode 로 잡히고 **ESC/POS
래스터(`GS v 0`)를 그대로 받는다.** POSBANK A8 영수증용으로 이미 있던
`UsbPrintService.sendRaw`(SetupAPI + CreateFile/WriteFile) 를 그대로 재사용했다.
BXLPAPI SDK 는 보유 중이지만 쓰지 않았다.

**Why:** 계획 문서에 적힌 "남은 작업"이 특정 구현 수단까지 못박아 두면, 더 싼 경로가
있는데도 그 수단을 조달하는 것부터 시작하게 된다. 여기서는 문서가 BXLPAPI 를 전제한 탓에
"SDK 수급"이 착수 조건처럼 보였다.

**How to apply:**
- 이식 대상이 "벤더 SDK 가 필요하다"고 적혀 있어도, **그 장치가 OS 표준 인터페이스로
  이미 보이는지 먼저 확인**할 것. G30 은 `usb_print_service.dart` 주석에 *"현장 PC 에는
  BIXOLON G30 도 usbprint 로 잡혀 있다"* 는 실측이 이미 적혀 있었다 — 답이 레포 안에 있었다.
- 프로토콜 추정의 결정적 증거는 **증상 자체**였다: 임의 바이트가 글리프로 인쇄된다 =
  ESC/POS 텍스트 모드. 벤더 문서를 찾기 전에 관측된 동작을 먼저 읽을 것.
- 검증은 `tool/g30_windows_probe.dart` — 앱과 **같은 인코더·같은 전송 방식**을 쓰는
  standalone `dart run` 스크립트. 앱 빌드(수 분) 없이 가장 위험한 가정 하나만 수 초에
  판별한다. 이걸 위해 인코더를 `dart:ui` 없는 순수 파일로 유지하는 것이 설계 제약이다.

## 같이 고친 버그 — Caysn SDK 가 G30 에 바이트를 쓰고 있었다

증상: **"연결안됨" 인데 G30 에서 깨진 문자가 한 줄 인쇄됨.** 두 증상이 같은 뿌리다.
`_ensurePortOpen` 이 `CP_Port_EnumUsb` 결과를 VID/PID 필터 없이 전부 열어봤고
(`_kUsbPortCandidates` 는 게이트가 아니라 **열거 실패 시 폴백**이었다), usbprint devnode 는
`CreateFile` 이 성공하므로 SDK 가 G30 에 Caysn 핸드셰이크를 써 넣었다. G30 이 응답을
못 주니 `portIsOpened` 가 0 → 연결안됨.

**일반화: 화이트리스트가 "폴백"으로만 쓰이면 그건 게이트가 아니다.** 열어봐서 확인하는
행위 자체가 부작용(남의 장비에 쓰기)이면 "모르면 시도"가 성립하지 않는다 — VID/PID 를
못 읽는 이름은 버리는 쪽이 맞다.

## 재이식/확장 시 주의

- **이진화 임계 210** 은 Android `BixolonPosDriver.BINARIZE_THRESHOLD` 승계. 재유도 금지.
- `g30_escpos_raster.dart` 에 win32 를 끌고 오는 파일(`escpos_builder.dart`)을 import 하면
  Android 크래시 — `ESC @`/`GS V 66 0` 상수를 **일부러 복제**했다. [[reference_win32_deferred_import]]
- 백엔드는 `usb_print_service` 를 `deferred as` 로만 import.
- **진입 게이트는 2026-09-04 에 Android 동등으로 올렸다** (DLE EOT 커버열림·용지없음
  무한 복구대기). 실측 정본과 함정 3개는 `docs/PRINTER_FLOW.md` §3.8.
- **완료 판정은 여전히 최소 범위**(WriteFile 성공 = 성공). ESC/POS 에 "이 작업이 끝났는가"
  신호가 없어 근사 판정 시 중복 인쇄 위험 — [[project_label_ack_timeout_duplicate]] 참조.
  **중복은 유실보다 나쁘다**는 것이 판단 근거다.

## DLE EOT 상태 조회 — 재사용할 결론

- 인터페이스가 `Prot_02`(양방향)여야 가능하다. `Prot_01` 이면 IN 엔드포인트가 없어 원천 불가 —
  **다른 기종 검토 시 이걸 먼저 볼 것**(호환 ID 로 물리 조작 없이 판정된다).
- **커버가 열려 있으면 용지 센서는 보고되지 않는다.** 두 신호를 각각 읽어 OR 로 막아야 한다.
- **질의 전 드레인 필수.** 안 하면 응답이 한 칸씩 밀려 엉뚱한 바이트를 용지없음으로 오독한다.
- **overlapped I/O 가 `FALSE` + `GetLastError()==0` 을 돌려줄 수 있다.** 실패로 단정하면
  첫 질의가 항상 무응답이 된다.
- 고정 비트(`b & 0x93 == 0x12`) 검증 실패 = 상태 모름 → **fail-open 통과**. 게이트가 없던
  시절에도 출력은 됐으므로 게이트가 출력을 막는 회귀를 만들면 안 된다.

**Why(방법론):** 처음 프로브에서 응답이 들쭉날쭉해 "G30 이 상태를 안 준다"로 결론 낼 뻔했다.
실제로는 프로브 자신의 버그 2개(위 3·4번)였다. **측정 도구가 의심스러울 때 피측정체를
탓하지 말 것** — 이 레포의 [[project_bixolon_g30_40mm_layout]] 에 이미 같은 교훈이 있다
(측정 경로의 320 clamp 가 가짜 실측값을 만든 건). 결정적 전환점은 추측을 늘리는 대신
호환 ID 로 **양방향 여부라는 확정 사실**을 먼저 잡은 것이었다.

관련: [[project_bixolon_g30_40mm_layout]] · [[project_bixolon_xd5_removal_residue]] ·
[[reference_g30_usb_claim_stuck]] · [[project_store_printer_topology]] ·
[[project_label_printer_platform_divergence]]
