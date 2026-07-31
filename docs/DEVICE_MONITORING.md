# 기기 관제 (Fleet)

매장 기기(Sunmi D3 MINI 주문접수기, D2s_KDS, Windows POS)의 **① 앱 실행 상태 ② 기기 정보 ③ 원격 로그 요청**을 다루는 최소 관제 시스템.

> **상태: 배포 완료(2026-07-31), 실기기 파일럿 대기.** 백엔드는 별도 레포 `appfit-fleet`(Cloudflare Workers + D1), 앱 측은 `lib/services/fleet/`.
>
> 대시보드: https://appfit-fleet.sckim.workers.dev (자격정보는 `appfit-fleet/DEPLOYMENT.local.md`)
>
> 에뮬레이터로 운영 서버 상대 전 구간 검증 완료 — 기기 등록 → 대시보드 표시 → 원격 로그 요청 → Slack 업로드 → 결과 반영. 실기기 검증만 남았다(§6).

이 문서의 이전 버전은 "수신단 미정 / 구현 미착수" 설계안이었다. 실제 구현에서 달라진 결정은 §7 에 정리했다.

## 배경

주력 디바이스가 매장에 다수 배포돼 있지만 어떤 기기가 지금 켜져 있고 어떤 앱/OS 버전으로 도는지 원격에서 볼 방법이 없었다. 게다가 로그를 받으려면 현장 직원에게 설정화면 조작을 안내해야 했는데, 그 "로그 전송" 버튼은 `AppEnv.showInternalUi = !kReleaseMode` 뒤라 **매장 출고본에서는 아예 보이지 않는다**. 즉 원격으로 로그를 받아낼 경로가 없었다.

---

## 1. 전체 구조

```
[기기 앱]                          [Cloudflare Worker]              [브라우저]
FleetReporter                      POST /v1/device/register  ──┐
 ├ 60s 단발타이머 ──────────────▶  POST /v1/device/heartbeat   ├─▶ D1(devices, commands)
 │   └ 응답 commands[] 수신                    │                 │
 ├ FleetCommandHandler                        ▼                 │
 │   └ LogCollectionService ──▶ Slack   nextIntervalSeconds     │
 └ 결과는 다음 heartbeat body 의 results[]                       │
                                    GET  /               ────────▶ 단일 페이지 대시보드
                                    POST /api/commands   ◀──────── "로그 요청"
```

명령은 **heartbeat 응답에 실어 보낸다(piggyback)**. AppFit 의 WebSocket 은 수신 전용(`sink.add` 없음)이라 push 채널을 새로 뚫으려면 서버팀 의존이 생긴다.

로그 파일은 관제 서버에 저장하지 않는다. 기기가 기존 `SlackDirectSink` 로 zip 을 올리고, 서버는 요청·진행·결과 상태만 들고 있는다.

## 2. 파일 맵

| 경로 | 역할 |
|---|---|
| `lib/services/fleet/core/fleet_models.dart` | 와이어 모델(수동 toJson/fromJson) |
| `lib/services/fleet/core/fleet_sink.dart` | `FleetSink` 추상 + `NoopFleetSink` |
| `lib/services/fleet/core/http_fleet_sink.dart` | 전용 Dio 로 Worker 에 전송 |
| `lib/services/fleet/core/fleet_reporter.dart` | 타이머·백오프·명령 디스패치 |
| `lib/services/fleet/order_agent_fleet_snapshot.dart` | 앱 전용 스냅샷 조달 |
| `lib/services/fleet/order_agent_fleet_command_handler.dart` | 앱 전용 명령 실행(로그 수집) |
| `lib/providers/fleet_provider.dart` | sink 교체 지점 + 생명주기 배선 |
| `lib/services/log_collection/log_collection_request.dart` | 캡션·기간·파일명 **정본**(수동/원격 공용) |
| `test/services/fleet/` | fakeAsync 21 + 모델 + sink + 격리 + 실서버 왕복 |

### `core/` 는 appfit_core 승격 대상

`lib/services/fleet/core/` 4파일은 나중에 `appfit_core/lib/src/fleet/` 로 옮겨 DID·KIOSK 와 공유한다. 그래서 **core/ 바깥의 앱 코드를 import 하지 않는다.** 허용은 `dart:*`, `package:dio`, `package:connectivity_plus`, `package:appfit_core`, 그리고 같은 `core/` 형제 파일뿐이다.

이 규율은 주석이 아니라 `test/services/fleet/fleet_core_isolation_test.dart` 가 지킨다. 빨개지면 승격 비용이 "파일 이동"에서 "재설계"로 뛴 것이다.

