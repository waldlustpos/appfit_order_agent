---
name: project_usb_direct_label_pipeline
description: 경로 B — Android USB Host API 직접 제어로 라벨 인쇄(TSPL BITMAP) 이식. 극성 확정·임계값 튜닝 진행 중
metadata: 
  node_type: memory
  type: project
  originSessionId: d878d032-b8eb-41f1-a0bb-073f3db8a81e
  modified: 2026-08-13T07:41:33.435Z
---

RXLA-561 동일 기종 2대 운용을 위해 Caysn SDK 를 버리고 USB Host API 로 직접 제어하는
작업. 브랜치 `feat/label-zone-routing`. 계획서 `~/.claude/plans/rexod-memoized-deer.md`
의 "경로 B". Caysn 으로는 불가한 이유는 [[reference_rexod_no_usb_serial]].

## 확정된 사실 (2026-08-13 실기기 D2s_KDS_STGL + REXOD 2대)

### 2대 독립 제어 ✅
`UsbDevice` 객체 지목이라 serial 이 없어도 갈린다. 두 기계가 각자 자기 라벨을 뽑았다.
```
장치1 bus=3 node=/dev/bus/usb/003/005 if=7 out=2 in=130
장치2 bus=5 node=/dev/bus/usb/005/005 if=7 out=2 in=130
```

### TSPL BITMAP 비트 극성 = **비트 0 이 검정** ✅
TSPL 스펙대로다(일반 감각과 반대). 판별 카드(전 비트 0 블록 vs 전 비트 0xFF 블록을
나란히 인쇄)에서 **왼쪽(0x00)이 검게** 나왔다.

⚠️ **판별 카드를 따로 뽑은 이유**: 실제 라벨을 반대 극성으로 뽑으면 490×600 전면이
새까맣게 인쇄된다. 카드는 48×96 dot 블록 2개라 잉크가 거의 안 든다. 다른 기종을
붙일 때도 실제 라벨 대신 카드로 먼저 가를 것.

### SIZE/GAP 필수
`CLS+TEXT+PRINT` 만 보내면 모터 소리만 나고 용지가 안 나온다. 통하는 프리앰블:
```
SIZE 61 mm,75 mm      ← LabelPainter 490×600 dot @203dpi(8 dot/mm)
GAP 2 mm,0 mm
DIRECTION 0
CLS
```
SIZE 는 **매체 속성**이지 이미지 속성이 아니다 — 이미지 크기에서 유도하지 말 것.

### BITMAP raw 는 길이 구분
`BITMAP x,y,widthBytes,height,0,<raw>` 의 raw 는 `widthBytes*height` 바이트로
길이 구분된다. 안에 0x0A/0x0D 가 섞여도 파서가 명령 끝으로 오해하지 않는다.
대신 raw **뒤**에 CRLF 를 붙여야 다음 명령이 인식된다.

### 패딩 비트 함정
490 dot → 62바이트 = 496 dot 이라 오른쪽에 6 dot 이 남는다. 이 비트를 0 으로 두면
(0=검정 극성에서) 라벨 오른쪽 끝에 **6 dot 검은 띠**가 생긴다. 버퍼를 흰색 값으로
먼저 채운 뒤 실제 픽셀만 덮어쓸 것.

### 이진화 임계값 = **232** ✅ (기본값 128 은 너무 얇다)

USB Direct 라벨이 Caysn 출력물보다 **글자가 얇게** 나왔다.

**증상으로 축을 가른 것이 핵심**: "연하다/흐리다" = 농도(DENSITY) 축,
"획이 얇다" = 이진화 축. 사용자가 "선명도라기보다 폰트가 얇아진 느낌" 이라고
정정해 줘서 농도 축을 아예 실험에서 뺄 수 있었다. 두 축을 같이 흔들었으면 원인이
섞였을 것이다.

원인: LabelPainter 는 글자 가장자리를 안티에일리어싱 **회색**으로 렌더한다.
임계값 128 은 "50% 이상 덮인 픽셀만 검정" 이라 그 회색을 전부 버린다.

- 1차 128/176/216 → 216. 단 **끝값**이라 최적이 바깥일 수 있어 재확인
- 2차 216/232/244 → **232 확정**

