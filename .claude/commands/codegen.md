---
description: freezed/json_serializable/riverpod_generator/slang 코드 재생성
---

> 이 프로젝트는 생성기가 **둘로 분리**되어 있다.
> - `.g.dart` / `.freezed.dart` (riverpod_generator 등) → **build_runner**
> - `lib/i18n/strings.g.dart` (다국어) → **slang standalone** (`slang_build_runner` 미사용이라 build_runner 로는 갱신 안 됨)
>
> Flutter 프로젝트라 `dart run` 은 SDK 해석 에러가 나므로 **`flutter pub run`** 을 쓴다.

Bash 툴로 아래 두 명령어를 순서대로 실행한다:

1. build_runner (freezed / json_serializable / riverpod_generator):
   ```
   flutter pub run build_runner build --delete-conflicting-outputs
   ```

2. slang (다국어 `strings.g.dart`):
   ```
   flutter pub run slang
   ```

실행 후:
- `git status --short` 로 생성/수정된 `.g.dart`, `.freezed.dart`, `strings.g.dart` 파일 목록을 간략히 요약
- 오류가 발생했다면 원인을 분석하고 수정 방법을 제안
- 오류가 없다면 "코드 생성 완료" 한 줄로 끝낸다