앱 안에서 먼저 구현한 이유는 core 가 별도 레포 + 태그 핀이라 왕복 비용이 크고, 3앱 공유 라이브러리에 검증 안 된 API 를 먼저 올리고 싶지 않았기 때문이다. 승격 절차는 §6.

## 3. 앱 측 설계

### 값 조달 = 비동기 builder 콜백

```dart
typedef FleetSnapshotBuilder = Future<FleetSnapshot?> Function();
```

`MonitoringContext` 확장안은 배제했다. 동기 getter 뿐이라 `DeviceIdentityService.resolve()`(네이티브 시리얼 조회, async)를 담을 수 없고, 그 객체는 `main()` 에서 1회 생성 후 갱신되지 않아 storeId 가 영구히 빈 값이 되며, 무엇보다 추상 클래스에 getter 를 더하면 DID·KIOSK 구현체가 동시에 깨진다.

builder 는 매 틱 호출되므로 로그인 지연과 매장 전환이 저절로 해결된다. `null` 은 "아직 준비 안 됨"이고 실패가 아니다(백오프 없음).

### 시계를 읽지 않는 타이머

`FleetReporter` 는 `DateTime.now()` 를 **어떤 분기에도** 쓰지 않는다. 재등록 판정은 지문 문자열 비교, 백오프는 실패 횟수 정수 연산, 중복 명령 차단은 ID 큐다. 덕분에 `fakeAsync` 가상시계로 전 시나리오가 결정론적으로 검증된다.

`Timer.periodic` 대신 매 틱 끝에서 단발 타이머를 다시 건다 — 간격을 동적으로 바꿀 수 있고, 응답이 느려도 틱이 누적되지 않는다.

### 명령 실행을 await 하지 않는다

로그 zip 수집이 3분 걸려도 heartbeat 케이던스가 유지되어야 대시보드에서 stale 로 오해받지 않는다. 동시 1건만 실행하고 나머지는 즉시 `BUSY` 로 답한다.

### 안전장치

| 상황 | 동작 |
|---|---|
| 핸들러 미주입(DID 등) | `UNSUPPORTED` 즉답 — 서버에 delivered 좀비가 남지 않는다 |
| 대상 불일치 | `INVALID_TARGET` — 매장 전환 직후 구 명령이 엉뚱한 매장 로그를 올리는 것 차단 |
| 서버가 기기를 모름 | `needsRegister` → 다음 틱에 register (DB 초기화 자가 치유) |
| 전송 실패 | 지수 백오프 60→120→240…, 상한 10분. 4xx 는 곧바로 상한 |
| 오프라인 | 2틱 스킵 + 3틱째 강제 프로브(connectivity 오판 자가 치유) |
| 동시 부팅 | 첫 틱에 0~15초 지터(정전 복구 스파이크 분산) |
| 예외 | 밖으로 나가지 않는다. 관제가 주문 흐름을 막으면 안 된다 |

### 배선 지점 = `MyApp.build()`

`home_screen` 이 아니다. 로그인 화면에 머무는 기기(설치했는데 로그인 안 된 기기)가 관제에서 통째로 사라지면 안 되고, 그게 오히려 가장 먼저 확인하고 싶은 상태다. 로그인 전에는 `storeId` 가 빈 문자열로 보고되고 서버가 "미배정" 으로 묶는다.

`fleetSyncProvider` 가 세 신호를 연결한다: 매장 전환(→ 재등록 + `DeviceIdentityService.invalidate()`), 소켓 상태, 라이프사이클(`detached` → closing 보고).

`paused` 에서는 closing 을 보내지 않는다. Android 는 오버레이 버블 때문에 paused 가 상시 발생해 대시보드가 "종료 중"으로 도배된다. 대신 `lifecycle` 필드로 백그라운드와 무응답을 구분한다.

## 4. 로그 원격 요청

수동 버튼과 원격 명령이 **물리적으로 같은 코드**를 지난다 — `buildLogCollectionRequest()` + `LogCollectionService.collectAndUpload()`. 복붙했다면 Slack 메시지 포맷이 두 벌로 갈라져 운영 중 매장 식별이 어긋난다. 캡션 문자열은 `log_collection_request_test.dart` 가 고정한다.

원격 경로만 **원본 30MB 상한**(`maxSourceBytes`)이 걸린다. zip 이 인메모리라 피크 메모리가 "원본 + 결과"인데, 원격 명령은 아무도 보고 있지 않은 매장 기기에서 실행되므로 OOM 이 나면 앱이 조용히 죽는다. 수동 버튼은 사용자가 보고 있으니 무제한 유지.

