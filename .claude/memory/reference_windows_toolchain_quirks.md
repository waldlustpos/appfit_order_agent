---
name: reference-windows-toolchain-quirks
description: "Windows 개발 환경의 도구 함정 — python 스텁, PowerShell 거부, dart.exe analyzer 캐시 잠금"
metadata: 
  node_type: memory
  type: reference
  originSessionId: b11581b9-f8fe-45e0-9392-afa26d5ca4dc
---

이 머신(Windows 11, MINGW64 bash)에서 스크립트/검증 작업 시 함정:

- **`python`/`python3` 는 Windows Store 스텁** — 실행해도 "Python"만 출력하고 아무것도 안 함(exit 0). 스크립트 자동화는 **Dart 스크립트**(`dart script.dart`)로 작성할 것. `dart`/`flutter`/`git`/`rg` 는 정상.
- **PowerShell 도구는 사용자가 거부** — `Select-String`/`ForEach-Object` 등 cmdlet을 Bash로 우회 호출하는 것도 차단됨. 조사·치환은 Grep/Read/Edit/Write + inline `git grep` 사용.
- **`dart.exe` analyzer 데몬이 파일 잠금** — analyze/test/build_runner 가 끝난 뒤에도 캐시 데몬이 남아 다음 명령을 wedge 시킬 수 있음. 무거운 dart 명령 전에 `taskkill //F //IM dart.exe //T` 로 정리하면 안정적.
- **백그라운드 Bash 출력이 재정렬·중복·깨져서 도착** — 같은 턴에 여러 background Bash를 띄우면 결과 매핑이 어긋남. 무거운 명령은 결과를 **파일로 redirect**한 뒤 Read/Grep으로 확정. 절대 background 요약 텍스트만 믿고 커밋/리셋하지 말 것 — inline `git log`/`git status`로 ground truth 재확인.
- **임시 파일 경로**: `$TEMP` 는 `C:\Users\Administrator\AppData\Local\Temp`. background 태스크 출력 파일은 `...\tasks\<id>.output`.

**Why:** 한 세션에서 python 스텁이 import 변환 스크립트를 silent no-op으로 만들어, lint만 켜지고 변환은 안 된 채 잘못 커밋한 사고가 있었음(local-only라 reset으로 복구). [[feedback-verify-on-disk-not-async-output]] 와 함께 적용.

**How to apply:** lib 전체 import 재작성 등 대량 텍스트 작업은 Dart 스크립트로. 각 단계 후 `dart analyze` 의 실제 error/lint 카운트를 파일로 받아 직접 확인하고, 커밋 직전 `git diff --cached --name-status` 로 스테이징 범위를 눈으로 검증.
