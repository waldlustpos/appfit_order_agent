---
name: project-alarm-audio-focus-bgm
description: 주문 알림음이 매장 BGM을 영구 정지시키던 원인(audioplayers 기본 AUDIOFOCUS_GAIN)과 진단 함정
metadata: 
  node_type: memory
  type: project
  originSessionId: 7a906c85-8c08-4085-b013-eceb5a456b5e
  modified: 2026-08-31T00:24:01.377Z
---

주문 인입 알림음이 매장 배경음악을 끊는다는 신고(2026-08-31)의 원인은 `SoundService._player`
(`lib/core/orders/sound_service.dart`)에 `AudioContext` 가 한 번도 설정되지 않아 audioplayers
기본값인 **`AUDIOFOCUS_GAIN` + `USAGE_MEDIA`** 로 재생된 것. GAIN 은 타 앱에 `AUDIOFOCUS_LOSS`
(영구 상실)를 통보하므로 BGM 앱은 **일시정지가 아니라 정지**하고 알림음이 끝나도 자동 재개되지
않는다. 게다가 `_loopPlay` 가 회차마다 `stop()`+`play()` 를 하는데 stop=포커스 반납,
play=재요청이라 **주문 1건당 LOSS 가 설정 횟수(기본 5회)만큼 연속으로 꽂혔다.**

**Why:** 세 가지가 겹쳐 진단이 어려웠다.
1. **가짜 안전감** — `AndroidAudioFocus.none` 을 거는 코드가 이미 2곳 있었으나 둘 다 알림음을
   내지 않는 플레이어였다. 특히 `OrderProvider._audioPlayer` 는 `.play()` 호출처가 0건인
   유령 플레이어인데도 `AudioContext 설정됨` 로그를 남겨, 로그만 보면 대응이 된 것처럼 보였다.
2. **`setAudioContext` 는 playerId 단위**(`audioplayers/lib/src/audioplayer.dart`)라 한 플레이어에
   건 설정이 다른 플레이어로 전파되지 않는다. 전역은 `AudioPlayer.global.setAudioContext` 로만
   가능하고, 네이티브가 이를 `defaultAudioContext` 에 보관해 **이후 생성되는** 플레이어가
   상속한다 — 이미 만들어진 플레이어에는 소급 적용되지 않는다(생성 순서가 곧 커버리지).
3. **Android 전용 증상** — `audioplayers_windows` 는 setAudioContext 를 "not supported" 로그만
   남기고 무시한다. Windows 에서 재현하려 하면 원인을 영영 못 찾는다.

**How to apply:** 오디오 포커스를 의심할 땐 **"어느 플레이어가 실제로 `.play()` 를 부르는가"를
grep 으로 먼저 확정**하고, 그 인스턴스에 설정이 걸렸는지만 본다. 설정 코드의 존재나 로그는
근거가 아니다 — [[reference-appfit-log-file-whitelist]] 와 같은 결의 함정이다. 채택한 동작은
**완전 공존(`AndroidAudioFocus.none`)**: 포커스 요청 자체를 안 하므로 BGM 과 믹스되고, 덤으로
"다른 앱이 포커스를 안 내줘서 알림음이 무음" 이 되는 경우도 사라진다(`FocusManager` 는 NONE 일
때 요청 없이 곧바로 `onGranted()`). 덕킹/일시정지 계열은 현재 반복 루프 구조에서 BGM 볼륨이
N번 출렁이므로 루프 재설계 없이는 채택 불가. 실기기 검증은 `adb shell dumpsys audio` 의 포커스
스택으로 확인한다.
