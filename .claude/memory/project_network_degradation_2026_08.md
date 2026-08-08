---
name: project-network-degradation-2026-08
description: "2026-08-07 매장 네트워크 열화 장애 분석·대응·재현도구 — NAT고갈 유력, 미커밋, 실기기 검증 대기"
metadata: 
  node_type: memory
  type: project
  originSessionId: 278d02e2-d30f-4005-8858-95a5214b5761
  modified: 2026-08-08T15:19:37.339Z
---

2026-08-07 매장 장애(15:06~15:20, 16:22~16:37 두 구간 각 14분) 대응 작업. **전부 미커밋** (main, 테스트 332개 통과).

**장애 정체**: 인터넷 단절 아님. "기존 세션(WebSocket)은 통과, 신규 세션(HTTP·DNS)만 실패"하는 비대칭 → **공유기 NAT 세션 고갈이 유력**, 차선 업링크 포화. 소켓 끊김 감지 14분 7초 지연 실측(heartbeat 가 readyState 만 봄). DNS 실패는 59ms 즉사인데 HTTP 는 20~30초 — 실패 모드가 섞여 있어 `[API진단] kind=` 계측으로 판별해야 함.

**구현 완료(3묶음)**: ① 계측+출혈차단 — `[API진단]` 로그, `_statusUpdateInFlight` 락(거절=false 필수), KdsAsyncButton 스피너, 새로고침 await+60s 상한, SocketEventSuppressor.discard ② ApiHealth(연속 2회 degraded, 4xx 는 리셋) + SyncStatusBanner(KDS·메인 공용) + 회복 시 refreshOrders ③ NetFaultInjector(대상3×종류7×지연×횟수, 10분 자동만료) + 프리셋 P1~P5 + 무장 리본. release 결함 수정: 앱바 시계 롱프레스 socket burst 가 무게이트였음.

**Why**: 장애 시 앱이 아무것도 알리지 않고 아무것도 복구하지 않았음. HTTP 성패가 유일한 진실 신호(connectivity_plus 는 링크만, 소켓은 유령).

