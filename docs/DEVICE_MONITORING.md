# 기기 관제 (Fleet)

매장 기기(Sunmi D3 MINI 주문접수기, D2s_KDS, Windows POS)의 **① 앱 실행 상태 ② 기기 정보 ③ 원격 로그 요청**을 다루는 최소 관제 시스템.

> ## ✅ 활성 — Windows 한정 (2026-08-21~)
>
> **`FleetConfig.enabled = true`**(커밋 9483998, "fleet 윈도우에서 활성화"). 다만 실제로 관제가 도는 범위는 이 상수 하나가 아니라 아래 네 게이트 전부다 — Windows 플랫폼 게이트가 여전히 걸려 있어 **Android 기기는 이 상수와 무관하게 관제 대상이 아니다.**
>
> 되돌릴 땐 `lib/config/fleet_config.dart` 의 이 상수 하나만 false 로 바꾸면 된다.
>
> **상태: 배포 완료(2026-07-31), appfit_core 승격 완료(2026-08-03), 대상 매장 화이트리스트 게이트 추가(2026-08-19), Windows 대상 활성화(2026-08-21), 실기기 파일럿 미실시.** 백엔드는 별도 레포 `appfit-fleet`(Cloudflare Workers + D1), 공통 리포터는 `appfit_core`(`appifit_agent_core` 레포, v1.0.18~), 앱 측 전용 코드는 `lib/services/fleet/`.
>
> **관제는 Windows 대상 매장에서만 돈다** — `FleetConfig.enabled` AND `.env` 설정(§5) AND **Windows 플랫폼**(`fleet_provider.dart` 의 `fleetEnabledProvider`, 우선 배포 범위 한정. 다음 업데이트에서 조건이 바뀔 수 있음) AND 원격 화이트리스트(§5-1) 네 게이트를 모두 통과해야 한다.
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

[Lightsail 정적 호스트]             GET /api/deployed-versions ◀─── 서버 배포 버전 바
 OTA version JSON ×4  ─────────────▶   (Worker 가 pull, 5분 캐시)
 fleet_sunmi_mammoth_version.json ─▶
 apk/zip ×4            ◀───────────  GET /api/download/:id (요청마다 즉시 프록시, 저장 안 함)
