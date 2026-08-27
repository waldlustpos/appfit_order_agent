---
name: reference_appfit_log_file_whitelist
description: logToFile 은 파일 보장이 아님 — logger.dart 화이트리스트(level>=warning 또는 태그 문자열)가 파일 기록을 결정. logger.d/i 는 태그 없으면 콘솔 전용.
metadata: 
  node_type: memory
  type: reference
  originSessionId: 96e6a53a-9e0a-4a24-bd64-abfb355bec14
  modified: 2026-08-27T07:52:56.472Z
---

`logToFile`(`lib/services/platform_service.dart`)은 **파일 API 가 아니라 `logger` 얇은 래퍼**다. ERROR→`logger.e`, WARNING→`logger.w`, 나머지→`logger.d('[TAG] …')`. 실제 파일 기록 여부는 `lib/utils/logger.dart` 의 `CustomLogOutput.output` 화이트리스트가 결정한다.

**규칙:**
1. 파일에 남으려면 **`level >= Level.warning`** 이거나 라인에 **태그 문자열**(`[PLATFORM]`/`[SYSTEM]`/`[UI_ACTION]`/`[WEBSOCKET]`/`[LIFECYCLE]`/`[FLEET]`/`[Notifier]`)이 포함돼야 한다. `LogTag.STATE`/`STORAGE`/`NAVIGATION` 등 화이트리스트에 없는 태그는 `logToFile` 을 써도 파일에서 사라진다.
1-a. **`LogTag.API` 는 조건부다** — `[API]` 분기는 라인에 `ERROR`/`실패`/`오류`(한글) 가 있을 때만 통과시킨다. 그래서 `logToFile(tag: LogTag.API, message: '…성공')` 류는 **전부 조용히 버려진다.** 영문 `error`/`Fail` 도 대소문자·언어가 안 맞아 통과 못 한다. 2026-08-27 점검에서 로그인시도/로그인성공/V2 Token Acquired/신규 주문 감지/Bulk completion result 가 전부 이 함정에 걸려 있었고(즉 "이 기기가 언제 로그인했나·주문을 언제 받았나"가 로그파일에 없었다), LIFECYCLE/WEBSOCKET/SYSTEM/UI_ACTION 으로 태그를 올려 해결했다. **성공 경로를 파일에 남기고 싶으면 `LogTag.API` 를 쓰면 안 된다.** 반대로 화이트리스트의 `[API]` 조건 자체를 푸는 건 금물 — 정상 API 트래픽이 통째로 파일에 쏟아진다.
2. `logger.w` / `logger.e` 는 태그 없이도 파일에 남는다 → 이미 warning 이상인 줄을 `logToFile` 로 "승격"하면 **중복 기록**이 된다. 승격은 **추가가 아니라 치환**으로 할 것.
3. 블록리스트 토큰(`[OutputQueue]`, `[SecureStorage]`, `스크롤` 등)이 문구에 들어가면 걸러진다.
4. `logToFile` 은 `await` 하지 말 것(fire-and-forget). 임계구역(`_portLock` 등) 안에서 await 하면 락 보유가 로그 I/O 에 묶인다.
5. 버퍼는 30줄/2초 flush 라 크래시 직전 로그는 유실될 수 있다.
6. Windows 로그 파일 경로는 `<Documents>\appfit\appfit_YYYY-MM-DD.txt`(`WindowsLogFileWriter`). Android 는 네이티브가 공개 `Documents/appfit` 우선.

**주의:** `PrinterJobQueue.onFinalFailure` 주석의 "logger.e 로 Sentry 자동 캡처" 는 **사실이 아니다.** `logger.dart` 에 Sentry 참조가 없고 `main.dart` 는 `FlutterError.onError` / `PlatformDispatcher.onError` 만 `MonitoringService` 에 연결한다. 출력 최종 실패는 파일 로그로만 남는다.

2026-07-21 COM 프린터 진단 로그 보강에서 확인(당시 `probeConnection` 종결 로그 3곳이 `logger.d/i` 라 파일에 한 줄도 안 남고 있었음). 관련: [[feedback_com_startup_retry_scope]], [[project_remote_log_collection]].
