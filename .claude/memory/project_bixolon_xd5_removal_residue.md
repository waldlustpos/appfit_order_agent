---
name: project-bixolon-xd5-removal-residue
description: XD5-40d 제거 후 남은 BIXOLON 자산은 전부 G30 소유 — libbxl_common.so / libcommon jar / com.bixolon.pdflib 스텁. proguard com.bixolon.** keep 은 release 전용 load-bearing. 버저 SDK 조사는 G30 에 승계, 하드웨어 결론은 미승계.
metadata:
  type: project
---

2026-09-01, BIXOLON XD5-40d 라벨프린터 지원을 종료했다. 지원 대상은 **REXOD RXLA-561
+ BIXOLON G30** 2종(Caysn D2/D3 는 화이트리스트에만 잔류). 이 노트의 주제는 지운 기종이
아니라 **"지웠는데 안 지워진 것들이 왜 G30 소유인가"** 다.

## 삭제 금지 — XD5 잔재처럼 보이지만 G30 현역

| 자산 | 근거 | 지웠을 때 |
|---|---|---|
| `jniLibs/*/libbxl_common.so` (arm 2종 16.5MB 출하) | `bxl_common` loadLibrary 문자열이 G30 의 `BXLConfigLoader.class` / `jpos/POSPrinter.class` 안에 있다. **커밋 `cb56a37`(G30)이 이 so 를 교체까지 했다** — 상속이 아니라 현역 | `UnsatisfiedLinkError`, catch 불가 |
| `android/app/libs/libcommon_V1.4.4.jar` | UPOS jar 24개 클래스가 `com/bixolon/commonlib` 참조 | G30 즉사 |
| `android/app/src/main/java/com/bixolon/pdflib/**` (스텁 4개) | `POSPrinterService114` + `POSPrinterBaseService.validateDevice()` 가 참조. **그 `catch (Exception)` 은 `NoClassDefFoundError`(Error)를 못 잡는다** | `ensureConnectedLocked` → `setDeviceEnabled(true)` 크래시 |
| `proguard-rules.pro` 의 `-keep`/`-dontwarn com.bixolon.**` | 남은 커버 대상은 `commonlib`(공유) + `pdflib`(스텁) 둘뿐 — 주석이 "XD5 Label SDK" 라고 오도했다 | **release 에서만** G30 사망 |

`device_filter.xml` 의 `<usb-device vendor-id="5380" />` VID-only 엔트리도 유지 — G30 의
attach 권한 승계 경로다. Dart 표시 판정(`labelPrinterModelName`)·드라이버 선택
(`isG30Attached`)은 PID/제품명까지 보는 좁은 조건이며, **목적이 달라 갈라져 있는 것이 정상**이다.

## proguard 함정

`com.bixolon.**` keep 은 **debug 는 멀쩡하고 release 에서만, 그것도 G30 connect 경로에서만**
터지는 종류다. macOS 개발기에서는 재현조차 안 되고 발현 장소는 매장이다. 좁히고 싶으면
release 빌드 + G30 실기기 스모크를 먼저 통과시킬 것. 잔여 커버리지 이득은 수십 KB 라
서두를 이유가 없다.

## ★ 일반화 — 기종 지원 종료의 삭제 경계는 벤더가 아니라 심볼이다

"BIXOLON = XD5" 로 묶어 지웠으면 위 4개가 전부 오삭제 후보가 됐고, 그중 3개는
**release 에서만 · 특정 하드웨어 경로에서만** 터진다. 삭제 전 확인 질문은
"이 벤더 기종을 쓰는가" 가 아니라 **"이 심볼을 참조하는 bytecode 가 있는가"** 여야 한다.
실제로 이번 판정은 jar bytecode 상수 풀 스캔(`loadLibrary` 문자열, 패키지 참조 카운트)으로
했고, 파일 히스토리(누가 언제 추가했나)는 **정반대 결론으로 유도했다** — `libbxl_common.so`
는 XD5 커밋이 들여왔지만 지금은 G30 커밋이 교체한 G30 자산이다.

같은 이유로 **APK 크기 이득을 기대하면 안 된다**. XD5 노트가 "APK +15MB" 를 XD5 비용으로
기록해 뒀지만 그 15MB 는 지금 전부 G30 비용이다. 실제 회수는 jar 65KB + dex 수십 KB
(≈0.2%). 이 작업의 이득은 소스 ~2,100줄과 라우팅 분기 하나다.

## 승계된 결론 (구 XD5 노트에서 이관)

- **사전 이진화 임계 210** — SDK 자체 이진화가 저임계로 동작해 AA 얇은 글자·1px 구분선·
  black26(≈189)이 소실된다. G30 이 `BixolonPosDriver.BINARIZE_THRESHOLD` 로 승계했고
  **그 javadoc 이 레포에 남은 유일한 근거 사본**이다(Windows 복제본
  `label_bmp_converter.dart`·`bxllapi_constants.dart` 는 함께 삭제됨). BXLPAPI 이식자는
  재유도하지 말고 그대로 가져갈 것.
- **BIXOLON SDK 에 buzzer API 는 없다** — `libcommon`(135클래스)·`libbxl_common.so` 심볼
  전수 조사 결과 0건. **두 자산 모두 G30 과 공유하므로 이 조사는 G30 에도 유효하고
  재조사가 불필요하다.**
- 단 XD5 의 **"버저 하드웨어 미탑재" 결론은 승계되지 않는다** — 그건 개별 하드웨어
  사실이고 G30 실기기 확인은 아직 없다. `libbxl_common.so` 펌웨어 다운로더 테이블에
  `Buzzer Driver image` 섹션이 있다는 건 제품군 정황일 뿐이다.
  → **SDK 조사 = 승계 / 하드웨어 실측 = 미승계**. 이 구분을 뭉개지 말 것.

## 의도적으로 남긴 것

`lib/services/label_printer/windows/windows_label_router.dart` 는 백엔드가 하나뿐인 채로
남겼다. G30 Windows 이식(BXLPAPI — Android UPOS 와 별도 명령셋)이 착수되면
`connectedModelName`/`printPng`/`warmupOpen` 세 지점에 두 번째 분기가 들어온다.
"무의미한 간접성" 으로 보고 접지 말 것 — 접으면 호출부 6곳을 다시 뒤집어야 한다.

관련: [[project-bixolon-g30-40mm-layout]] · [[reference-rexod-label-printer-signals]] ·
[[project-store-printer-topology]] · [[project-label-printer-platform-divergence]]
