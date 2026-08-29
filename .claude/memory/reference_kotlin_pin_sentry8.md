---
name: reference-kotlin-pin-sentry8
description: Kotlin 플러그인 2.2+ 는 sentry_flutter 8.x 를 컴파일하지 못한다 — 2.1.0 에 핀
metadata: 
  node_type: memory
  type: reference
  originSessionId: 63d816ff-a848-4835-861f-76dd56b13cbb
  modified: 2026-08-28T06:52:04.055Z
---

`flutter create` 가 찍어주는 최신 템플릿은 `org.jetbrains.kotlin.android` **2.2.20** 을 넣는데,
그 상태로 `sentry_flutter` 8.x 를 의존하면 빌드가 이렇게 죽는다.

```
e: Language version 1.6 is no longer supported; please, use version 1.8 or greater.
Execution failed for task ':sentry_flutter:compileDebugKotlin'.
```

sentry_flutter 8.x 의 Android 소스가 Kotlin **language version 1.6** 으로 컴파일되는데 Kotlin 2.2 가
1.6 지원을 **제거**했다(2.1 은 경고만 내고 통과). 앱 코드와 무관하므로 우리 쪽에서 고칠 수 없다.

**대응**: `android/settings.gradle.kts` 에서 `id("org.jetbrains.kotlin.android") version "2.1.0"`.
AGP 8.11 / Gradle 8.14 와는 문제없이 물린다. `appfit_order_agent` 도 2.1.0 이라 Sunmi 함대에서
이미 검증된 조합이다.

sentry 9.x 로 올려서 푸는 길은 막혀 있다 — **`appfit_core` 가 `sentry_flutter: ^8.0.0` 을 핀**하므로
core 릴리즈([[feedback-appfit-core-release]])가 선행되어야 한다.

[[project-simple-pos-jp-pilot]] 초기 세팅에서 겪음.
