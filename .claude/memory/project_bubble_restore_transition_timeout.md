---
name: project-bubble-restore-transition-timeout
description: T2mini 버블 복귀 5.7초의 원인은 onNewIntent 의 중복 moveTaskToFront. 앱 전환 타임아웃이며 앱 렌더링은 무죄. sysui_action 계측법 포함
metadata: 
  node_type: memory
  type: project
  originSessionId: 8a2d766d-7c99-4687-a5c3-6d72006e8f82
  modified: 2026-08-31T01:01:55.007Z
---

T2mini(Android 7.1)에서 최소화 후 버블 터치 복귀가 5.7초 걸리던 원인은 **`MainActivity.onNewIntent()` 가 이미 진행 중인 앱 전환에 대고 `moveTaskToFront()` 를 한 번 더 부른 것**. 제거 후 5,056ms → 122ms. D3mini(Android 11+)는 같은 코드로도 빠르다 — 신형 OS 가 흡수한다.

**Why:** onNewIntent 가 불렸다는 건 시스템이 이미 태스크 전면화 전환을 시작했다는 뜻이다. 그 상태에서 moveTaskToFront 를 또 부르면 WindowManager 가 새 전환을 prepare 하고, 진행 중이던 전환이 영영 "good to go" 가 되지 못해 5초 `APP_TRANSITION_TIMEOUT` 을 그대로 소진한다. 함께 얹던 `FLAG_SHOW_WHEN_LOCKED|DISMISS_KEYGUARD|TURN_SCREEN_ON` 도 잠금화면 안 쓰는 매장 단말에선 얻는 것 없이 키가드 정책만 끌어들여 같이 제거했다.

**How to apply:**
- **계측법 (정본)**: `adb logcat -b all` 의 `sysui_action` 이 앱 전환을 그대로 불어준다. `[322,N]`=windows_drawn_delay, `[319,N]`=transition_delay, `[320,N]`=reason(**2=WINDOWS_DRAWN 정상 / 3=TIMEOUT**). 322 는 작은데 319 가 5,000 이면 앱이 느린 게 아니라 전환이 막힌 것 — 앱 코드 프로파일링은 헛수고다.
- **대조군 3종을 반드시 뽑을 것**: ①다른 앱(ES 파일탐색기 836ms/reason 2) ②신선 실행=onNewIntent 미경유(69ms/reason 1) ③문제 경로(5,056ms/reason 3). 이 세 개가 있으면 "우리 앱의 특정 경로"까지 한 번에 좁혀진다.
- 전환 정체 구간에서 `dumpsys window` 를 뜨면 `allDrawn=true` 인데도 `mOpeningApps` 가 남아 있는 게 보인다 — 앱은 다 그렸다는 증거.
- `NativeMethodHandler` 의 `bringToFront` 케이스에 같은 안티패턴(moveTaskToFront + startActivity 중복)이 남아 있다. 현재 Dart 호출부가 없어 죽은 경로지만 되살리면 같은 5초를 만난다.

**헛짚은 판별자 (기록용):** `E Layer: rejecting buffer bufHeight=1011 vs front.active.h=1080` 이 인과처럼 보였다. 몰입 플래그에서 `LAYOUT_*` 3종이 빠져 창이 1080↔1011 로 왕복하던 건 사실이고 고칠 값어치도 있었지만(수정 후 거부 1건→0건), **복귀 시간은 5.71초로 미동도 없었다**. 편차 0.01초의 고정값을 보고 타임아웃이라고 판단한 것까지는 맞았는데, 무엇의 타임아웃인지를 로그 한 줄의 그럴듯함으로 단정한 게 실수였다. `sysui_action` 을 먼저 봤으면 한 번에 끝났다.

관련: [[project_ui_perf_audit_2026_07]] · [[project_android_label_warmup]] · [[feedback_concurrent_session_git_state]]
