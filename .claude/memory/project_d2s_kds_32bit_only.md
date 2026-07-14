---
name: project-d2s-kds-32bit-only
description: D2s_KDS 는 커널까지 32비트 전용(zygote32/linker64 부재) — armeabi-v7a 빼면 설치 불가. 원인은 MT6580 BSP 계보. SoC 스펙·웹리서치로는 못 잡고 getprop 실측으로만 드러남.
metadata: 
  node_type: memory
  type: project
  originSessionId: 4a1baabb-3bf6-427f-9e70-c73ed846b424
---

**D2s_KDS_STGL 은 커널부터 32비트 전용이다.** `ro.zygote=zygote32`, `abilist64` **비어 있음**, `uname -m=armv8l`(ARMv8 코어를 AArch32 로 실행), `/system/bin/linker64`·`app_process64` **부재**, `/vendor/lib64` 0개. 64비트를 "끈" 게 아니라 **실행 인프라가 이미지에 없다**.

→ 릴리즈 APK 의 `abiFilters` 에서 **`armeabi-v7a` 를 빼면 `INSTALL_FAILED_NO_MATCHING_ABIS`** (실측 확인). 나머지 기기(D3 MINI, T2mini_s)는 `zygote64_32`.

**왜**: RAM 절약이 아니다(3.79GB, `low_ram` 미설정). 하드웨어도 64비트가 맞다(RK3566 = Cortex-A55, `CPU part 0xd05`). 원인은 **BSP 계보** — 모든 fingerprint 가 `alps/full_rlk6580_we_c_m/...` 인데 `alps`=MediaTek BSP 빌드시스템, `rlk6580`=**MT6580**(Cortex-A7, 64비트 불가능한 칩)이다. SUNMI 가 MT6580 제품의 device makefile 을 물려받아 RK3566 이미지를 만들었고 32비트 구성이 화석처럼 남았다. BSP 베이스 2022-11, 보안패치 2024-03 에 동결 → **앞으로도 32비트일 가능성 높음**.

**Why(작업 교훈)**: 2026-07-14 APK 감축에서 D3 MINI·T2mini_s 두 대만 실측하고 arm64 전용으로 갔다가 D2s_KDS 를 꽂아보고서야 잡았다. (1) "가장 구형인 T2mini_s 가 64비트면 나머지도" 라는 추론과 (2) SUNMI 라인업 웹 리서치("D2s=Cortex-A55=64비트")가 **둘 다 같은 방향으로 틀렸다**. SoC 스펙시트는 OEM 의 유저스페이스 빌드 결정을 알려주지 않는다.

**How to apply**: 틀리면 기기가 설치 불가가 되는 축소 결정(ABI/ARCH)은 fleet **전수를 `adb shell getprop ro.product.cpu.abilist64` 로 실측**하기 전엔 내리지 않는다. 값이 비면 32비트 전용. 표본 2대 + 웹리서치 + 연식추론의 일치는 근거가 못 된다. 부수 제약: KDS 는 32비트 프로세스라 주소공간 2~3GB — 이미지/캐시 크게 쥐면 D2s_KDS 에서만 OOM. 정본은 `docs/BUILD.md` "Android APK 크기 정책".