**에뮬레이터 검증 완료(2026-08-08, staging MHST01073)**: P4 전체 사이클(실패1 배너X→실패2 저하+배너→성공 회복+배너소멸+리스너 refreshOrders가 in-flight 가드에 흡수) 시각+로그 이중 확인. P2 slowOnly 25s(스피너 유지·폴링 스킵 흡수·배너 오탐 0) 확인. P3 실주문(#0001)으로 확인: 20초 스피너(핑크 유지)·elapsed=20001ms 계측·실패 후 카드 진행탭 잔존·해제 후 재시도 104ms 성공·픽업탭 이동. 리본 실시간 잔여·탭 해제 확인. [API진단] kind=connectionError cause=SocketException — 실장애 로그와 동일 문자열. **미검증 잔여: P5·실네트워크(DNS/SYN)·4-D(소켓 백오프 소진).**

**★P3 중 신규 버그 발견→수정 완료 — KdsAsyncButton 재탭 관통**: 스피너 중 재탭에 확인 다이얼로그가 다시 떴다. 원인은 **가드를 State 수명에 묶은 설계** — `_busy` 가 State 로컬인데 kds_order_card 가 isDetailLoaded/kdsOrderType 로 Simple↔Scrollable 트리를 통째 교체 + 하단버튼도 `if (isDetailLoaded)` 조건부라, 20초 대기 중 폴링이 주문을 갱신하면 State 재생성으로 _busy 리셋. key 는 orderId 기반이라 무관했음. **수정**: private Set → `statusUpdateInFlightProvider` 승격(tryAcquire/release), KdsAsyncButton 에 `externalBusy` 추가(`_locked = _busy || externalBusy`), 버튼이 orderId select 구독. 위젯테스트 4개(관통 재현 케이스를 "로컬 가드만으론 못 막는다" 문서화로 보존) + 에뮬레이터 재검증(5연타 전부 차단·실패 다이얼로그 정상·해제 후 120ms 성공) 완료.

**2차 보강(Sentry 실데이터 기반, 커밋 a5448df·32ac65c)**: PAIK00002 조회로 확인 — 코어가 transient 를 breadcrumb 으로만 남겨 매장 열화가 원격에서 **구조적으로 안 보임**(14분 장애 = Sentry 0건). R1 api_health 전역태그(전이 **3곳** — 4xx 리셋 회복을 빠뜨리면 태그 sticky) / R2 NetworkDegradedException captureError(fingerprint 고정+cooldownKey) / R3 HTTP 회복 시 disconnected 소켓 깨우기(Auth.reconnect, 코어 notifyNetworkRestored 는 래퍼가 private 이라 도달 불가) / R4 비네트워크 예외만 파일 승격.

**E2E 검증 완료(에뮬레이터 staging)**: 장애주입→degraded→Sentry 이슈(APPFIT-ORDER-AGENT-5J, api_health=degraded + store_id 태그)→**Slack #appfit-alert-test 도달까지 실확인**. 회복 시 이슈 추가생성 없음(breadcrumb만). R3 는 iptables DROP 으로 소켓 백오프 5회 소진(21:37:51→21:41:04, 93초)→"최대 재연결 횟수 초과"→차단해제→**15초 만에 `소켓 영구 정지 감지 → HTTP 회복 신호로 재연결 시도` → 연결 성공**.

**★실측: SYN 드롭 = `kind=connectionTimeout elapsed≈30000ms`** (iptables DROP 재현). 보류했던 타임아웃 전략의 방향 근거 — 실장애 20~27초가 이 계열이면 앱 레이어 receiveTimeout 으로는 못 줄이고 **코어 C1(connectTimeout) 필수**. 단 iptables DROP 은 기존 세션도 죽여 소켓이 45초에 사망 — 실장애의 "기존 세션 생존" 비대칭(NAT 고갈)은 재현 못 함.

**★코어 C4 완료(2026-08-09, 코어 v1.2.0 = f27fb03 / 앱 34fd34b)**: `_maxReconnectAttempts=5` 영구 정지를 **2단계 백오프**로 교체 — 빠른 5회(3·6·12·24·48초)는 그대로 `reconnecting`, 소진 시 `disconnected` **1회** emit + error 로그, 이후 300초 간격 **무한** 재시도(추가 emit 없음). 설계 제약이 관측 계약이었다: `disconnected` 는 앱바 빨강 + **탭하면 수동 재연결** 어포던스라 없애면 안 되고, 느린 구간에서 상태를 반복 emit 하면 UI 깜빡임 + flapping 감지(5분 6회) 오탐. 힌트는 코드에 이미 있었다 — `_maxDelaySeconds=300` 이 5회 상한 때문에 **도달 불가능한 죽은 상수**였음(원래 의도가 상한 무한재시도). `_isInSlowRetry` 리셋 4곳(연결성공/notifyNetworkRestored/connect/disconnect) 필수 — 앱 R1 "전이 3곳"과 같은 계열 함정. **느린 구간은 pow 금지**: 무한 재시도면 `pow(2,1024)=infinity` → `toInt()` 가 던짐(300초 간격 ≈3.5일에 도달). 분기로 지수를 ≤4 로 묶어 구조적 차단. 앱 R3 는 역할이 "영구 침묵 탈출"→"5분 대기 단축"으로 바뀌고 수단도 `Auth.reconnect()`(getProjectInfo HTTP 왕복) → 코어 `notifyNetworkRestored()`(v1.2.0 passthrough 신설) 로 경량화. 판정 로직·테스트 단언은 무변, doc 주석만 갱신.

**E2E 3건(에뮬레이터 staging MHST01073)**: ① 느린 재시도 진입 — 빠른 5회 실패 후 전환 로그 **1회**, 6·7번째가 정확히 300초 간격 발화(예전엔 완전 정지), 상태 추가 emit 0 ② **코어 단독 자력 복구** — [[reference-tls-sni-selective-block]] 로 소켓만 차단해 HTTP 무결 유지(건강도·API진단 로그 **0줄** = R3 발화 불가) → 해제 후 무개입으로 예약된 7번째가 스스로 성공(`연결 성공 (느린 재시도 7번째 시도에서 복구)`) ③ 회복 신호 단축 — 전체 443 해제 7초 만에 재연결(예정 대비 4분 단축). 실측: 소켓 사망은 차단 후 46초, 빠른 구간 wall-clock 은 93초가 아니라 **193초**(각 시도에 wsConnectTimeout 20초가 더해짐).

**How to apply**:
- 검증은 debug 빌드 + 개발자 옵션(버전 5연타) 프리셋. P2(slowOnly)에서 배너 뜨면 버그. 4-D(DNS 차단+앱 재시작→소켓 93초 후 영구정지)는 영업 외 시간에만.
- 에뮬레이터 검증 시 폴링 위상 주의: 60s 그리드(이번엔 :27초)가 유한 카운터를 소모해 탭 횟수와 안 맞을 수 있음. 파일 로그(/sdcard/Documents/appfit/appfit_YYYY-MM-DD.txt)의 [FAULT주입] 줄로 소모 주체를 확인할 것.
- 실기기 `kind=` 결과가 보류 항목을 결정: connectionTimeout 우세→코어 C1(connectTimeout, Dio Options 로 우회 불가), receiveTimeout 우세→앱 레이어 per-request 타임아웃.
- ~~코어 C4 가 최우선 코어 작업~~ → **완료(코어 v1.2.0, 앱 커밋 34fd34b)**. 아래 참조.
- 다음 단계 확정 정책: 유실 전이 자동 재발행 큐(printer_job_queue 본뜸, CANCELLED 절대 재시도 금지, drain 시 서버 상태 선검증, [[project-order-output-audit-2026-07]] 배너 연동).
- 주입점은 반드시 try 안 + dio 호출 직전 — try 밖이면 건강도/진단을 우회 (전신 injector 의 결함이었음).
- 계획 정본: ~/.claude/plans/15-06-27-731-d-ui-action-moonlit-lark.md
