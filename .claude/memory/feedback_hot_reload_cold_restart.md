---
name: feedback-hot-reload-cold-restart
description: "프린터/FFI/native 경로의 static 필드 추가, 새 import, 함수 본체 큰 재작성 후 디버그 검증은 반드시 cold-restart 로 — hot-reload 가 hang 처럼 보이는 사고가 있었음"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 0c886ff3-b720-401a-be8a-01949f9ab18b
---

`lib/services/` 의 프린터·FFI 관련 파일에 **새 import + 새 static 필드 + 새 static method + 함수 본체 큰 재작성** 이 한 커밋에 같이 들어간 변경 후에는, hot-reload 가 아닌 `flutter clean` → cold debug start 로 검증할 것.

**Why:** 2026-05-19, `com_port_print_service.dart` 에 `platform_service.dart` import + `_lastFailureAt` / `_lastFailureReason` static 필드 + `_waitPortEnumerated` / `_safeClose` static method + `sendRaw` 본체 재작성을 동시 적용했더니 디버그 실행 시 main.dart 의 `PreferenceService 초기화 완료` 직후에 hang. 변경 3개 파일 stash 분리 → cold-restart 시 정상. `git stash pop` 후에도 `flutter clean` + cold-restart 시 정상. 즉 코드 회귀가 아니라 Flutter incremental kernel link 가 새 정적 멤버를 못 묶어 앱이 멈춘 것처럼 보이는 사고였음. flutter analyze + 단위 테스트는 통과해도 hot-reload 는 별개라는 점을 잡아야 함.

**How to apply:** 프린터/serial_port_win32/win32 FFI/MethodChannel 영역에 (1) 새 import 추가, (2) 새 static 멤버 추가, (3) 함수 본체 큰 재작성 중 둘 이상이 동시에 들어가는 변경을 만든 직후엔 사용자에게 "cold-restart 로 검증해주세요" 를 먼저 안내. 사용자가 "응답없음" 보고를 하면 회귀로 결론 짓기 전에 `git stash` 분리 + cold-restart 비교를 1단계로 권할 것. `analyze` / 테스트 통과 = 정상 동작 보장 아님 (특히 hot-reload).
