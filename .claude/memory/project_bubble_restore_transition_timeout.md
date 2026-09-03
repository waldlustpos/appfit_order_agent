---
name: project-bubble-restore-transition-timeout
description: T2mini 버블 복귀가 느린 원인은 서로 다른 5초 두 개 — ①onNewIntent 중복 moveTaskToFront(수정됨) ②홈키의 stopAppSwitches 5초(OS 정책, 수용·통제실험 확정). 기준은 마지막 홈키 시각, D3mini 무증상, sysui_action 계측법과 반증된 우회안 포함
metadata: 
  node_type: memory
  type: project
  originSessionId: 8a2d766d-7c99-4687-a5c3-6d72006e8f82
  modified: 2026-09-02T23:34:28.132Z
---

T2mini(Android 7.1)에서 최소화 후 버블 터치 복귀가 5.7초 걸리던 원인은 **`MainActivity.onNewIntent()` 가 이미 진행 중인 앱 전환에 대고 `moveTaskToFront()` 를 한 번 더 부른 것**. 제거 후 5,056ms → 122ms. D3mini(Android 11+)는 같은 코드로도 빠르다 — 신형 OS 가 흡수한다.

**Why:** onNewIntent 가 불렸다는 건 시스템이 이미 태스크 전면화 전환을 시작했다는 뜻이다. 그 상태에서 moveTaskToFront 를 또 부르면 WindowManager 가 새 전환을 prepare 하고, 진행 중이던 전환이 영영 "good to go" 가 되지 못해 5초 `APP_TRANSITION_TIMEOUT` 을 그대로 소진한다. 함께 얹던 `FLAG_SHOW_WHEN_LOCKED|DISMISS_KEYGUARD|TURN_SCREEN_ON` 도 잠금화면 안 쓰는 매장 단말에선 얻는 것 없이 키가드 정책만 끌어들여 같이 제거했다.

**How to apply:**
- **계측법 (정본)**: `adb logcat -b all` 의 `sysui_action` 이 앱 전환을 그대로 불어준다. `[322,N]`=windows_drawn_delay, `[319,N]`=transition_delay, `[320,N]`=reason(**2=WINDOWS_DRAWN 정상 / 3=TIMEOUT**). 322 는 작은데 319 가 5,000 이면 앱이 느린 게 아니라 전환이 막힌 것 — 앱 코드 프로파일링은 헛수고다.
- **대조군 3종을 반드시 뽑을 것**: ①다른 앱(ES 파일탐색기 836ms/reason 2) ②신선 실행=onNewIntent 미경유(69ms/reason 1) ③문제 경로(5,056ms/reason 3). 이 세 개가 있으면 "우리 앱의 특정 경로"까지 한 번에 좁혀진다.
- 전환 정체 구간에서 `dumpsys window` 를 뜨면 `allDrawn=true` 인데도 `mOpeningApps` 가 남아 있는 게 보인다 — 앱은 다 그렸다는 증거.
- `NativeMethodHandler` 의 `bringToFront` 케이스에 같은 안티패턴(moveTaskToFront + startActivity 중복)이 남아 있다. 현재 Dart 호출부가 없어 죽은 경로지만 되살리면 같은 5초를 만난다.

**이 버그에 한해 탈출 경로는 무관 (2026-09-02 T2mini_s 실측):** 복귀는 어느 쪽이든 `startActivity` → `onNewIntent` 한 길뿐이다. 수정 전 common 3.0.0+191 은 홈키 5038ms / 최소화 5040ms (둘 다 reason 3), 수정 후 3.0.7+204 는 홈키 100~122ms / 최소화 101~161ms (reason 2). 백그라운드 5초·90초, tap·swipe 차이 없음. 버블은 onPause 후 ~130ms 에 뜬다. 수정 전 빌드는 `D MainActivity: moveTaskToFront success in onNewIntent` 가 찍히므로 **이 한 줄이 어느 빌드인지 판별자**다 — 한 기기에 두 티어 아티팩트를 같은 매장으로 로그인해두면 화면이 동일해 육안 구분이 안 되고 버블도 같은 좌표에 겹친다.

