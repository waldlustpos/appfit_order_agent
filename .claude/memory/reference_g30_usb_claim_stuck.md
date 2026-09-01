---
name: reference-g30-usb-claim-stuck
description: G30 이 exclusive claim 실패로 고착되면 코드가 아니라 프린터 전원 재인가가 해결. usblp 바인딩·SDK force=true 는 정상 상태에서도 관측되므로 범인 증거가 아니다.
metadata:
  type: reference
---

BIXOLON G30 라벨 인쇄가 아래 로그로 **100% 실패**하는 상태가 있다. 2026-09-01 D2s_KDS_STGL
(DK1925AJ40349)에서 관측.

```
I/BixolonPosDriver: [warmup] 연결불가 [This device cannot be claimed for exclusive access.]
I/BixolonPosDriver: [TEST]   연결불가 [This device cannot be claimed for exclusive access.]
```

## 해결: 프린터 전원 재인가

USB 재열거로 풀린다. **코드를 고칠 일이 아니다.** 앱 재시작·재설치로는 안 풀린다
(같은 증상이 앱 재시작 2회를 건너 지속되는 것을 확인).

## ★ 범인 증거로 착각하기 쉬운 것 3가지

고착 상태를 조사하면 아래가 전부 관측되는데, **정상 동작 시에도 동일하게 관측되므로
원인이 아니다.** 이걸 근거로 코드를 고치면 헛수고한다 (실제로 두 번 헛짚었다).

1. **커널 `usblp` 가 인터페이스를 점유** — `/sys/bus/usb/drivers/usblp/3-1:1.0` 심볼릭 링크
   존재. G30 이 USB 프린터 클래스(intf0 cls=7 sub=1 proto=2)를 노출하므로 커널이 항상
   자동 바인딩한다. 그런데 BIXOLON SDK 는 `claimInterface(intf, force=true)` 로 호출하므로
   (`libcommon` `USBService$ConnectionCallable` 바이트코드에 `iconst_1` 확인) usblp 는
   원래 떨어져 나가야 정상이다.
2. **`UsbProtectControlService: allow uid:1000 pid:417 to use G30`** — Sunmi 시스템 서비스가
   system_server 에게 허용하는 로그. 상시 찍힌다.
3. **`UsbReceiptPrinter` 선점** — 아니다. `discover: no receipt printer candidate found` 를
   확인할 것. (다만 [[project-bixolon-xd5-removal-residue]] 참조 — G30 을
   `isLabelPrinter` 에서 제외하는 건 별개로 필요했고 2026-09-01 에 반영했다.)

## 진단 순서 (다음에 같은 증상이 나오면)

1. **먼저 프린터 전원 재인가 후 재시도.** 이걸 안 하고 코드부터 보면 하루 날린다.
2. 그래도 실패하면 `adb logcat | grep -i "UsbReceiptPrinter\|BixolonPosDriver"` 로
   위 3번(영수증 경로 선점) 배제.
3. 코드 회귀 의심은 **마지막**. 판정법: 마지막으로 동작하던 커밋과
   `git diff <ref> -- android/` 를 떠서 USB 경로에 실제 차이가 있는지 본다.
   차이가 없으면 환경 문제다 — 더 파지 말고 1번으로 돌아갈 것.

## 일반화

증상이 결정론적(100% 재현)이라고 해서 원인이 코드인 것은 아니다. 하드웨어 상태 고착도
100% 재현된다. **"코드 차이가 없는데 증상이 있다" 는 환경을 가리키는 신호**이지,
더 깊이 파라는 신호가 아니다.

관련: [[project-bixolon-g30-40mm-layout]] · [[project-android-label-warmup]]