기간이 없으면 **기기 로컬 기준 오늘**로 해석한다. 서버가 UTC 로 '오늘'을 정하면 KST 매장에서 하루가 어긋나므로, 서버는 날짜를 비워 보내고 해석을 기기에 맡긴다.

### 릴리즈 UI 정책

설정화면 "로그 전송" 카드는 릴리즈에서 계속 숨겨진다(`AppEnv.showInternalUi = !kReleaseMode`). 매장 기기는 **원격 명령으로만** 로그를 올린다.

**`fleetSyncProvider`·`fleetCommandHandlerProvider`·`HttpFleetSink` 에는 어떤 빌드모드 가드도 넣지 말 것.** 넣으면 개발 기기에서만 잘 되고 매장 기기에서만 정확히 안 되는, 발견이 가장 늦는 버그가 된다.

## 5. 설정

`.env` 두 줄이면 된다. 빌드 스크립트 6개가 전부 `--dart-define-from-file=.env` 라 스크립트 수정은 불필요.

```
FLEET_BASE_URL=https://appfit-fleet.<subdomain>.workers.dev
FLEET_DEVICE_KEY=<서버 DEVICE_KEYS 중 하나>
```

`lib/config/app_env.dart` 에 `fleetBaseUrl`/`fleetDeviceKey`/`hasFleetConfig` 를 추가해야 한다. 이 파일은 **gitignore 대상**이라 PR diff 에 안 보이고, 다른 머신에서 상수가 없으면 컴파일 에러가 난다.

미주입 시 `NoopFleetSink` 로 폴백해 관제만 꺼지고 앱 동작은 같다.

기기 키는 **쓰기 전용**이다. 유출돼도 조회·명령 생성은 불가하며(대시보드는 별도 비밀번호 세션), 피해가 "가짜 기기 행 생성" 노이즈로 한정된다. 서버의 `DEVICE_KEYS` 가 콤마 목록이라 무중단 로테이션이 된다.

## 6. 남은 일

1. **실기기 파일럿** — Sunmi 1대 + Windows 1대로 며칠 운영. 확인 대상: 강제종료 후 3분 `stale`/15분 `offline`, Windows 창 닫기 → `closing`, 로그인 전 "미배정" 표시, 원격 로그 요청 왕복, **릴리즈 APK 에서 설정 카드는 숨겨진 채 원격 명령은 동작**.
2. **로그 크기 실측** → `maxSourceBytes` 30MB 임계 확정.
3. **appfit_core 승격** — `core/` 4파일 이동 → import 헤더 치환 → barrel export 추가 → 테스트 이동 → `pubspec.yaml` 버전만 올리고 `bash tool/release.sh`(직접 `git tag` 금지) → 앱 `ref` 범프.
4. **DID 배선** — `did_fleet_snapshot.dart` + provider 3줄. `commandHandler` 는 주입하지 않는다(로그 수집 기능이 없으므로 `UNSUPPORTED` 자동 응답이 정답).

후속 후보(v1 에서 뺀 것): heartbeat 이력 테이블(D1 쓰기 한도), 명령 재배달 재시도, offline 시 Slack 통지, 서버 릴레이 다운로드(`BackendRelaySink`), per-device 토큰(스키마 필드만 예약됨).

## 7. 이전 설계안에서 바뀐 것

| 이전 문서 | 실제 |
|---|---|
| 수신단 미정 → `NoopSink` 만 | Cloudflare Workers + D1 로 확정, 대시보드까지 구현 |
| `appVariant` 필드(japan/korea) | **삭제.** `APPFIT_VARIANT` 가 제거돼 조달 불가 |
| 식별자 = 설치 UUID 고정 | `DeviceIdentityService` 정본 사용(시리얼 > MachineGuid > 설치 UUID). core 는 식별자를 만들지 않는다 |
| `MonitoringContext` 재사용 | builder 콜백으로 대체(§3) |
| `appFitDioProvider` 경유 | **전용 Dio.** 그 인스턴스는 인터셉터가 매장 토큰을 자동 주입해서, 재사용하면 매장 자격증명이 관제 서버로 흘러간다 |
| 명령 `eventType` enum | `String`. enum 이면 새 명령 타입마다 core 재릴리즈 + 앱 ref 범프가 강제된다 |
| 60초 heartbeat 로 명령 지연 해소 | **첫 명령 지연 최대 60초는 줄일 수 없다**(명령 생성 시점에 기기가 폴링 중이 아님). `nextIntervalSeconds` 는 미완료 명령이 있는 동안 15초로 낮춰 결과 회수·재시도만 빠르게 한다 |
