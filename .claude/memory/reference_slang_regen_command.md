---
name: reference_slang_regen_command
description: i18n(slang) 재생성은 dart run slang. build_runner 로는 strings.g.dart 안 바뀜.
metadata: 
  node_type: memory
  type: reference
  originSessionId: f01ab972-6a89-49e0-8441-82b9b30a6201
  modified: 2026-09-03T06:26:07.314Z
---

이 프로젝트는 `slang_build_runner` 의존성이 없다. 따라서 `dart run build_runner build` 로는 `lib/i18n/strings.g.dart` 가 갱신되지 않는다 (build 는 성공하지만 i18n 변경 미반영 — clean 해도 동일).

i18n JSON(`strings_ko/en/ja.i18n.json`) 변경 후 생성 파일 재생성은 반드시:

```
dart run slang
```

생성 파일 헤더에도 `To regenerate, run: dart run slang` 로 명시되어 있다. 참고: [[project_appfit_core_dual_repo]] 와 무관, 앱 로컬 생성기.

**재생성 diff 가 수천 줄로 튀면 내 변경 탓이 아니다** (2026-09-03 실측): JSON 을 한 글자도 안 바꾸고 재생성만 해도 `strings_ko/en/ja.g.dart` 각 2,700~2,800줄이 바뀌었다 — 커밋돼 있던 산출물이 `pubspec.lock` 에 고정된 버전(당시 slang 4.18.0)보다 **옛 생성기**로 만든 것이었기 때문. 이때는 ① JSON 을 원상복구한 채 재생성해 **순수 churn 만 별도 커밋**(`chore(i18n): slang N 재생성`) ② 그 위에 내 문구 변경 + 재생성을 얹으면 실제 diff 가 수십 줄로 읽힌다. 캐시에 여러 버전(4.14/4.18/4.19)이 깔려 있어도 `flutter pub run slang` 은 lock 버전을 쓴다.
