---
name: reference_sunmi_device_sn_vs_printer_sn
description: Sunmi 프린터 서비스 SN ≠ 단말 SN. T2mini_s 에서 갈리고 D3 MINI 는 같아 안 드러남. 정본은 ro.serialno.
metadata: 
  node_type: memory
  type: reference
  originSessionId: 5922e777-7106-4df2-89d2-229a1c130e43
  modified: 2026-09-04T06:39:48.481Z
---

Android 시리얼 취득 경로가 둘이고 기종에 따라 **다른 값**이 나온다 (2026-09-04 실기기 실측).

| 경로 | T2mini_s | D3 MINI |
|---|---|---|
| 단말 SN = `ro.serialno` = adb 시리얼 = 기기 라벨 = Sunmi 파트너 포털 | `TN11211U40325` | `DE33256H10784` |
| Sunmi `getPrinterSerialNo()` = **프린터 보드** SN | `4308425239384D5305D5FF30` (24자리 칩 UID) | `DE33256H10784` (우연히 동일) |

- **D3 MINI 에서 두 값이 같다는 게 함정.** 그래서 "프린터 서비스가 기기 시리얼을 준다" 는 오해가 코드 주석으로 굳어 있었다. 검증 기기를 D3 하나로 하면 절대 안 드러난다.
- 프린터 서비스 바인딩이 늦으면(최대 1.5초 폴링) 폴백으로 단말 SN 이 나와서 **같은 기기가 실행마다 다른 값**을 기록했다. "값이 두 종류로 관측된다" 는 신고는 우선순위 역전이 아니라 **레이스**를 의심할 것.
- T2mini_s 는 `/proc/cmdline` 에 `androidboot.serialno` 토큰이 **없다**. `getprop ro.serialno`(exec) 단계에서 잡히므로, 0단계 실패만 보고 "이 기기는 시리얼을 못 읽는다" 고 결론내지 말 것.
- 포털/CSV 교차매칭([[project_device_version_alias_audit]])에 쓸 수 있는 값은 **단말 SN 뿐**이다.

**Why:** 관제·대장·로그 캡션이 모두 이 값을 기기 식별자로 쓰는데, 기종마다 다른 축의 값이 섞이면 같은 기기가 두 행으로 갈라진다([[project_appfit_migration_monitoring]] 의 수작업 매칭이 어긋나는 원인).

**How to apply:** 단말 SN 을 먼저 읽고 Sunmi 프린터 서비스는 폴백으로만 쓴다(`NativeMethodHandler.getDeviceSerial`). 이미 캐시된 잘못된 값이 있으면 prefs 키 문자열을 갈아 1회 재조회시킨다. 관련: [[project_label_printer_platform_divergence]], [[reference_rexod_label_printer_signals]].