```

명령은 **heartbeat 응답에 실어 보낸다(piggyback)**. AppFit 의 WebSocket 은 수신 전용(`sink.add` 없음)이라 push 채널을 새로 뚫으려면 서버팀 의존이 생긴다.

로그 파일은 관제 서버에 저장하지 않는다. 기기가 기존 `SlackDirectSink` 로 zip 을 올리고, 서버는 요청·진행·결과 상태만 들고 있는다.

### 서버 배포 버전 표기 (대시보드 상단 바)

기기가 보고한 버전 옆에 **"지금 서버에 올라가 있는 최신"** 을 같이 띄운다. 표기 단위는 5개이며 정본은 `appfit-fleet/src/types.ts` 의 `RELEASE_ARTIFACTS` 다.

| | Appfit (Tier 0) | Mammoth (Tier 1) | Sunmi Mammoth |
|---|---|---|---|
| **Android** | OTA `_release` | OTA `_mammoth_release` | Sunmi App Store |
| **Windows** | OTA 무접미 | OTA `_mammoth_windows` | — 해당 없음 (Sunmi 는 Android 전용 하드웨어) |

- **Worker 가 정적 호스트를 직접 읽는다(pull).** 배포 스크립트가 fleet 로 보고(push)하게 하지 않은 이유는, 보고가 실패하면 "배포는 됐는데 표기는 옛날 값"이라는 조용한 거짓말이 남기 때문이다. OTA version JSON 은 앱이 업데이트를 판정할 때 보는 바로 그 파일이라 그대로 읽는 쪽이 정의상 맞다. **`deploy_apk.sh`/`deploy_windows.ps1` 은 이 기능과 무관하다 — 수정하지 않았다.**
- 표기 단위는 **빌드번호**다. OTA version JSON 에 semver 가 없고(`{"version": 189}`), 그게 앱이 업데이트를 판정하는 단위이기도 하다.
- 배포 시각은 별도로 기록하지 않고 정적 파일의 `Last-Modified` 를 쓴다 — 업로드가 곧 배포다.
- Windows 채널 2개는 `deploy_windows.ps1` 의 `Out-File -Encoding utf8` 때문에 응답 앞에 **UTF-8 BOM** 이 붙는다. Worker 가 파싱 전에 벗겨낸다(BOM 을 그대로 두면 `JSON.parse` 가 터진다).
- **Sunmi 칸만 조회 지점이 없다.** `/store-upload` 스킬 5-1단계가 같은 호스트에 `fleet_sunmi_mammoth_version.json` 을 올린다. 아직 한 번도 안 올렸으면 "배포 기록 없음"으로 뜬다(404 는 장애가 아니다). **이 파일은 채널이 아니다** — 앱이 폴링하지 않고 아티팩트도 딸려 있지 않아, `fleet_stores.json`(§5-1) 과 같은 성격의 수동 자산이라 `fleet_` 접두사를 쓴다.
- 기기 목록 필터에 **OS(Android/Windows)** 가 함께 추가됐다. 판정 근거는 기기가 register 시 보내는 `platform` 필드다.

이 기능은 **`FleetConfig.enabled` 와 무관하게 동작한다** — 앱이 아무것도 보고하지 않아도 대시보드는 배포 버전을 보여준다. 앱 측 코드는 전혀 관여하지 않는다.

### 설치 파일 다운로드

배포 버전 카드 중 4개(Android/Windows × common/mammoth)에는 다운로드 링크가 붙는다 — `GET /api/download/:id`. 최초 설치 등 수동 배포 시 대시보드 로그인 한 번으로 apk/zip 을 바로 받을 수 있게 하려는 용도다.

- **fleet 이 파일을 들고 있지 않는다.** Worker 가 요청마다 Lightsail 원본을 그대로 스트리밍(passthrough)한다 — R2 미러를 두지 않은 이유는 배포 스크립트를 안 건드리기 위해서다(위 pull 설계와 같은 논리: 사본을 만들면 사본만 갱신 실패할 여지가 생긴다).
- Sunmi Mammoth 는 다운로드가 없다. 실제 배포 파일이 Sunmi 콘솔 내부에 있어 URL 자체가 없고, `android_mammoth` 와 바이트가 같다고 대신 내려주면("같은 서명키+versionCode" 불변식, 위 채널 표) "Sunmi 전용 다운로드"라는 표시가 거짓이 된다 — 그 카드는 다운로드 없이 버전 표기만 한다.
- 접근 권한은 나머지 `/api/*` 와 동일하게 대시보드 세션 로그인이 필요하다 — 인증 없는 공개 링크가 아니다.

## 2. 파일 맵

| 경로 | 역할 |
|---|---|
| `appfit_core/lib/src/fleet/fleet_models.dart` | 와이어 모델(수동 toJson/fromJson) |
| `appfit_core/lib/src/fleet/fleet_sink.dart` | `FleetSink` 추상 + `NoopFleetSink` |
| `appfit_core/lib/src/fleet/http_fleet_sink.dart` | 전용 Dio 로 Worker 에 전송 |
| `appfit_core/lib/src/fleet/fleet_reporter.dart` | 타이머·백오프·명령 디스패치 |
| `lib/services/fleet/order_agent_fleet_snapshot.dart` | 앱 전용 스냅샷 조달 |
| `lib/services/fleet/order_agent_fleet_command_handler.dart` | 앱 전용 명령 실행(로그 수집) |
| `lib/providers/fleet_provider.dart` | sink 교체 지점 + 생명주기 배선 + 대상 매장 게이트 |
| `lib/services/fleet/fleet_store_allowlist_service.dart` | 대상 매장 목록 조회·캐시·판정(§5-1) |
| `lib/config/fleet_config.dart` | 대상 매장 목록 URL·타임아웃 |
| `fleet_targets/fleet_stores.json` | 대상 매장 목록 **레포 정본**(서버 파일은 사본) |
| `lib/services/log_collection/log_collection_request.dart` | 캡션·기간·파일명 **정본**(수동/원격 공용) |
| `appfit_core/test/fleet_*_test.dart` (`appifit_agent_core` 레포) | fakeAsync 21 + 모델 + sink + 실서버 왕복 |

### `appfit_core` 로 승격 완료 (v1.0.18, 2026-08-03)

기기 실행상태·기기정보 보고 + 원격 명령 리포터는 이제 `appfit_core/lib/src/fleet/`(별도 레포 `appifit_agent_core`)에 있고, `package:appfit_core/appfit_core.dart` barrel 로 export 된다. DID·KIOSK 도 같은 코드를 재사용할 수 있다.

승격 전 앱 안에서 먼저 구현하며 `lib/services/fleet/core/`가 앱 코드를 import 하지 않게 지켰던 `fleet_core_isolation_test.dart`는 승격 완료로 폐기했다 — 코드가 물리적으로 다른 패키지에 있어 더 이상 구조로 강제할 필요가 없다.

앱 전용 파일(`order_agent_fleet_snapshot.dart`/`order_agent_fleet_command_handler.dart`)은 `PreferenceService`·`storeProvider`·`DeviceIdentityService`·`LogCollectionService` 등 앱 의존이 있어 승격 대상이 아니다 — core 쪽(`FleetReporter`)은 이들을 모르고 `Future<FleetSnapshot?>`/`FleetCommandHandler` 콜백만 안다.

core 수정 시 반영 절차는 `appifit_agent_core` 레포 안에서 `cd appfit_core && bash tool/release.sh`로 태그+푸시한 뒤, 소비 앱 `pubspec.yaml`의 `ref:`를 새 태그로 올리고 `flutter pub get` — 직접 `git tag`/`git push` 금지.

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

## 5-1. 대상 매장 화이트리스트

§5 의 `.env` 설정만으로 켜면 **그 빌드를 받은 전 매장이 동시에 관제에 붙는다.** 파일럿은 실기기 몇 대로 시작해야 하고, 무료 티어 천장도 heartbeat 하루 10만회(60초 간격 = 59대)라 규모상으로도 곤란하다. 그래서 빌드 타임 설정 위에 **런타임 매장 게이트**를 한 겹 얹는다.

```
http://waldpay.kokonutstamp2.com/fleet_stores.json   (OTA 와 같은 플랫 디렉토리)
        │  GET (전용 Dio — 앱 dioProvider 는 baseUrl·인증 인터셉터가 붙어 못 쓴다)
        ▼
FleetStoreAllowlistService.refresh()  ──▶ PreferenceService 캐시(성공 시에만 갱신)
        │  isTargeted(storeId) — 대문자 정규화 후 완전일치
        ▼
fleetTargetedProvider ──▶ fleetEnabledProvider = hasFleetConfig && targeted
                              ├ fleetSinkProvider      : false → NoopFleetSink
                              ├ fleetConnectionStatus  : false → disabled(앱바 아이콘 숨김)
                              └ fleetSyncProvider      : false → reporter.stop()
```

두 게이트의 역할이 다르다. `AppEnv.hasFleetConfig` 는 "이 빌드가 관제를 말할 수 있는가", 화이트리스트는 "이 매장이 지금 관제 대상인가"다.

**목록은 브랜드·플랫폼 공용 단일 파일이다.** 매장 코드가 이미 전역 고유해서 OTA 처럼 채널을 가를 이유가 없다. `FleetConfig` 가 `BuildBrand` 를 참조하지 않는 것도 같은 이유이며, 참조하면 `test/config/build_brand_scope_test.dart` 화이트리스트를 늘려야 하는데 그 목록의 취지(OS 셸 아이덴티티 + 배포 채널)에 맞지 않는다.

**매칭은 완전일치만.** 프리픽스 와일드카드를 지원하지 않는다 — 손이 미끄러져 브랜드 전체를 켜는 사고를 구조적으로 막는다.

### 조회 시점과 실패 처리

조회는 **로그인 성공 시 1회**다(`login_screen.dart` 의 성공 블록, `setStoreModel()` 직후). 업데이트 채널 정책 재조정·브랜드 테마 reconcile 이 이미 모여 있는 자리이고, 수동/자동 로그인 두 경로가 모두 `_login()` 을 통과한다. 로그인을 막지 않도록 fire-and-forget 이다.

**Windows 만 조회한다.** `reconcileFleetTarget` 이 `Platform.isWindows` 를 먼저 판별해 Android 는 로그인마다 나가는 이 요청 자체를 만들지 않는다 — 최종 판정(`fleetEnabledProvider`)에서 Android 는 어차피 OFF 이므로 도달하지 않을 활성화를 위해 요청을 낼 이유가 없다. Android 도 켤 때는 여기와 §상단 요약(`fleetEnabledProvider`) 두 곳의 `Platform.isWindows` 가드를 함께 지워야 한다.

**조회 실패는 관제를 끄지 않는다.** 마지막으로 성공한 목록이 캐시에 남아 있으면 그걸로 판정한다. 매장 인터넷이 잠깐 끊겼다고 파일럿 기기가 대시보드에서 사라지면, 정작 관제가 필요한 상황에서 관제가 없어진다. 캐시조차 없는 기기(최초 설치)만 OFF 다.

같은 이유로 **앱 시작 시에도 캐시로 시드한다**(`fleetTargetedProvider` 의 초기값 = 캐시된 목록 ∩ `PreferenceService.getId()`). 로그인 훅만 두면 §3 의 "로그인 못 한 기기도 보인다" 성질이 통째로 사라지는데, 그게 오히려 가장 먼저 확인하고 싶은 상태다. 저장된 매장 코드는 재시작 직후에도 남아 있으므로 파일럿 매장 한정으로 로그인 전 구간의 보고가 유지된다.

`stores` 가 빈 배열이거나 키가 없는 것은 오류가 아니라 **"전부 OFF"** 라는 정상 지시다(파일럿 중단). 반면 형식이 어긋난 응답(404 HTML 등)은 캐시를 덮지 않는다. 이 구분을 `test/services/fleet/fleet_store_allowlist_service_test.dart` 가 고정한다.

### 운영

레포 정본은 `fleet_targets/fleet_stores.json`, 업로드는 수동 scp 다 — 배포 스크립트는 아티팩트 + version JSON 2개만 다룬다. 절차는 [fleet_targets/README.md](../fleet_targets/README.md).

목록을 고친 뒤 대상 기기가 **재로그인(또는 앱 재시작 → 자동 로그인)** 해야 반영된다.

이 파일은 평문 HTTP · 무인증 공개 파일이 된다. 매장 코드는 곧 로그인 ID 이므로 목록 공개는 계정 열거를 조금 돕는다 — 파일럿 범위에서 수용하기로 한 트레이드오프다.

## 6. 남은 일

1. **실기기 파일럿** — Sunmi 1대 + Windows 1대로 며칠 운영. 확인 대상: 강제종료 후 3분 `stale`/15분 `offline`, Windows 창 닫기 → `closing`, 로그인 전 "미배정" 표시, 원격 로그 요청 왕복, **릴리즈 APK 에서 설정 카드는 숨겨진 채 원격 명령은 동작**.
2. **로그 크기 실측** → `maxSourceBytes` 30MB 임계 확정.
3. ~~**appfit_core 승격**~~ — 완료(v1.0.18, 2026-08-03). 실기기 파일럿 검증 전에 앞당겨 진행했다.
4. **DID 배선** — `did_fleet_snapshot.dart` + provider 3줄. `commandHandler` 는 주입하지 않는다(로그 수집 기능이 없으므로 `UNSUPPORTED` 자동 응답이 정답). core 승격이 끝나 이제 `package:appfit_core/appfit_core.dart` 하나만 import 하면 된다.

후속 후보(v1 에서 뺀 것): heartbeat 이력 테이블(D1 쓰기 한도), 명령 재배달 재시도, offline 시 Slack 통지, 서버 릴레이 다운로드(`BackendRelaySink`), per-device 토큰(스키마 필드만 예약됨).

**원격 화면제어 확장은 별도 문서로 분리했다** — [REMOTE_CONTROL_ANALYSIS.md](REMOTE_CONTROL_ANALYSIS.md). 결론만: 자체 구현(90~148 PD)이 아니라 Sunmi MDM + MeshCentral 조합(13~22 PD)을 권고하고, 착수 전에 결정 게이트 실험 3개를 먼저 돌린다. 어느 경로든 **대시보드 운영자 인증 개편이 선행 조건**이다(현재 공유 비밀번호 1개).

## 6-1. 규모 확장

기기 수가 늘 때의 간격별 수용 대수·비용·수정 범위는 `appfit-fleet/SCALING.md` 에 계산해 뒀다. 앱 쪽에서 미리 알아둘 것 하나:

**`fleet_reporter.dart` 의 `maxIntervalSeconds = 600` 은 서버 지시 간격의 클라이언트측 상한이다.** 즉 서버가 10분보다 긴 간격을 지시해도 앱이 10분으로 깎는다. 500대를 넘겨 간격을 더 늘려야 하는 시점에 이 값이 걸리는데, 그때는 이미 매장에 나가 있는 **전 기기의 앱을 업데이트해야** 한다.

값을 3600 정도로 미리 올려두면 지금 동작은 전혀 바뀌지 않으면서(서버가 60초를 보내면 60초로 돈다) 이후 간격 조절이 서버 상수 한 줄로 끝난다. **기기가 매장에 나가기 전에 결정할 것.** 대가는 서버가 잘못된 값을 보냈을 때 기기가 최대 1시간 조용해질 수 있다는 점이다(현재는 최대 10분).

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
