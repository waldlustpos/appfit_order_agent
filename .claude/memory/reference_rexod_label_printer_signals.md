---
name: reference_rexod_label_printer_signals
description: "REXOD RXLA-561(Caysn SDK) 신호 실측 정본 — PAPERNOFETCH는 정상 동작, QueryPrintResult는 떼기를 안 기다림, GetPrinterPrintedInfo pageId는 판정 불가, 펌웨어 보류 실재."
metadata:
  type: reference
---

2026-08-03 D2s_KDS_STGL(`DK1925AJ40349`) + REXOD RXLA-561 실기기 측정. 이전 메모들의 추측을 대체하는 **실측 정본**.

기기: VID `0x0FE6` / PID `0x811E`, "Virtual PRN (Manufacture)".

## 확정된 신호 동작

**`INFO_PAPERNOFETCH`(0x20)는 정상 동작한다.** 매 인쇄마다 전이가 찍힌다 — 라벨이 peel에 도달하면(인쇄 시작 ~0.83초 후) true, 사용자가 떼면 false. ⚠️ **"이 기기에서 이 비트가 안 뜬다"는 통념은 틀렸다.**

**`CP_Pos_QueryPrintResult`는 떼기를 기다리지 않는다.** 인쇄 엔진 완료 시점에 true 를 반환한다(총 ~1.1초). `PAPERNOFETCH=true`(안 뗀 상태)에서도 `출력끝`이 정상적으로 난다.

**펌웨어 보류는 실재한다.** 앞 라벨이 안 떼어져 있으면 다음 `PagePrint`를 물고 있다가 떼는 순간 인쇄한다. 소요시간 = 떼기까지 걸린 시간 + ~1.1초. **19.2초까지 관측**. 프로덕션 로그의 2~8초 지연들이 전부 이것.

**`CP_Printer_GetPrinterPrintedInfo`의 pageId는 인쇄 여부 판정에 못 쓴다.** 인쇄 도중에는 갱신되지 않고 *다음* 인쇄 시작 시점에야 반영된다(`pg=0→0`, `0→0`, `1→1`). 따라서 `pageIdBefore != pageIdAfter` 판정은 항상 false. 진단 표시용으로만 유지 중.

## 왜 오판했었나 — 관찰 수단의 부재

`INFO_PAPERNOFETCH`는 `QueryPrintResult`가 **실패했을 때만** 로그(`떼기대기`)에 남는 구조였다. 즉 평소 동작 여부를 확인할 방법이 아예 없었고, "실패 로그에 안 보임 = 비트가 안 뜸"으로 잘못 결론냈다.

**Why:** 동작을 관찰할 수단이 없는 가드는 "안 걸린 것"과 "고장난 것"을 구분할 수 없다. 라벨/프린터 가드를 만들거나 진단할 때 먼저 **그 신호가 살아 있는지 볼 수 있게** 만들 것.

**How to apply:** 지금은 [LabelPrinter.java](android/app/src/main/java/co/kr/waldlust/order/receive/util/print/LabelPrinter.java) `statusCallback`이 PAPERNOFETCH 전이를 **logcat 전용**으로 찍는다(파일 로그는 라벨당 2줄 증가를 피해 제외). 확인 명령:
```
adb -s DK1925AJ40349 logcat -v time -s "LabelPrinter"
```
`PAPERNOFETCH → 안뗌(라벨 대기중)` / `→ 떼어짐/없음` 전이를 본다.

관련: [[project_label_ack_timeout_duplicate]](이 실측이 나온 사고), [[project_label_ack_patch]]·[[project_label_inter_label_delay]](이 파일이 정정하는 구 메모)
