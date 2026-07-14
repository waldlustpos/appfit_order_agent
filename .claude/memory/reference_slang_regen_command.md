---
name: reference_slang_regen_command
description: i18n(slang) 재생성은 dart run slang. build_runner 로는 strings.g.dart 안 바뀜.
metadata: 
  node_type: memory
  type: reference
  originSessionId: f01ab972-6a89-49e0-8441-82b9b30a6201
---

이 프로젝트는 `slang_build_runner` 의존성이 없다. 따라서 `dart run build_runner build` 로는 `lib/i18n/strings.g.dart` 가 갱신되지 않는다 (build 는 성공하지만 i18n 변경 미반영 — clean 해도 동일).

i18n JSON(`strings_ko/en/ja.i18n.json`) 변경 후 생성 파일 재생성은 반드시:

```
dart run slang
```

생성 파일 헤더에도 `To regenerate, run: dart run slang` 로 명시되어 있다. 참고: [[project_appfit_core_dual_repo]] 와 무관, 앱 로컬 생성기.
