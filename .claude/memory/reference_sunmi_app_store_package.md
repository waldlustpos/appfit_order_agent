---
name: reference_sunmi_app_store_package
description: "Sunmi App Store 패키지는 woyou.market (T2mini/D3MINI 공통). market:// 는 Google Play 로 새고, <queries> 검증은 dumpsys package queries."
metadata: 
  node_type: memory
  type: reference
  originSessionId: b5dfef67-f0b9-403e-b44b-f54498fd0210
  modified: 2026-08-25T06:14:07.203Z
---

Sunmi 단말에서 App Store 앱을 코드로 여는 방법과 그 함정. 2026-08-25 실측(T2mini_s TN11211U40325 / Android 7.1, D3MINI DE33256H10784 / Android 13).

**패키지는 `woyou.market` 하나다.** 두 기기 모두 동일. `com.sunmi.appstore` 라는 패키지는 **어느 기기에도 없다**(이름만 보고 추측하면 틀린다). 내부 런처 액티비티는 기기마다 다르다 -- T2mini_s 는 `store.ui.l.activity.HomeActivity`, D3MINI 는 `com.sunmi.appstore.activity.HomeActivity`. **액티비티명을 하드코딩하지 말고 `getLaunchIntentForPackage("woyou.market")` 를 쓸 것.**

**`market://details?id=<pkg>` 는 쓰면 안 된다.** T2mini_s 에서 이 URI 는 Google Play(`com.android.vending/...MarketDeepLinkHandlerActivity`)로 해석된다. 사내 배포 앱은 Play 에 없으므로 점주 화면에 "앱을 찾을 수 없음"이 뜬다. Sunmi 스토어는 자체 스킴 `market://woyou.market/appDetail`(`AppDetailActivity`)을 갖고 있으나 쿼리 파라미터명이 미확인이라 상세 딥링크는 아직 못 쓴다 -- 스토어 홈만 연다.

**`<queries>` 가 실제로 먹었는지는 `adb shell dumpsys package queries` 로 확인한다.** "queries via package name" 섹션에 호출 앱별로 볼 수 있는 패키지가 나열된다. 앱 UI 를 거치지 않고(로그인 없이) 검증할 수 있어 값싸다. 선언했지만 설치돼 있지 않은 패키지는 목록에 안 나온다(무해).

**검증은 반드시 Android 11+ 기기에서.** 패키지 가시성 필터는 호출 앱 targetSdk 30+ **그리고** 단말 API 30+ 일 때만 작동한다. T2mini(Android 7.1)에서는 `<queries>` 없이도 조회·실행이 되므로 통과해도 근거가 되지 않는다. D3MINI(Android 13)가 판정 기기다. 이 비대칭이 "개발기에선 되는데 현장 일부에서만 실패"를 만든다.

관련: [[project_kokonut_to_appfit_handoff]], [[project_d2s_kds_32bit_only]].
