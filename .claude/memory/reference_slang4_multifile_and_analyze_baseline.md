---
name: reference_slang4_multifile_and_analyze_baseline
description: slang 4 다파일 생성 함정 + analyze 경고 baseline(0 아님) + unused_catch_stack 는 analyzer 진단
metadata: 
  node_type: memory
  type: reference
  originSessionId: a101d869-d4ef-4505-98f7-098d45aad9de
  modified: 2026-07-22T04:49:56.075Z
---

**slang 4 다파일 생성**: slang 4는 output_format 폐지로 항상 다파일 생성. `strings.g.dart`가 `part 'strings_ko.g.dart'`(base) + `import 'strings_en.g.dart'`/`strings_ja.g.dart`를 **필수 참조**한다. 재생성 후 로케일별 `strings_<locale>.g.dart` 3개를 반드시 함께 커밋해야 fresh checkout이 컴파일된다(안 하면 part/import 누락). slang 4는 기본 lazy 로딩이라 `slang.yaml`에 `lazy: false`를 넣어야 `setLocaleSync`/`setPluralResolverSync` 동기 API를 쓸 수 있다. `setLocale`/`setPluralResolver`의 void→Future 변경은 문장 위치 호출에서 **컴파일/린트로 안 잡히는 침묵 변경**(analysis_options에 unawaited_futures 없음) → grep 전수 확인 필수. 입력 파일명 `strings_<locale>.i18n.json`은 4.3에서 deprecated(→`<locale>.i18n.json`), 4.x 동작하나 개명은 add-brand/l10n-auditor/docs 파급이라 별도 과제. [[reference_slang_regen_command]]

**analyze baseline은 0이 아니다**: 이 repo는 flutter_lints 2 시절부터 **warning 약 69건**(0 errors) 상존 — 대부분 `unused_catch_stack`(catch(e,s)에서 s 미사용, ~61건) + unused_import 2 + dead_code 1 + unused_field 1 + strings.g.dart unused_element_parameter 2 + unused_local_variable 2. "analyze0"은 error/warning 0이 아니라 error 0을 뜻함. **PowerShell/Git Bash grep에서 `\s`는 POSIX ERE 미지원** → `grep -E "^\s+warning"`은 항상 0을 반환(false negative). 심각도 집계는 `grep -cE "^[[:space:]]*warning -"` 사용.

**unused_catch_stack은 linter 룰이 아니라 analyzer 진단**: `linter: rules:`에 `unused_catch_stack: false` 넣으면 `undefined_lint` 경고만 나고 억제 안 됨. `analyzer: errors: unused_catch_stack: ignore`로 설정해야 함. flutter_lints 6은 const 룰 3종 제거 + constant_identifier_names(SCREAMING_CASE 97곳)·no_leading_underscores(18) 신규 발화 → 최소 적용 시 이 셋을 억제(기존 관행과 충돌). [[project_deps_tier1_upgrade]]
