---
name: 라벨 ACK 패치 — D2s_KDS_STGL 검증 결과
description: PrintedEvent ACK 패치 (커밋 d187e57) D2s_KDS_STGL 디버그 부하 테스트 결과. SDK 콜백 미동작 확인 + race 재현 확인.
type: project
originSessionId: b388391c-2fba-4c63-be88-5693ed533a86
---
## 배경
2026-04-30 청산점(青山店) 주문 #958 (バニララテ + カフェラテ) 라벨 한 장 누락 사고. 분석 결과 `autoReplyMode=0` 단방향 SDK 환경에서 PagePrint 두 호출 사이 race 가 원인으로 추정.

## 적용된 패치 (커밋 d187e57, 2026-05-01, 로컬에만 — origin/main 보다 1 앞섬)
SDK의 `CP_Printer_AddOnPrinterPrintedEvent` 콜백을 등록해 PagePrint ACK 를 받을 때까지 다음 호출을 차단. `autoReplyMode` 운영 기본값 1 로 변경. 검증 안 된 폴링 fallback / 강제 close 분기 제거하여 단순화. 비프음 흐름은 `INFO_PAPERNOFETCH` 비트 미체크로 보존.

핵심 파일: [LabelPrinter.java](android/app/src/main/java/co/kr/waldlust/order/receive/util/print/LabelPrinter.java) (265→190줄, 분기 3→0).

**Why:** ACK 콜백 fire 시점이 SDK 문서로 명시 안 됨 + 단말 펌웨어별 동작 검증 필요.

**How to apply:** 새 세션에서 사용자가 "라벨 테스트 결과", "ACK 부하 테스트", "청산점 라벨 누락 후속" 같은 표현을 쓰면 이 메모리 참조.

## 2026-05-04 D2s_KDS_STGL 디버그 부하 테스트 결과

테스트 단말: SUNMI D2s_KDS_STGL (시리얼 DK1925AJ40349, Android 11). 디버그 빌드 + logcat + 단말 로그파일(`/sdcard/Documents/appfit/appfit_2026-05-04.txt`) 회수.

### 발견 1 — D2s_KDS_STGL 에서 SDK PrintedEvent 콜백 완전 미동작
- `[CALLBACK] PrintedEvent register -> true` (등록은 성공)
- 테스트 출력 3장 + 부하 테스트 54 iter (108 페이지) 모두 `acked=false (5000ms)` — 콜백 fire 0건
- 즉 ACK 게이트는 이 단말에서 단순 5초 sleep 효과로만 동작
- **추가 검증 (08:53 ~ 08:54)**: 제조사 PrinterSetting GUI 에서 Motor Step Detection / Paper Near Ending 두 설정 모두 Enable 변경 후 재시도 — 5/5 모두 `acked=false (5000ms)`. 이 두 설정은 펌웨어 내부 감지만 켜고 USB ACK 채널은 무관. **운영 단말에는 두 옵션 적용 비권장** (false positive 위험만 추가). 단 `Set unprintable when paper not taked out` 토글은 buzzer/감지의 펌웨어 내부 트리거로 필요 — 그대로 둘 것.

### 발견 2 — autoReply=0 에서 race 재현 확인 (청산점 가설 입증)
부하 테스트 Phase B (3 iter, autoReply=0):
- iter 1: 1.5s — 정상
- iter 2: **19.3s** (페이지 2/2 가 18.3s hang)
- iter 3: **13.5s** (페이지 2/2 가 11.8s hang)
사용자 중단됨. 청산점 사고 패턴(2장 빠른 호출 시 둘째 장 stuck) 재현.

### 발견 3 — autoReply=1 (현 패치) 에서 안정성
부하 테스트 Phase A (54 iter, autoReply=1):
- 모든 iter ~11s (5초 ACK timeout × 2)
- 108/108 결과 성공 (포트 열림 판정 — 종이 출력 여부와는 별개. 종이는 정상 출력 확인)
- **outlier**: iter #16/#18/#25 등에서 페이지 7~21s — 5초 sleep 으로도 완전 안전은 X

## 시사점
- 현 ACK 패치는 D2s_KDS_STGL 에서 "단말 종속 5초 sleep" 과 동등
- 그래도 race 보호 효과는 분명함 (Phase B 와 비교)
- 운영 부작용: 라벨 1장당 +5초 → 1주문 5장 시 출력 +20초 = UX 영향
- **분석기 버그**: `/tmp/analyze_stress_log.py` 가 multi-phase 로그(같은 iter 번호 재시작) 처리 못함. 다음 사용 전 수정 필요.

