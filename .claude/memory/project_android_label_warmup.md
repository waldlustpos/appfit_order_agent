---
name: project-android-label-warmup
description: "부팅 후 첫 라벨 \"연결오류\" 원인=USB 권한 미보유(A 확정)+warm-up 부재. 실기기 검증 완료 (2026-08-10)"
metadata: 
  node_type: memory
  type: project
  originSessionId: 6042ee9b-9d49-4c06-80fb-98a3ec52faf4
  modified: 2026-08-10T01:29:22.938Z
---

부팅 후 앱 최초 실행 시 **첫 주문 라벨만** `실패 [연결오류] (114ms)` → 1.5초 뒤 재시도 성공.
원인은 레이스나 프린터 결함이 아니라 **USB 포트를 여는 시점이 첫 인쇄 순간**이라는 구조:
`LabelPrinter.init()` 은 상태 콜백만 등록하고, Android `checkConnection()` 은 `getDeviceList()`
매칭으로 "꽂혀 있다"만 판정할 뿐 **포트를 열어보지 않는다.** Windows 는 `main.dart` 에서
`WindowsLabelRouter.warmupOpen()` 으로 이미 같은 일을 하고 있었고 **Android 에만 없었다.**

**Why:** 플랫폼 간 비대칭이 곧 결함의 위치였다. "Windows 에는 있는데 Android 에는 없는 것"
을 먼저 대조했으면 로그 분석보다 빨리 도달했다. 프린터 이슈에서 [[project-label-printer-platform-divergence]]
와 같은 교훈 — 다만 저기서는 비교가 교란 변수였고, 여기서는 비교가 정답이었다.

**How to apply:** 브랜치 `fix/network-degradation-resilience` 에 구현 완료(미커밋).
`LabelPrinter.warmup(mode)` + `NativeMethodHandler.warmupLabelPrinter` + Dart
`label_warmup_starter.dart`(StartupProbeScheduler 재사용, 백오프 3/8/20/60초).
인쇄 경로는 한 줄도 안 건드림 — `label_print_retry.dart` 의 "retryable 일 때 정확히 1회"
불변식 보존([[project-label-ack-timeout-duplicate]]).

**원인은 (A) USB 권한 미보유로 확정** (D2s_KDS_STGL / PAIK00002 실기기, 앱 설치+재부팅 후):
`권한=없음`(open 3포트 전부 실패) → 권한 요청 → 3.3초 뒤 `권한=있음` → open 성공 →
첫 주문 라벨이 `#1` 에서 연결오류 없이 성공(1062ms, 프린터응답 919ms — 기존 정상치와 동등).
직접 원인은 Caysn SDK 내부 `NZUSBClientIO.Open` 이 `requestPermission` 을 던지고 **기다리지
않고** `openDevice` 로 진행하는 것 — 권한 없는 세션의 첫 open 은 반드시 실패한다.
(수정 전 증상의 "1.5초 뒤 재시도는 성공" 도 이걸로 설명된다.)

**주의 — 검증 단말은 Android 11(D2s_KDS_STGL).** SDK 의 `PendingIntent flags=0` 이 예외가
되는 것은 **OS 12+ 단말에서만**이고 targetSdk 35 여도 OS 11 에는 그 검사 자체가 없다. 따라서
이 기기에서는 SDK 내부 요청도 동작했고, 승인을 촉발한 것이 SDK 요청인지 새로 넣은
`UsbPermissionHelper` 요청인지는 **로그로 구분되지 않는다.** 공용 헬퍼의 확실한 가치는
Android 12+ 단말 — 거기서는 SDK 요청이 무효라 이것이 유일한 요청이 된다.

**Why (진단 설계 교훈):** 증상만 보면 "1.5초 뒤 되니까 타이밍 문제" 로 읽히지만, 실제로는
관측 불가능한 상태(권한)가 조용히 빠져 있었다. `권한=` `장치=` `시도=[포트별 ms]` 를 한 줄에
찍는 것만으로 두 가설이 배포 1회에 갈렸다. 관찰할 수 없는 상태는 없는 것과 같다
([[reference-rexod-label-printer-signals]] 와 같은 원칙).

**권한 승인은 무인(無人)이다** — 운영자가 다이얼로그를 누르지 않았는데 3.3초 만에 붙었다
(device_filter.xml attach 승계 / 기존 "항상 허용"). 즉 매장 배포에 사람 개입이 필요 없고,
`requestPermission` 호출이 그 자동 승인을 **촉발하는 방아쇠** 역할만 한다. 첫 백오프 3초가
이 3.3초와 우연히 잘 맞았다 — 줄일 이유도, 권한 폴링 대기를 넣을 이유도 없다.
**재현은 매번 기기 재부팅 필요** — `hPrinter` 가 프로세스 전역 static.

회귀 확인 완료: 첫 인쇄가 idle 게이트를 새로 통과해도 소요시간 증가 없음. 인쇄 경로에
`[CONNECT] 인쇄` 로그 0줄 = warm-up 핸들 재사용·모드 일치 실증.

진단 로그 표기 주의: `reason` 은 hPrinter NULL 을 modeChanged 보다 먼저 봐야 한다. 안 그러면
세션 최초 연결이 `모드변경 0→1` 로 찍힌다(초기 `currentAutoReplyMode`=0 vs 실제 모드 1).
