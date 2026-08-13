---
name: reference-raw-control-char-breaks-grep
description: 소스에 생 제어문자(NUL 등)가 들어가면 grep 이 파일을 바이너리로 판정해 통째로 건너뛴다 — 반드시 \uXXXX 이스케이프로 쓸 것
metadata: 
  node_type: memory
  type: reference
  originSessionId: 30c102d8-e958-4830-b663-406629a7881f
  modified: 2026-08-13T13:02:51.581Z
---

Dart 소스에 **생(raw) 제어문자**를 문자열 리터럴로 넣으면 `file` 이 그 파일을 `data`(바이너리)로 판정하고, **`grep -n` / `grep -r` 이 해당 파일을 통째로 건너뛴다**. 컴파일·런타임에는 아무 문제가 없어서 증상이 조용하다.

**실제 피해 사례 (2026-08-13)**: `lib/widgets/common/common_dialog.dart:308` 의 dedupe 키에 생 NUL 2개가 있어서(커밋 b30da01부터) 이 파일이 grep 대상에서 제외됐다. 그 결과:
- `showInfoDialog` 가 존재하는데 grep 결과 0건 → "없다"고 오판하고 SnackBar 대체안을 계획에 넣었다
- l10n 감사 서브에이전트도 같은 이유로 `bulk_*` 키 6개를 전부 "미사용"으로 오탐했다

**규칙**: 구분자·센티널로 제어문자를 쓸 때는 소스에 `'\u0001'` / `'\u0000'` **이스케이프 표기**로 쓴다. 런타임 값은 동일하고 소스는 ASCII로 남아 도구 호환이 유지된다.

**진단**: `file -b <경로>` 가 `data` 로 나오면 이 함정이다. 급할 때 우회는 `grep -a`.

CLAUDE.md 의 "빌드/네이티브 소스는 ASCII만" 규칙과 같은 계열의 문제지만, 그 규칙은 `.cpp`/`.ps1` 대상이라 Dart 는 사각지대였다.

관련: [[project_product_group_bulk_soldout]]