**같은 제스처에 5초가 하나 더 있다 — 홈키의 `stopAppSwitches` (2026-09-02 실측, 미수정·수용 결정):** 위 수정을 다 하고도 **홈키로 나간 직후** 버블을 누르면 느리다. 이건 전환 타임아웃이 아니라 **`APP_SWITCH_DELAY_TIME`(5초)** 이다. 홈키·최근앱키를 처리할 때 `PhoneWindowManager` 가 `stopAppSwitches()` 를 부르고, 그 창 안의 백그라운드 앱 `startActivity` 는 실패가 아니라 `mPendingActivityLaunches` 로 밀렸다가 **홈키+5.00초** 에 실행된다. 판별자는 `W ActivityManager: Activity start request from <uid> stopped`. 실측: 홈키 후 1.7초 터치 → +3.09초 / 3.9초 터치 → +1.05초 / 6.7초 터치 → 차단 없음 113ms. **지연 = 5초 − 경과시간.** 최소화 버튼(`moveTaskToBack`)은 이 잠금을 걸지 않아 언제 눌러도 즉시다 — 두 경로의 차이는 여기서 갈린다.
- 앱 코드로는 못 뚫는다. Android 7 `checkAppSwitchAllowedLocked` 의 면제는 ①`STOP_APP_SWITCHES`(signature|privileged, 일반 앱 불가) ②resumed 액티비티가 같은 uid 뿐이다. 시스템이 대신 쏘게 하는 우회 둘도 막혔다 — **AlarmManager 는 `MIN_FUTURITY` 때문에 "즉시" 예약도 5.005초 뒤에 발화(실측)** 해서 그냥 기다리는 것과 같고, 알림 `fullScreenIntent` 는 화면이 켜진 비잠금 상태에서 액티비티 대신 헤드업으로 대체된다(**이쪽은 AOSP 동작 기반 추론이고 이 기기에서 실측하지 않았다** — 굳이 재도전한다면 여기부터). 알람 우회는 구현·실측·되돌림까지 마쳤으니 **다시 시도하지 말 것**.
- D3mini(13)는 무증상(실기 보고). 규칙 자체는 전 버전 공통이고 달라진 건 면제 목록이다 — 10 의 BAL, 12+ 의 앱전환 3단계(DISALLOW/FG_ONLY/ALLOW)에서 SYSTEM_ALERT_WINDOW·가시 오버레이·포그라운드 서비스가 허용 사유가 된다. 다만 이건 추정이고, D3mini 에서 버블 터치 순간 `logcat | grep -E "BAL_ALLOW|request from .* stopped"` 한 줄로 확정된다(미실행).

**통제 실험으로 확정 (2026-09-03, 두 기기 각 15시행 = 5시나리오 × 3회, 둘 다 mammoth 3.0.7+204):** 위 가설이 수치로 닫혔다. **기준 시각은 앱이 백그라운드로 간 시점이 아니라 "마지막 홈키 시각"** 이고, 복귀 시각은 그 +5.02초로 고정이다.

| 시나리오 | T2mini(7.1) `stopped` | 홈키→복귀 | 체감 지연 | D3mini(13) |
|---|---|---|---|---|
| 최소화(=`moveTaskToBack`), 1s | 0건 | — | **115~134ms** | 47~169ms |
| 홈키, 1s 뒤 터치 | 1건 | **5.014~5.025s** | 3.07~3.09s | 52~65ms |
| 홈키, 3s 뒤 터치 | 1건 | **5.015~5.019s** | 1.06~1.07s | 69~85ms |
| 홈키, 6s 뒤 터치 | 0건 | — | 110~117ms | 74~81ms |
| 홈키→6s→**홈키 재입력**→즉시 | 1건 | **5.017~5.023s**(2번째 홈키 기준) | 4.11~4.14s | 45~86ms |

