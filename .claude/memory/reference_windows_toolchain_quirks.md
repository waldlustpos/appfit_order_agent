---
name: reference-windows-toolchain-quirks
description: "Windows 개발 환경의 도구 함정 — python 스텁, PowerShell 거부, dart.exe analyzer 캐시 잠금"
metadata: 
  node_type: memory
  type: reference
  originSessionId: b11581b9-f8fe-45e0-9392-afa26d5ca4dc
  modified: 2026-08-27T02:44:38.148Z
---

이 머신(Windows 11, MINGW64 bash)에서 스크립트/검증 작업 시 함정:

- **`python`/`python3` 는 Windows Store 스텁** — 실행해도 "Python"만 출력하고 아무것도 안 함(exit 0). 스크립트 자동화는 **Dart 스크립트**(`dart script.dart`)로 작성할 것. `dart`/`flutter`/`git`/`rg` 는 정상.
- **PowerShell 은 (2026-08-27 재확인) 정상 동작한다** — `powershell.exe -NoProfile -Command ...` 를 Bash 툴에서 호출하는 것도 통과. 이전 기록의 "사용자가 거부" 는 더 이상 맞지 않음. 다만 **한국어 출력이 콘솔 코드페이지 때문에 깨져서 도착**하므로, 판정에 쓰는 값은 ASCII 로 뽑거나 파일로 받아 읽을 것. `rm -rf` 등 파괴적 명령은 여전히 거부될 수 있음(경로별로 다름).
- **PowerShell 로 한글 포함 텍스트 파일을 왕복 편집하지 말 것** — `Get-Content`(인코딩 미지정)는 UTF-8 파일을 CP949 로 오독하고 `Set-Content -Encoding UTF8` 은 BOM 을 붙인다. 실제로 `shared_preferences.json` 의 한글 값이 깨지고 닫는 따옴표·쉼표까지 삼켜 앱이 설정 초기화에 실패했다(2026-08-27). **JSON/설정 편집은 Dart 로** — 파싱→값 변경→직렬화 왕복이면 안전.
- **PowerShell 쉼표 연산자는 `+` 보다 강하게 묶인다** — `@('a=' + $x, 'b=' + $y)` 는 `'a=' + ($x,'b=') + $y` 로 파싱되어 배열이 `$OFS`(공백)로 평탄화된 **문자열 1개**가 된다(실측 `Count=1`). 배열 리터럴에서 요소마다 문자열 연결을 쓰면 **각 요소를 괄호로 감쌀 것**. 이 버그로 Defender 진단 로그 6키가 한 줄로 뭉쳐 있었다.
- **`dart.exe` analyzer 데몬이 파일 잠금** — analyze/test/build_runner 가 끝난 뒤에도 캐시 데몬이 남아 다음 명령을 wedge 시킬 수 있음. 무거운 dart 명령 전에 `taskkill //F //IM dart.exe //T` 로 정리하면 안정적.
- **백그라운드 Bash 출력이 재정렬·중복·깨져서 도착** — 같은 턴에 여러 background Bash를 띄우면 결과 매핑이 어긋남. 무거운 명령은 결과를 **파일로 redirect**한 뒤 Read/Grep으로 확정. 절대 background 요약 텍스트만 믿고 커밋/리셋하지 말 것 — inline `git log`/`git status`로 ground truth 재확인.
- **임시 파일 경로**: `$TEMP` 는 `C:\Users\Administrator\AppData\Local\Temp`. background 태스크 출력 파일은 `...\tasks\<id>.output`.

**Why:** 한 세션에서 python 스텁이 import 변환 스크립트를 silent no-op으로 만들어, lint만 켜지고 변환은 안 된 채 잘못 커밋한 사고가 있었음(local-only라 reset으로 복구). [[feedback-verify-on-disk-not-async-output]] 와 함께 적용.

**How to apply:** lib 전체 import 재작성 등 대량 텍스트 작업은 Dart 스크립트로. 각 단계 후 `dart analyze` 의 실제 error/lint 카운트를 파일로 받아 직접 확인하고, 커밋 직전 `git diff --cached --name-status` 로 스테이징 범위를 눈으로 검증.
