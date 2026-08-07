---
name: project-network-degradation-2026-08
description: "2026-08-07 매장 네트워크 열화 장애 분석·대응·재현도구 — NAT고갈 유력, 미커밋, 실기기 검증 대기"
metadata: 
  node_type: memory
  type: project
  originSessionId: 278d02e2-d30f-4005-8858-95a5214b5761
  modified: 2026-08-07T16:24:14.631Z
---

2026-08-07 매장 장애(15:06~15:20, 16:22~16:37 두 구간 각 14분) 대응 작업. **전부 미커밋** (main, 테스트 332개 통과).

**장애 정체**: 인터넷 단절 아님. "기존 세션(WebSocket)은 통과, 신규 세션(HTTP·DNS)만 실패"하는 비대칭 → **공유기 NAT 세션 고갈이 유력**, 차선 업링크 포화. 소켓 끊김 감지 14분 7초 지연 실측(heartbeat 가 readyState 만 봄). DNS 실패는 59ms 즉사인데 HTTP 는 20~30초 — 실패 모드가 섞여 있어 `[API진단] kind=` 계측으로 판별해야 함.

**구현 완료(3묶음)**: ① 계측+출혈차단 — `[API진단]` 로그, `_statusUpdateInFlight` 락(거절=false 필수), KdsAsyncButton 스피너, 새로고침 await+60s 상한, SocketEventSuppressor.discard ② ApiHealth(연속 2회 degraded, 4xx 는 리셋) + SyncStatusBanner(KDS·메인 공용) + 회복 시 refreshOrders ③ NetFaultInjector(대상3×종류7×지연×횟수, 10분 자동만료) + 프리셋 P1~P5 + 무장 리본. release 결함 수정: 앱바 시계 롱프레스 socket burst 가 무게이트였음.

**Why**: 장애 시 앱이 아무것도 알리지 않고 아무것도 복구하지 않았음. HTTP 성패가 유일한 진실 신호(connectivity_plus 는 링크만, 소켓은 유령).

**에뮬레이터 검증 완료(2026-08-08, staging MHST01073)**: P4 전체 사이클(실패1 배너X→실패2 저하+배너→성공 회복+배너소멸+리스너 refreshOrders가 in-flight 가드에 흡수) 시각+로그 이중 확인. P2 slowOnly 25s(스피너 유지·폴링 스킵 흡수·배너 오탐 0) 확인. P3 실주문(#0001)으로 확인: 20초 스피너(핑크 유지)·elapsed=20001ms 계측·실패 후 카드 진행탭 잔존·해제 후 재시도 104ms 성공·픽업탭 이동. 리본 실시간 잔여·탭 해제 확인. [API진단] kind=connectionError cause=SocketException — 실장애 로그와 동일 문자열. **미검증 잔여: P5·실네트워크(DNS/SYN)·4-D(소켓 백오프 소진).**

**★P3 중 신규 버그 발견→수정 완료 — KdsAsyncButton 재탭 관통**: 스피너 중 재탭에 확인 다이얼로그가 다시 떴다. 원인은 **가드를 State 수명에 묶은 설계** — `_busy` 가 State 로컬인데 kds_order_card 가 isDetailLoaded/kdsOrderType 로 Simple↔Scrollable 트리를 통째 교체 + 하단버튼도 `if (isDetailLoaded)` 조건부라, 20초 대기 중 폴링이 주문을 갱신하면 State 재생성으로 _busy 리셋. key 는 orderId 기반이라 무관했음. **수정**: private Set → `statusUpdateInFlightProvider` 승격(tryAcquire/release), KdsAsyncButton 에 `externalBusy` 추가(`_locked = _busy || externalBusy`), 버튼이 orderId select 구독. 위젯테스트 4개(관통 재현 케이스를 "로컬 가드만으론 못 막는다" 문서화로 보존) + 에뮬레이터 재검증(5연타 전부 차단·실패 다이얼로그 정상·해제 후 120ms 성공) 완료.

**How to apply**:
- 검증은 debug 빌드 + 개발자 옵션(버전 5연타) 프리셋. P2(slowOnly)에서 배너 뜨면 버그. 4-D(DNS 차단+앱 재시작→소켓 93초 후 영구정지)는 영업 외 시간에만.
- 에뮬레이터 검증 시 폴링 위상 주의: 60s 그리드(이번엔 :27초)가 유한 카운터를 소모해 탭 횟수와 안 맞을 수 있음. 파일 로그(/sdcard/Documents/appfit/appfit_YYYY-MM-DD.txt)의 [FAULT주입] 줄로 소모 주체를 확인할 것.
- 실기기 `kind=` 결과가 보류 항목을 결정: connectionTimeout 우세→코어 C1(connectTimeout, Dio Options 로 우회 불가), receiveTimeout 우세→앱 레이어 per-request 타임아웃.
- 코어 C4(재연결 백오프 5회/93초 소진 후 영구 disconnected)가 최우선 코어 작업 — 이번에 21초 차이로 회피했을 뿐.
- 다음 단계 확정 정책: 유실 전이 자동 재발행 큐(printer_job_queue 본뜸, CANCELLED 절대 재시도 금지, drain 시 서버 상태 선검증, [[project-order-output-audit-2026-07]] 배너 연동).
- 주입점은 반드시 try 안 + dio 호출 직전 — try 밖이면 건강도/진단을 우회 (전신 injector 의 결함이었음).
- 계획 정본: ~/.claude/plans/15-06-27-731-d-ui-action-moonlit-lark.md