- **신규 관찰 — 홈키는 누를 때마다 창을 새로 연다.** 이미 런처가 포그라운드여서 아무 전환도 일어나지 않는 홈키조차 `stopAppSwitches()` 를 다시 부른다. "앱이 백그라운드에 오래 있었으니 괜찮다"는 직관이 틀리는 지점이고, 점주가 홈 화면에서 홈키를 습관적으로 한 번 더 누르면 다시 5초를 산다.
- 전 시행 `[320,2]`(WINDOWS_DRAWN) — 5초 ①(전환 타임아웃)의 재발이 아님을 매 시행 확인했다. 319≈322≈체감지연으로 함께 움직인다(①일 때는 322만 작고 319만 5,000).
- **D3mini 는 15시행 전부 `stopped` 0건.** 홈키 후 **0.13초** 만에 터치해도 즉시 복귀 — 잠금을 아예 안 건다. "T2mini(Android 7) 한정" 확정. (`BAL_ALLOW` 로그는 기본 비활성이라 안 찍혔다. 면제 *사유*는 여전히 추정으로 남는다.)
- **계측 함정 — `adb shell input` 의 프로세스 기동 지연이 측정을 오염시킨다.** T2mini 에서 `input keyevent` 는 마커 로그 후 **0.80초**, `input tap` 은 **0.95초** 뒤에야 실제 이벤트를 만든다(D3mini 는 ~0.13초). 그래서 마커 시각을 터치 시각으로 쓰면 안 된다. 해법 둘: ①**`stopped` 로그 시각이 곧 `startActivity` 호출 시각** 이므로 이것을 터치 시각으로 쓴다 ②홈키 시각은 `am_pause_activity`(앱→런처)로 관측한다. 단 시나리오 4의 두 번째 홈키는 전환이 없어 pause 로그가 안 남으므로, 마커 + K(0.80초)로 보정해야 한다 — 이 보정을 빼면 5.82초로 읽혀 "5초가 아니네"라는 오판을 부른다.
- 재현 스크립트는 `bubble_probe.sh`(탈출키·대기초·홈키재입력을 파라미터로 받아 기기 내에서 원자 실행 후 로그 파싱). 시나리오 1은 앱바 최소화 버튼 대신 **BACK 키로 대체 가능** — `PopScope`→`moveToBackground`→`activity.moveTaskToBack(true)` 로 같은 네이티브 경로를 타는 것을 `I ActivityManager: moveTaskToBack:` 로그로 확인했다(Flutter 위젯이라 버튼 좌표 자동 추출이 불안정한 문제를 피한다). 버블 좌표는 앱을 백그라운드로 보낸 뒤 `dumpsys window windows` 에서 액티비티명 없이 **패키지명만 있는 창**의 `mAttrs` 위치+크기로 얻는다(T2mini `(1590,640) 115x115` / D3mini `(414,66) 80x80`).
- **결론: 수용.** 코드 변경 없음. 운영상 회피책은 "앱을 잠시 내릴 땐 앱바의 최소화 버튼을 쓸 것" 하나뿐이다.

**헛짚은 판별자 (기록용):** `E Layer: rejecting buffer bufHeight=1011 vs front.active.h=1080` 이 인과처럼 보였다. 몰입 플래그에서 `LAYOUT_*` 3종이 빠져 창이 1080↔1011 로 왕복하던 건 사실이고 고칠 값어치도 있었지만(수정 후 거부 1건→0건), **복귀 시간은 5.71초로 미동도 없었다**. 편차 0.01초의 고정값을 보고 타임아웃이라고 판단한 것까지는 맞았는데, 무엇의 타임아웃인지를 로그 한 줄의 그럴듯함으로 단정한 게 실수였다. `sysui_action` 을 먼저 봤으면 한 번에 끝났다.

관련: [[project_ui_perf_audit_2026_07]] · [[project_android_label_warmup]] · [[feedback_concurrent_session_git_state]]
