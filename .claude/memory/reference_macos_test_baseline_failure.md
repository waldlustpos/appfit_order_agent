---
name: reference-macos-test-baseline-failure
description: macOS 에서 flutter test 는 항상 1건 실패한다 — build_brand_scope_test 의 Windows 경로 전제. 신규 실패와 혼동 금지.
metadata: 
  node_type: memory
  type: reference
  originSessionId: 42571bfa-ba71-4478-8842-914014252665
  modified: 2026-09-01T14:36:14.960Z
---

`appfit_order_agent` 에서 macOS 로 `flutter test` 를 돌리면 **항상 1건이 실패**한다:

```
test/config/build_brand_scope_test.dart:214
'설치 폴더명 — Dart 와 Inno Setup 스크립트가 일치한다 스테이징 폴더가 installDirName 아래에 있다'
Expected: a string ending with 'AppfitOrderAgent'
  Actual: '/var/folders/xv/...'
```

`UpdateConfig.stagingDir()` 이 Windows 의 `%LOCALAPPDATA%\<installDirName>\update`
를 전제하는데 macOS 에서는 시스템 temp 로 떨어진다. **Windows 에서만 통과하는
테스트**이며 코드 변경과 무관하다.

**어떻게 쓰나:** `flutter test` 결과가 `+N -1` 이면 그 -1 이 이것인지 먼저 확인하고
"신규 실패 0" 으로 판정한다. 확인 방법은 `git stash` 후 같은 파일만 재실행:
`flutter test test/config/build_brand_scope_test.dart`.

**Why:** 전체 스위트 끝의 `Some tests failed.` 만 보고 내 변경이 깨뜨렸다고
오판하기 쉽다. 실제로 출력이 캐리지리턴(`\r`)으로 한 줄에 뭉쳐 나와서 실패
지점을 찾기도 번거롭다 — `tr '\r' '\n'` 을 통과시켜야 `[E]` 블록이 보인다.

**How to apply:** 이 레포에서 테스트 통과 여부를 보고할 때 "691 통과, 신규 실패 0
(기존 macOS 전용 실패 1건)" 처럼 baseline 을 명시할 것. analyze 쪽 baseline 도
별도로 있다 — [[reference-slang4-multifile-and-analyze-baseline]].