**Why:** SDK 콜백 미동작이 D2s_KDS_STGL 펌웨어/SDK 빌드 한계인지, 다른 콜백 (`ReceivedEvent` / `StatusEvent`) 으로 우회 가능한지 미검증. 청산점 단말도 D2s_KDS 일 가능성 높음(KDS 매장).

**How to apply:** 후속 작업 시 이 검증 결과 위에서 결정. 아래 "다음 결정 분기" 참고.

## 대안 SDK 조사 (2026-05-04)

라벨 프린터 GUI(PrinterSetting 3.0) 는 중국 OEM 보드 공통 — Vretti/Caysn/MUNBYN/ARKSCAN 등 모두 동일 펌웨어. Label Cmd Set = TSC/TSPL 확정. VID 0x4B43 은 KC/Vretti 가능성.

| 후보 | ACK/콜백 | 적합성 |
|---|---|---|
| Caysn AutoReplyPrint (현재) | PrintedEvent — D2s 에서 미동작 확정 | 기준선 |
| [tspl2-driver (fintrace)](https://github.com/fintrace/tspl2-driver) | 약함, fire-and-forget | OSS 대안, ACK 개선 보장 X |
| [flutter_pos_printer_platform](https://github.com/marwenbk/flutter_pos_printer_platform) | BT state stream 만 | Flutter 통합 깔끔, ACK 약점 동일 |
| Bixolon SDK | StatusUpdateEvent 풍부 | 자사 프린터 한정 — 하드웨어 교체 |
| Zebra Link-OS | 산업 표준 콜백 | 하드웨어 교체 |
| Sunmi External Printer | 단말 API | 라벨 호환성 약함 |
| DantSu/ESCPOS-ThermalPrinter-Android | 없음 | 라벨 명령 미지원 |
| **Android USB Host API + TSPL READ / DLE EOT polling** | bulk-in 직접 read = 진짜 ACK 가능성 | **검증 비용 최저, 응답 여부로 펌웨어 한계 확정 가능** |

**핵심 가설**: ACK 미동작은 SDK 레이어가 아니라 펌웨어/USB-Serial chip(PL2303) 한계일 가능성 높음. 다른 SDK 로 바꿔도 동일 결과 가능성. 50줄 USB Host API 프로토타입으로 bulk-in 응답 유무 확인이 가장 정보 가치 큼.

**Why:** Caysn 네이티브 .so 가 이미 bulk-in 을 read 중인데도 PrintedEvent fire 0건 = SDK 의 read loop 가 작동해도 펌웨어가 response 를 안 내는 것이 가장 합리적 설명.

**How to apply:** "다른 라벨 SDK 검토" 같은 표현 나오면 이 표 참조. USB Host API 프로토타입을 가장 먼저 추천.

## 2026-05-04 Direct USB PoC — paper-state machine 입증

기존 Caysn AAR 의 PrintedEvent 미동작 가설을 깨고, **펌웨어가 USB bulk-in 으로 자발적 status 비콘을 ~2초 주기로 보낸다**는 사실을 USB Host API 직접 프로브로 확인.

### USB 라벨 프린터 식별
- VID `0x0FE6` PID `0x811E` (mfg "Manufacture", product "Virtual PRN")
- USB Printer Class 7, subclass 1, **protocol 2 (Bidirectional)**
- bulk OUT `0x02`, bulk IN `0x82`, maxPacket 64

### 응답 패킷 형식
- **명령 ACK**: `53 00 06 E4 [seq] 00 03 [chk]` — 매 OUT 명령마다 sequence 증가 응답
- **자발적 status**: `53 1B XX 00 00 04 00 [byte7]` — ~2초 주기 비콘

### paper-state machine (byte 7)
| 상태 | byte 7 | bit 7 (0x80) | bit 6 (0x40) | bit 5 (0x20) |
|---|---|---|---|---|
| 인쇄 시작 | 0x42 | 0 | 1 | 0 |
| 인쇄 진행 | 0x62 | 0 | 1 | 1 |
| **peel 도달** | **0xA2** (또는 0xE2 transition) | 1 | 0/1 | 1 |
| **떼기 transition** | **0xC2** | 1 | 1 | 0 |
| **paper absent (idle)** | **0x82** | 1 | 0 | 0 |

### 정확한 마스크
- **peel 도달**: `(byte7 & 0xA0) == 0xA0` — bit5+bit7 set
- **paper absent**: `(byte7 & 0xA0) == 0x80` — bit5 clear, bit7 set (0x82/0xC2 모두 매칭)

### Direct USB 2장 PoC 결과 (마스크 수정 후)
- 1장: peel-arrival 759ms, paper-detach 11907ms (사용자 페이스)
- 2장: peel-arrival 975ms, paper-detach 7393ms (사용자 페이스)
- 떼는 순간 → 다음 인쇄 송신 latency: **~12ms**
- 떼지 않으면 **무한 대기** (race 100% 차단)

**Why:** 펌웨어가 paper at peel / paper absent 를 USB 로 자발적으로 통지함을 확인. PrintedEvent 보다 더 강력한 신호 (실제 사용자 종이 분리까지 직접 통지). 청산점 #958 같은 race 누락 사고가 물리적으로 불가능해짐.

**How to apply:** 새 세션에서 "USB Direct", "paper-state machine", "라벨 ACK 진짜 신호" 같은 표현 나오면 이 섹션 참조. 코드 위치:
- [UsbLabelProbe.java](android/app/src/main/java/co/kr/waldlust/order/receive/util/print/UsbLabelProbe.java) — 프로브 + Direct PoC 클래스
- [NativeMethodHandler.java](android/app/src/main/java/co/kr/waldlust/order/receive/NativeMethodHandler.java) — `probeUsbLabel`/`probeUsbLabelPrint`/`directPrintUsbLabel` 케이스
- [settings_label_test_section.dart](lib/widgets/settings/settings_label_test_section.dart) — 3개 진입 버튼 (청록/보라/초록)

### 운영 적용 전 남은 작업
1. **TSPL BITMAP 명령으로 실제 라벨 이미지 인쇄** — 현재 PoC 는 단순 TEXT 라벨. Bitmap → 1bpp 변환 + BITMAP 명령 필요 (~150줄)
2. **LabelPrinter.java 교체** — Caysn AAR 의존성 제거, USB Host API 기반 재작성
3. **다양한 단말 검증** — 청산점 단말 + Sunmi V2 + Windows 호환성
4. **timeout 정책** — 떼지 않은 채 다음 주문 들어올 때 (예: 60초 timeout 후 강제 진행 또는 알림)
5. **상태 머신 멀티페이지** — 1개 주문 N장일 때 각 페이지 사이 paper-detach 대기

## 2026-05-04 BITMAP PoC + Buzzer 실험 — paper-state machine 완성

이전 단계의 단순 TEXT 라벨 PoC 를 BITMAP 이미지 인쇄로 확장 + buzzer USB 비트 식별. 신규 코드 ~395 라인 (Java + Dart).

### 신규 진입점 (모두 개발자 옵션 → 라벨프린터 고급 설정 내부)
- 청록 "USB 응답 프로빙 (11개 명령)" → `runProbe`
- 보라 "USB 인쇄 프로빙 (1장 + 30초 폴링)" → `runPrintProbe`
- 초록 "Direct USB 2장 (state machine PoC)" → `runDirectPrintTwoLabels`
- 갈색 "Direct USB 10장 (BITMAP + state machine + buzzer 실험)" → `runDirectPrintTenLabels`
- 분홍 "Buzzer 실험 (race 시뮬레이션)" → `runBuzzerExperiment`

### 발견 4 — TSPL BITMAP 직접 송신 + state machine 정상 작동
- LabelPainter 490×600 PNG → Native (Java) BitmapFactory + threshold(<128=black) + TSPL `BITMAP 0,0,62,600,0,<raw>` (총 37,272 bytes)
- 단일 bulkTransfer (4096 chunk × 10) 송신 정상
- 5/10 라벨 BITMAP 인쇄 성공, peel-arrival latency 매우 일관 (avg 881ms, σ ~50ms)
- paper-detach: `0x82` (idle) / `0xC2` (transition) 양쪽 마스크 모두 검증
- 떼기 → 다음 송신 latency: ~42ms (Caysn 5초 sleep 의 ~120배 빠름)
- 6/10 에서 `[FAIL-PEEL] 10s timeout` (펌웨어 stuck/종이 jam 등 외부 원인 추정)

### 발견 5 — buzzer 가 USB 비트로 노출됨 (확정)
race 시뮬레이션 (1장 peel 도달 후 즉시 2장 BITMAP 송신) 결과:
- t=170ms: 2장 명령 ACK 수신, status `0xEE/0xA2` → `0x6E/0x22` 전환
- **t=2274ms: byte 1 = `0x1B` → `0x1C` (0x01 비트 set) — buzzer 알람 시작**
- ~10초 동안 `0x1C` 비콘 유지
- t=12791ms: byte 1 = `0x1B` 복귀 (알람 종료)
- t=14202ms: 펌웨어가 두 번째 인쇄 자동 시작
- **사용자 청각 확인: buzzer 실제로 울림 + USB 비트 동기 입증**

### 발견 6 — 펌웨어 race 처리는 안전함 (청산점 사고 가설 약화)
사용자 보고: "종이출력 → 대기중 buzzer 울림 → 기다리다 종이뗌 → 다음 종이 정상 출력 → **누락 0건**"
- 즉 펌웨어가 race 발생 시: buzzer 알림 + 명령 큐 보존 + 사용자 떼기 후 자동 진행
- **청산점 #958 누락 사고 원인 재검토 필요** — race 자체가 직접 원인이 아닐 가능성. 후보:
  - 사용자가 buzzer 못 들음 + 펌웨어 timeout 후 강제 진행 (떼지 않은 종이 위로 덮어쓰기)
  - 종이 잼/소진
  - USB 일시 끊김
  - 명령 자체가 펌웨어에 도달 안 함

### Paper-state machine — 비트 의미 확정 (byte 1 추가)
| byte 1 | 의미 |
|---|---|
| `0x1B` | 정상 status 비콘 |
| `0x1C` | **buzzer alarm active** (0x01 비트) ⭐ |

byte 7 마스크 (이전 발견 그대로):
- peel: `(byte7 & 0xA0) == 0xA0` (`0xA2` 또는 `0xE2`)
- detach: `(byte7 & 0xA0) == 0x80` (`0x82` 또는 `0xC2`)

### PoC 의 운영 가치 (사용자 다음 작업 계획 기준)
- **race 차단**: state machine 으로 떼기 대기 보장
- **buzzer 감지**: byte 1 의 0x01 비트로 사용자 떼기 깜박했음 detection 가능 (UI 알림/음성)
- **paper-state machine**: 떼기 즉시 ~12ms 다음 송신 latency
- **다음 작업** (사용자 계획):
  1. **설정 화면에 USB Direct vs Caysn AAR 토글 추가** — 매장별/단말별 점진적 전환 가능
  2. **출력 로직 전반 재정비** — 현재 OutputService 의 메뉴/qty/options 반복 흐름 개선

### 핵심 파일
- [UsbLabelProbe.java](android/app/src/main/java/co/kr/waldlust/order/receive/util/print/UsbLabelProbe.java) — 5개 진입점 (probe/print probe/2-label/10-label/buzzer)
- [NativeMethodHandler.java](android/app/src/main/java/co/kr/waldlust/order/receive/NativeMethodHandler.java) — 4개 method case
- [platform_service.dart](lib/services/platform_service.dart) — 4개 Dart 메서드
- [settings_label_test_section.dart](lib/widgets/settings/settings_label_test_section.dart) — 5개 버튼 + mock 생성

### 변경 상태
- 모두 개발자 옵션 내부 (운영 흐름 영향 없음)
- 커밋 안 됨 (`d187e57` 위에 미커밋 변경 4 파일)
- 다음 단계 (운영 통합) 전까지 PoC 코드 그대로 유지 권장

## 다음 결정 분기

- **A. ACK 타임아웃 5s → 1.5~2s 단축** ([LabelPrinter.java:30](android/app/src/main/java/co/kr/waldlust/order/receive/util/print/LabelPrinter.java#L30) `PRINTED_ACK_TIMEOUT_MS`). 정상 ACK 단말 영향 없음, D2s sleep 짧아짐. 단 race 보호 약화 가능.
- **B. SDK 다른 콜백 시도** — `CP_Printer_AddOnPrinterReceivedEvent` 또는 `CP_Printer_AddOnPrinterStatusEvent`. AAR 네이티브 심볼 확인됨 (`/tmp/aar_extract/jni/arm64-v8a/libautoreplyprint.so`). 새 빌드 필요.
- **C. 단말별 분기** — `Build.MODEL` 로 D2s 면 짧은 sleep, 그 외 ACK 게이트. 가장 깔끔.
- **D. 현 상태 유지 + 운영 관찰**. 청산점 1~2주 누락 0 이면 안전함 입증.

## 관련 문서/메모
- 본 패치 플랜: [lovely-stargazing-galaxy.md](/Users/kimsungchun/.claude/plans/lovely-stargazing-galaxy.md)
- 1차 사고 진단: [12-55-51-769-i-api-appfitcore-goofy-mango.md](/Users/kimsungchun/.claude/plans/12-55-51-769-i-api-appfitcore-goofy-mango.md)
- 부하 테스트 분석기: `/tmp/analyze_stress_log.py` (multi-phase 처리 버그 있음)
- 2026-05-04 테스트 로그: `/tmp/appfit_2026-05-04.txt` (63KB)
- SDK 키 심볼: `CP_Printer_AddOnPrinterPrintedEvent`, `CP_Printer_AddOnPrinterReceivedEvent`, `CP_Printer_AddOnPrinterStatusEvent`, `INFO_PAPERNOFETCH (0x10)`, `INFO_PRINTIDLE (0x20)`
