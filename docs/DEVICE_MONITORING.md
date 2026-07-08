# 기기·앱 모니터링 최소 시스템 — 설계

각 기기가 **① 앱 실행여부 ② 앱 버전 ③ OS 정보 ④ 기기 정보**를 스스로 보고하는 최소 모니터링 시스템의 설계 정본입니다.

> **상태: 설계 확정 (2026-07-07), 구현 미착수.** 수신단(백엔드/대시보드)이 미정이므로 앱 측 설계만 확정합니다. 스키마·엔드포인트 계약·식별자·아키텍처·비목표가 이 문서의 계약이며, 착수 시 아래 [구현 단계](#구현-단계)를 따릅니다.

## 배경

주력 디바이스(Sunmi D3 MINI 주문접수기, D2s_KDS, Windows POS)가 매장에 다수 배포돼 있지만, 어떤 기기가 지금 켜져 있고 어떤 앱/OS 버전으로 도는지 원격에서 볼 방법이 없습니다. 크래시·구버전 잔존·기기 방치를 사후에야 인지합니다.

조사 결과(2026-07-07) 값 대부분은 이미 런타임에서 수집되고(`_buildMonitoringContext()`, `PackageInfo`) 스키마(`MonitoringContext`)도 존재하며 상당수가 Sentry 태그로 올라갑니다. 순수 신규는 **기기 고유 식별자 + 실행여부(heartbeat) + 커스텀 수신단으로의 전송**뿐입니다.

## 확정된 결정

| 축 | 결정 | 함의 |
|---|---|---|
| 수신단 | **미정 — 앱 측만 우선 설계** | sink를 추상화, 기본 `NoopSink`. 실제 전송은 수신단 확정 후(Phase 4) |
| 기기 식별자 | **설치 UUID** | `Random.secure()` 16바이트 hex, SharedPreferences 영속. `uuid` 패키지 불필요 |
| 전송 채널 | **REST** (`appFitDioProvider`) | 현행 WebSocket은 수신 전용(`sink.add` 없음) — heartbeat를 태우려면 `send()` 신설 필요, 최소 경로 아님 |

## 데이터 소스 인벤토리

| 항목 | 조달처 | 상태 |
|---|---|---|
| 앱 버전 | `appInfoProvider` / `PackageInfo.version`+`buildNumber` (`lib/providers/app_info_provider.dart`) | ✅ 그대로 사용 |
| OS 정보 | `Platform.*` + Android `version.release`(현재 로그만) / Windows 버전 미수집 / iOS `systemVersion` | 🔶 `osVersion` 필드 조달 보강 필요 |
| 기기 정보 | `_buildMonitoringContext()` model·manufacturer (`lib/main.dart`) + **신규 deviceUuid** | 🔶 식별자 신규 |
| 앱 실행여부 | 없음 (appfit_core socket 60s heartbeat는 로컬 ghost-connection 감지 전용, 서버로 전송 없음) | ❌ heartbeat 신설 |

정적 스키마는 이미 appfit_core `MonitoringContext`(storeId/storeName/appType/appVersion/buildNumber/deviceModel/deviceManufacturer/environment)에 정의되어 있습니다 — 여기에 `deviceUuid`·`osVersion`·`appVariant`만 더합니다.

## 기기 식별자 (설치 UUID)

- **생성**: `Random.secure()`로 16바이트 → 32자리 hex(대시 없음). `uuid` 패키지를 추가하지 않습니다(의존성 최소화).
- **영속**: SharedPreferences. 민감정보가 아니므로 secure storage 불필요. 로컬 브랜치 `feature/remote-log-collection`(미푸시)의 기존 키 `KOKONUT_INSTALL_ID`를 재사용해 브랜치 코드 lift 마찰을 최소화합니다.
- **재사용**: 같은 브랜치의 `PreferenceService.getOrCreateInstallId()` 로직을 그대로 lift. 최초 1회 생성 후 불변, 이후 동일값 반환.
- **fleet 키 = `storeId` + `deviceUuid`.** 같은 매장 내 주문접수기/KDS가 storeId를 공유하므로 이 조합으로만 기기를 구분할 수 있습니다(현행 storeId 단독으로는 불가 — `KEY_IGNORE_OTHER_DEVICE_TASKS_KDS` 설정이 존재하는 이유).
- **수명**: 앱 재설치·데이터 삭제 시 새 UUID 발급을 감수합니다(최소 버전 트레이드오프). 재설치에도 안정된 식별이 필요해지면 브랜치 `DeviceIdentityService`의 시리얼 폴백 체인(Sunmi 시리얼 > Windows MachineGuid > installId)으로 확장합니다(스캐폴딩 이미 존재).
- 최소 버전은 `idSource = installId` 고정.

## 데이터 모델 — 정적/동적 분리

한 페이로드로 묶지 않습니다. 정적값(버전/OS/모델)을 매 heartbeat마다 재전송하지 않습니다.

### Register (정적 — 시작 시 1회 + 값 변경 시)

```jsonc
POST /v0/device/register            // 제안 경로 — 수신단 확정 시 합의
{
  "storeId": "PAIK001",             // shopCode (PreferenceService.getId)
  "deviceUuid": "9f2c…",            // 설치 UUID (32 hex)
  "appType": "ORDER_AGENT",
  "appVersion": "3.0.0",
  "buildNumber": "157",
  "platform": "android",            // android | windows | ios
  "osVersion": "13",                // Android release / Windows build / iOS systemVersion — 조달 보강 대상
  "deviceModel": "D3 MINI",
  "deviceManufacturer": "SUNMI",
  "environment": "live",            // dev | staging | live | japanLive
  "appVariant": "japan",            // japan | korea (AppEnv.region)
  "reportedAt": "2026-07-07T09:00:00Z"
}
```

정적값은 직전 전송분을 prefs에 캐시해 **변경 시에만** 재전송합니다.

### Heartbeat (동적 — 주기적, 작게)

```jsonc
POST /v0/device/heartbeat           // 제안 경로 — 수신단 확정 시 합의
{
  "storeId": "PAIK001",
  "deviceUuid": "9f2c…",
  "status": "online",               // online | closing (정상 종료 시 best-effort)
  "mode": "MAIN",                   // MAIN | KDS (선택)
  "businessOpen": true,             // 선택 (영업상태)
  "connection": "wifi",             // 선택 (wifi | ethernet | none)
  "appVersion": "3.0.0",            // 선택 (버전 드리프트 감지용 소량 에코)
  "reportedAt": "2026-07-07T09:01:00Z"
}
```

## 엔드포인트 계약 (제안)

- `POST /v0/device/register`, `POST /v0/device/heartbeat` — 인증은 `appFitDioProvider` 인터셉터가 `Authorization: Bearer`·`Waldlust-Project-ID`를 자동 주입합니다. **직접 `http`/`Dio` 금지** (CLAUDE.md 절대 규칙).
- **라우트 상수 위치**: appfit_core는 git 의존성(`ref: v1.0.15`)이라 core `ApiRoutes` 추가 = core 릴리즈(release.sh 단일 진입점) + 앱 ref 범프가 따라오는 크로스 repo 작업입니다. **최소 버전은 앱 로컬 상수로 시작**하고(인터셉터는 Dio 인스턴스에 붙으므로 경로 문자열 출처와 무관하게 적용됨), 서버 계약 확정 시 core `ApiRoutes`로 승격합니다.
- 성공 응답: `200 OK`.
- **확장 훅(선택, 최소 버전 미구현)**: 응답 바디에 서버→기기 명령을 실을 수 있게 계약만 예약 —
  `{ "command": { "eventType": "STATUS_REPORT_REQUESTED", "payload": { "commandId", "targetDeviceUuid", "shopCode" } } }`.
  브랜치 core의 `DeviceCommandType`(`LOG_UPLOAD_REQUESTED`/`STATUS_REPORT_REQUESTED`) + `DeviceCommandPayload.fromSocketMessage` wire 포맷과 정렬.
- 서버는 수신 시각으로 기기별 `last-seen`을 갱신합니다(아래 판정 참조).

## 앱 측 리포터 아키텍처

수신단이 미정이어도 앱 측을 완성할 수 있도록, 로그수집 브랜치의 `LogUploadSink` 스왑 패턴을 그대로 차용합니다.

```
DeviceReport / DeviceHeartbeat        // 페이로드 모델 (lib/models/ — 수동 작성 규칙, freezed 금지)
DeviceReportSink (abstract)           // register(report), heartbeat(beat)
 ├─ NoopSink                          // 기본 — 로그만 (수신단 미정)
 └─ (향후) BackendReportSink          // appFitDioProvider POST — Phase 4
deviceReportSinkProvider              // 단일 스왑 지점 (logUploadSinkProvider 패턴)
DeviceMonitorService                  // 오케스트레이션
```

- **register 발화**: 매장 로드 성공 시 1회 + 정적값 변경 감지 시. 페이로드는 `_buildMonitoringContext()` 재사용 + `deviceUuid`/`osVersion`/`appVariant` 추가.
- **heartbeat 발화**: 60초 타이머(`AppFitSyncIntervals.connectedSeconds` 상수 재사용), `status: online`.
- **closing 발화**: `AppLifecycleState.detached`/`paused` 시 1회 best-effort(`status: closing`). **기존 `appLifecycleObserverProvider`(`lib/providers/lifecycle_provider.dart`)를 listen** — 신규 observer를 만들지 않습니다. 단, 크래시·정전·강제종료는 이 신호도 없습니다(서버 임계값이 본선).
- **안전**: fire-and-forget, 모든 경로 try/catch로 예외 삼킴, UI·주문 흐름 절대 블로킹 금지. 오프라인(`connectivity_plus`)이면 skip.
- **배선 위치**: `monitoringSyncProvider`(이미 store 로드 시 identity를 MonitoringService에 push) 인근 + `appLifecycleObserverProvider` listen.
- **재사용 자산(브랜치)**: `DeviceStatusReporter.snapshot()`(스냅샷 조립)·`DeviceIdentityService`(식별자) 스캐폴딩을 참고/lift.

## Liveness 판정 (서버측 임계값 — 계약)

"실행여부"는 직접 관측이 불가능하므로 **last-seen 기반 추론**입니다. heartbeat 60초 기준:

| 상태 | 조건 |
|---|---|
| online | last-seen < 3분 (miss ≤ 2회) |
| stale | 3–15분 |
| offline | > 15분 |

- 크래시·정전은 아무 신호도 보내지 않음 → **서버 임계값이 유일한 판정 근거**. `status: closing`만 정상 종료를 구분합니다.
- 임계값은 서버 소유이지만 앱의 60초 케이던스가 그 값을 규정합니다.

## 재사용 자산 맵

| 용도 | 재사용 대상 |
|---|---|
| 인증 자동주입 전송 | `appFitDioProvider` + `ApiService` POST 패턴 (`lib/services/api_service.dart`) |
| 페이로드 조립 | `_buildMonitoringContext()` (`lib/main.dart`), core `MonitoringContext`/`OrderAgentMonitoringContext` |
| 식별자 생성·영속 | 브랜치 `getOrCreateInstallId()` / `DeviceIdentityService` (`feature/remote-log-collection`, 미푸시) |
| 케이던스 상수 | core `AppFitSyncIntervals` |
| sink 스왑 패턴 | 브랜치 `LogUploadSink` / `logUploadSinkProvider` |
| 서버→기기 명령 계약 | 브랜치 core `DeviceCommandType` / `DeviceCommandPayload` |
| store identity 배선 | `monitoringSyncProvider` (`lib/services/monitoring/monitoring_sync_provider.dart`) |
| lifecycle 신호 | `appLifecycleObserverProvider` (`lib/providers/lifecycle_provider.dart`) |

## 비목표 (최소 버전에서 하지 않음)

- WebSocket에 heartbeat 태우기 — 현행 소켓은 수신 전용, `send()` 신설 비용. REST가 최소 경로.
- 오프라인 영속 큐/재시도 폭주 — 오프라인은 skip, 서버가 부재로 offline을 추론.
- 하드웨어 시리얼·IMEI·MAC·IP·SSID 수집 — 설치 UUID로 충분(프라이버시·권한 회피). 필요 시 확장.
- 직접 `http`/`Dio` — 반드시 `appFitDioProvider` 경유.
- 매 heartbeat 전체 정적 페이로드 재전송.
- 모델 freezed 생성 — `lib/models/`는 수동 작성 규칙.

## 보류된 결정 (착수 전 확정 필요)

- **수신단 확정**: 커스텀 백엔드 엔드포인트 vs Sentry structured event vs Slack relay → `BackendReportSink` 구현 형태를 좌우(Phase 4).
- 관제 대시보드 / 저장·집계 / 알림 임계.
- 서버→기기 명령(`STATUS_REPORT_REQUESTED` 등) 연동 범위.
- OS 버전 수집 보강 범위(Windows build·Android release 저장).

## 구현 단계

- **Phase 0 (완료)**: 이 설계 문서 커밋.
- **Phase 1**: 식별자 — `getOrCreateInstallId()` lift + `DeviceReport`/`DeviceHeartbeat` 모델(수동 작성). `osVersion` 조달 보강.
- **Phase 2**: `DeviceReportSink`(abstract) + `NoopSink` + `deviceReportSinkProvider` + `DeviceMonitorService`의 register 조립(`_buildMonitoringContext()` 재사용) + 정적값 변경 감지.
- **Phase 3**: heartbeat 60초 타이머 + lifecycle `closing` 신호 + 오프라인 skip + fire-and-forget 안전망.
- **Phase 4**: 수신단 확정 후 `BackendReportSink`(앱 로컬 라우트 상수 + `ApiService` 스타일 POST; core `ApiRoutes` 승격은 core 릴리즈와 함께 별도 판단). ← 보류 결정 재개.

## 테스트 계획 (구현 시)

[TESTING.md](TESTING.md)의 PreferenceService seam·fake 패턴을 활용합니다.

- **P1**: 최초 실행 UUID 생성·영속, 재시작 시 동일값, clear-data/재설치 시 갱신.
- **P2**: register 페이로드 필드 스냅샷 테스트; 정적값 불변 시 미전송·변경 시에만 전송.
- **P3**: fake clock으로 60초 heartbeat 발화 카운트; 오프라인 시 skip; `detached` 시 `closing` 1회; **리포터 예외가 주문 흐름에 무영향**(에러 주입).
- **P4**: `BackendReportSink` POST 200 + 인증 헤더 자동 주입 확인; 서버 last-seen 반영; `flutter analyze` 통과.
