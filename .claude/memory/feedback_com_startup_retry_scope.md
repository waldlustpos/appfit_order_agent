---
name: feedback_com_startup_retry_scope
description: "Windows COM 프린터 재시도 계층 경계 — sendRaw 는 큐 backoff 가 이미 상위 호환이라 내부 재시도 금지, probeConnection(시작 연결 확인)만 백오프 재시도 대상. 2026-07-21 실기 검증."
metadata:
  node_type: memory
  type: feedback
---

Windows 외부 COM 영수증 프린터의 **재시도는 두 계층이 역할을 나눠 갖는다.** 어느 쪽에 넣을지 헷갈리면 아래 경계를 따른다. 2026-07-21 kokonut(90e5bdf/964ba97) 개선을 appfit 에 대조하며 확정, 실기(Windows POS + PR800, COM3) 검증 완료.

**Why:**
- `ComPortPrintService.sendRaw` 의 살아있는 호출자는 `external_receipt_printer_windows.dart` 의 `WindowsTransport.send` 단 1곳이고, 그 호출자는 `printer_job_queue.dart` 의 재시도 루프 단 1곳이다. 모든 출력은 `external_receipt_printer.dart` 의 `_sendBytes` → `PrinterJobQueue.enqueue` 를 강제 경유한다(주문서/영수증/테스트/기기호출 4종 전부).
- 큐 backoff 는 0/2/5/10/20/40/60초 = 7회·누적 137초이고, **매 회차가 `getAvailablePorts()` 부터 통째로 재진입**한다(새 SerialPort 인스턴스 + DCB prime + open + settle + probe). 게다가 2회차부터는 `_lastFailureAt` 때문에 settle 이 failure-cooldown(cold 1.5s + 250ms)으로 자동 승격된다. kokonut K2(동일 인스턴스로 350ms×3 ≈ 1.05초)의 **시간·범위 상위 호환**이다.
- 반면 `probeConnection` 위에는 backoff 계층이 **전혀 없다.** 내부 5회 핑 재시도는 open 성공 이후에만 돌아서, 점유(open throw)나 미enumerate 는 즉시 false 로 끝났다.

**How to apply:**
- **`sendRaw` 내부에 open+probe 재시도 루프를 넣지 말 것.** 넣으면 `_portLock` 보유 시간이 시도당 최악 ~9초로 늘고, 그게 7 attempt 에 곱해져 단일 worker 큐의 head-of-line blocking 이 악화된다. 진입부 enumerate 폴링 대기도 같은 이유로 금지(락을 쥔 채 기다린다 — 큐 backoff 는 락을 놓고 기다린다).
- **이 면제는 `sendRaw` 한정.** 시작 시 연결 확인은 `PrintService._runStartupConnectionCheck` + `StartupProbeScheduler`(5/15/30/60/60초, 초기 1회 포함 총 6회)가 담당한다. 주기 폴링으로 승격하지 말 것 — COM probe 는 포트를 실제로 여닫아 출력과 간섭한다. 시작 창 한정·유한 횟수.
- **재검토 조건:** `PrinterJobQueue.defaultBackoffs` 정책이 축소되면(회차·간격) 위 포섭 논증이 무효가 되므로 다시 판단한다.
- probe 경로에서 `_lastFailureAt` / `_lastSuccessfulSendAt` 을 **쓰지 말 것.** `_lastFailureAt` 을 건드리면 failure-cooldown 이 켜져 직후 첫 출력 settle 이 1750ms 로 늘어난다.
- 연결 확인 결과(`printerStatusProvider.isExternalConnected`)는 **출력을 게이트하지 않는다.** 소비처는 설정화면 뱃지 1곳뿐이라, probe 실패 자체는 주문서 누락을 만들지 않는다. 진짜 누락 경로는 큐 137초 소진 후 **최종 실패 무통지**다([[project_order_output_audit_2026_07]]).

관련: [[project_pr800_rs232_serial]], [[reference_external_printer_liveness]], [[feedback_queue_enqueue_timing]], [[reference_appfit_log_file_whitelist]].