즉 Caysn 의 `CP_ImageBinarizationMethod_Thresholding` 은 128 보다 **훨씬 관대한**
임계값을 쓰고 있었다. 이 값은 비공개라 실측 말고는 알 방법이 없었다.

⚠️ **임계값은 QR 모듈도 같이 굵힌다.** 무작정 올리면 모듈 사이 여백이 메워져 스캔이
깨진다. 바꿀 때는 획 굵기와 QR 스캔을 **함께** 볼 것. 둘이 상충하면 QR 영역만 다른
임계값을 쓰는 쪽으로 가야 한다.

**후보 비교는 재빌드 없이** `probeDirectBitmapTuning`(개발자 옵션 버튼)으로 돌린다 —
조합을 Dart 가 정하고, 라벨 주문번호 자리에 `T232` 가 찍혀 인쇄물만 보고 고를 수 있다.

## 함정 — 진단 하네스가 운영과 다른 이미지를 쓰고 있었다

프로브가 `LabelPainter.generateLabelImage` 에 `qrSize`/`qrErrorCorrectLevel` 을
안 넘겨 기본값(120px·레벨 M)으로 렌더됐다. **운영 V2 는 `qrSizeForLayout(1)` =
120×1.5 = 180px·레벨 L** 이다 → 33% 작고 더 촘촘한 라벨을 비교하고 있었다.
사용자가 "QR 이 작다" 고 해서 발견. USB Direct 문제가 아니었다.

**Why:** 진단이 운영과 다른 이미지를 쓰면 그 차이가 결론을 통째로 오염시킨다.
레이아웃 버전만 맞추면 되는 게 아니라 **버전에 딸린 정책 함수**(`qrSizeForLayout`,
`qrErrorCorrectLevelForLayout`)까지 호출해야 운영과 같아진다.

**How to apply:** 진단용 라벨은 반드시 공용 빌더 하나(`_buildProbeLabel`)를 거치게
할 것. 호출부마다 파라미터를 나열하면 또 빠진다.

## 미해결 — IN 채널 비대칭

장치1(bus 3)은 status 비콘 응답이 **0건**, 장치2(bus 5)는 정상
(`53 1C 0E 00 00 04 00 45 …`). **완료 판정을 비콘에 의존하려면 이걸 먼저 풀어야
한다** — paper-state machine 의 선행조건이다.

⚠️ **1차 관측만으로는 원인을 못 가린다** — "그 기계의 특성" 과 "먼저 처리한 장치라는
위치의 특성" 이 완전히 교락돼 있었다. 그래서 `probeDirectInChannel` 은 인쇄 없이
**정순 → 역순**으로 각 10초씩 비콘을 센다:

- 순서를 바꿔도 같은 bus 가 0건 → 기계/케이블 고유
- 순서를 바꾸면 0건이 옮겨감 → "먼저 연 장치" 구조 문제(커널 usblp 잔여 claim 등)
- 둘 다 정상 → 1차는 read timeout(2~3초)이 비콘 주기(~2초) 경계에 걸린 **측정 아티팩트**

## 남은 것

1. ~~임계값 확정~~ ✅ 232
2. paper-state machine — peel `(byte7 & 0xA0)==0xA0` / detach `==0x80` /
   buzzer byte1 `0x1C`. 프로토콜은 [[project_label_ack_patch]] 에 역공학돼 있음
3. `LabelPrintOutcome` 3분류 · submit-wins · "retryable 일 때 정확히 1회" 계약 유지
4. `LabelTarget` ↔ 버스번호 매핑, Caysn↔Direct 토글(가면 둘 다 간다 — 혼용 금지)

## 코드 위치

- `android/.../util/print/UsbLabelDriver.java` — 드라이버 + 진단 3종
  (`probeDirectTwoDevices` / `probeDirectBitmap` / `probeDirectBitmapTuning`)
- `NativeMethodHandler.java` — `probeDirectUsbLabel` / `probeDirectUsbBitmap` /
  `probeDirectUsbBitmapTuning`
- `lib/widgets/settings/settings_label_test_section.dart` — 개발자 옵션 버튼
- `lib/services/platform_service.dart` — Dart 진입점

관련: [[reference_rexod_no_usb_serial]], [[project_label_ack_patch]],
[[reference_rexod_label_printer_signals]], [[project_label_printer_platform_divergence]]
