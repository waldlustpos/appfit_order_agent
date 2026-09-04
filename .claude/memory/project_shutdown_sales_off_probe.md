---
name: project-shutdown-sales-off-probe
description: 전원종료 감지→영업OFF 구현·실기검증 완료(T2mini·D3mini). "종료 시 네트워크 끊김" 기존 진단은 반증됨. 실측 도구 함정 4건
metadata: 
  node_type: memory
  type: project
  originSessionId: 331ebaef-089b-482d-8ec8-83ab6463c762
  modified: 2026-09-04T04:29:59.322Z
---

레거시 kokonut 의 "정상 전원종료 감지 → 영업 OFF" 를 AppFit 에 이식(2026-09-04). 브랜치 `feat/label-category-subinfo-settings`.

**구현·실기검증 완료.** 두 기기 통과, 기기 분기 코드 0줄:

```
D3 MINI  sdk=33  salesOff=ok(97ms)  totalMs=101   MMTH00084
T2mini_s sdk=25  salesOff=ok(103ms) totalMs=107   MMTH00101
```

산출물: `ShutdownSalesOffBridge.java`(우선순위 999 + goAsync + Dart 3초 캡/5초 워치독, **실패 시에만** DNS·TCP post-mortem) / `MainActivity.appendLogToFileSynced`(fsync) / `lib/services/shutdown_signal_service.dart` / `lib/providers/sales_off_provider.dart`(detached 복원, MyApp 에서 watch) / 단위테스트 7건. 서버측 dead-man switch 제안서는 `docs/STORE_AUTO_CLOSE.md`.

**`setPriority(999)` + `goAsync()` 는 제거하면 안 된다(load-bearing).** 운영 로그 순서가 `salesOff=ok` → `소켓 종료` → `Online: false` 다 — 네트워크는 우리 리시버가 끝난 **직후** 죽는다. 마진이 넉넉해서 되는 게 아니라 ordered broadcast 를 먼저 잡고 붙들고 있어서 된다. Wi-Fi 강제 종료는 실재한다("가설 A 기각"은 과했음).

종료 후 네트워크 상실로 앱이 복구 시퀀스(소켓 재연결·폴링·알림음·버블)를 도는 것은 **유지하기로 결정**(2026-09-04). Sentry 오염은 없음 — `connectionError` 는 core `isTransientNetworkError` 로 breadcrumb 처리된다.

설계 주의 2가지:
- `KEY_ORDER_ON` 은 **건드리지 않는다** — 다음 기동 때 home_screen 이 그 값으로 서버 상태를 복원하므로, false 로 덮으면 재부팅 후 매장이 닫힌 채 남는다.
- KDS 가드 판정은 provider 가 아니라 영속 플래그(getKdsMode/getKdsAcceptOrders)로. 프로세스가 죽는 중엔 provider 그래프를 믿을 수 없다.

**핵심 반증**: "D3mini 는 전원종료 시점에 인터넷이 끊겨 API 가 안 나간다"는 기존 진단은 **틀렸다.** D3MINI(A13/SDK33) 실측 2회 재현:

```
[SHUTDOWN_BCAST] model=D3 MINI sdk=33 net=wifi/internet=true,validated=true
  dns=ok:15.165.229.24(40ms) tcp=ok(12ms) dart=ok:true(1ms) totalMs=58
[SHUTDOWN_BCAST] ... dns=ok(14ms) tcp=ok(23ms) dart=ok:true(1ms) totalMs=44
```

브로드캐스트 도달 O / 네트워크 validated=true / TCP 443 성공 / **Dart MethodChannel 왕복 1ms**(엔진 생존 = 본구현 전제 성립). AOSP ShutdownThread 가 라디오를 브로드캐스트 **이후에** 내리는 것과 일치. 기존 오진의 원인은 레거시가 쓴 deprecated `getActiveNetworkInfo()/isConnectedOrConnecting()` 로 추정.

`[ON_DESTROY]` 는 **A7·A13 둘 다 종료 시 안 찍힌다** — onDestroy 는 호출되지 않는다. 유일한 훅은 ACTION_SHUTDOWN 이다(레거시가 onDestroy 에도 걸어둔 것은 전원종료에는 무효였다).

**실측 도구 함정 4건** (다음에 또 밟기 쉬움):
1. `adb reboot` 는 adbd 가 `sys.powerctl` 을 직접 써서 **프레임워크 종료 시퀀스를 건너뛴다** → ACTION_SHUTDOWN 안 나감. 올바른 도구는 `adb shell svc power reboot`(PowerManagerService→ShutdownThread).
2. `adb shell am broadcast -a android.intent.action.ACTION_SHUTDOWN` 은 **shell uid(2000) 권한 거부**. protected broadcast 발송 allowlist 에 SHELL_UID 없음. 선검증 불가.
3. T2mini(A7)는 shell 에 `android.permission.REBOOT` 이 없어 `svc power reboot` 도 SecurityException → **A7 은 물리 전원버튼 외에 방법 없음**. A13 은 shell 에 권한 있음.
4. 온디바이스 `grep` 이 로그파일(UTF-8 BOM)을 통째로 스킵한다. 반드시 `adb shell cat ... | grep` (호스트측)로 볼 것. [[reference-raw-control-char-breaks-grep]] 와 같은 계열.

**운영상 주의**: 리시버는 MainActivity 수명에 묶여 있다(Dart 엔진 필요). 부팅 후 앱이 서비스만으로 헤드리스 기동하면 등록 0이고 전원종료 훅도 없다.

**별건(미처리)**: D3mini 기동 시 `ForegroundServiceDidNotStartInTimeException` 로 프로세스가 죽는 것을 2회 관측. 이번 변경과 무관한 기존 `checkAndStartForegroundService` 경로지만, 이 기능과 맞물리면 전원종료로 닫아놓고 재기동이 죽어 **매장이 닫힌 채 남는다**.

계획 문서: `C:\Users\Administrator\.claude\plans\kokonut-order-agent-v2-majestic-goblet.md`
