# 기기 로그 원격 수집 → Slack 전송 + 관재(원격관리) 토대

> **상태: main 병합 완료.** 설정화면 "로그 전송" 카드(수동 경로)가 동작한다.
>
> **원격 요청 경로는 이 문서가 아니라 [DEVICE_MONITORING.md](DEVICE_MONITORING.md) 가 정본이다.**
> 이 문서가 스캐폴딩으로 적어둔 `remote_command_handler.dart` / `remoteCommandHandlerProvider` /
> `device_status_reporter.dart` / 소켓 기기명령 가로채기는 **전부 채택되지 않았고 실제 코드에 없다.**
> 원격 명령은 WebSocket 이 아니라 관제 서버(`appfit-fleet`) heartbeat 응답에 실려 오며,
> 실행기는 `lib/services/fleet/order_agent_fleet_command_handler.dart` 다.
>
> 캡션·기간·파일명 조립도 위젯에서 `lib/services/log_collection/log_collection_request.dart`
> 로 추출됐다 — 수동 버튼과 원격 명령이 같은 함수를 쓰게 하려는 것이고, 포맷은 테스트로 고정돼 있다.

## 1. 목적/배경

특정 기기 로그를 AnyDesk 등 원격 프로그램 → 파일전송 → 폴더 탐색으로 수동 수집하던 상시 업무를 자동화한다. 트리거(설정화면 **수동 버튼** 또는 서버 **웹소켓 원격명령**)를 받으면 해당 기간 로그를 zip → **Slack 대화에 첨부 전송**. 나아가 매장명+매장코드+기기 시리얼로 매핑되는 **관재 대시보드**의 클라이언트 토대(기기 식별자, 상태 스냅샷)를 깐다.

확정 방향:
- **하이브리드 sink**: 지금은 Slack 직전송, sink 교체 인터페이스로 추후 **백엔드 경유** 무중단 전환.
- 백엔드 현재 불가 → 웹소켓 원격명령은 **수신 스캐폴딩만**(서버 푸시 미래). 실동작은 수동 버튼.
- 운영 식별 = 매장명 + 매장코드 + 기기 시리얼(예: D3MINI `DE33256H10784`).

## 2. 데이터 흐름

```
트리거(버튼 / 웹소켓 DeviceCommand)
  → LogCollectionService.collectAndUpload(from, to, caption, filename)
    1) flushLogBuffer()            // 버퍼(30개/2초) 강제 flush → 최신 로그 반영
    2) 플랫폼별 로그 열거 + 기간필터
        - Android: PlatformService.getLogDirPath()(native) → dart:io 직접 read
        - Windows: WindowsLogFileWriter.listLogFiles(from,to)
    3) archive(순수 Dart) in-memory zip → Uint8List
    4) caption 조립(DeviceIdentity: 매장명+코드+시리얼+기간)
    5) sink.upload(zipBytes, filename, caption)
        - SlackDirectSink (현재 동작)
        - BackendRelaySink (스텁, 미래)
  → Slack 대화에 zip 첨부 + initial_comment(caption)
```

## 3. 파일 맵

### 앱 (appfit_order_agent)
- `lib/services/log_collection/`
  - `log_upload_sink.dart` — `LogUploadSink`(추상) + `LogUploadResult`
  - `slack_direct_sink.dart` — Slack 3-step 업로드(현행 API)
  - `backend_relay_sink.dart` — **스텁**(향후 appfit Dio FormData 멀티파트)
  - `log_collection_service.dart` — 오케스트레이터(flush→열거→zip→sink) + `LogCollectionStage`
  - `remote_command_handler.dart` — **스캐폴딩** 원격명령 처리(버튼과 동일 경로)
- `lib/services/monitoring/`
  - `device_identity_service.dart` — Sunmi 시리얼 > Windows MachineGuid > 설치 UUID
  - `device_status_reporter.dart` — **스캐폴딩** 상태 스냅샷(전송 경로 미구현)
- `lib/providers/log_collection_provider.dart` — `logUploadSinkProvider`(sink 교체 단일 지점)/`logCollectionServiceProvider`/`deviceIdentityServiceProvider`/`deviceStatusReporterProvider`/`remoteCommandHandlerProvider` (+ `providers.dart` 배럴 export)
- `lib/widgets/settings/settings_log_collection_section.dart` — 설정화면 "로그 전송" 카드(자기완결형 ConsumerStatefulWidget) — `settings_right_panel.dart`에 삽입
- 수정: `lib/utils/logger.dart`(`flushLogBuffer()`), `lib/services/windows_log_file_writer.dart`(`flushPending()`/`listLogFiles()`), `lib/services/platform_service.dart`(`getLogDirPath()`/`getDeviceSerial()`), `lib/services/preference_service.dart`(`getOrCreateInstallId()`/시리얼 캐시 + `KEY_INSTALL_ID`/`KEY_DEVICE_SERIAL`), `lib/config/app_env.dart`(`slackBotToken`/`slackChannelId`/`hasSlackConfig`), `lib/providers/order/order_socket_manager.dart`(기기명령 가로채기), i18n 3로캘(`settings.log_collection.*`)
- Android native: `MainActivity.java`(`getLogDirPath()`, `getDeviceSerial()`), `NativeMethodHandler.java`(`getLogDirPath`/`getDeviceSerial` case)

**기기 시리얼 취득(다중 소스, `getDeviceSerial`)**: Sunmi 단말(예: D3 MINI `DE33256H10784`)은 프린터 서비스(`getPrinterSerialNo`)로 취득(검증됨). 그 외/비-Sunmi 단말(예: IM H092W `H092W24A1G00862`)은 `MainActivity.getDeviceSerial()` 이 SystemProperties(`ro.serialno`/`ro.boot.serialno`/`gsm.sn1`/`persist.sys.serialno`) → `Build.getSerial()`(READ_PHONE_STATE 보유 시) → `Build.SERIAL`(레거시) 순으로 best-effort. 모두 실패 시 null → Dart 가 설치 UUID 로 fallback.
  - **캐비엇**: 일부 ROM 은 SystemProperties 가 막혀 있을 수 있음. 그 경우 `READ_PHONE_STATE` 권한 추가 + 런타임 요청이 필요할 수 있다(현재 미추가 — 권한 프롬프트 회피). IM H092W 에서 실제 값이 안 나오면 이 권한 경로를 검토.

### 코어 (appifit_agent_core/appfit_core)
- `lib/src/events/device_command_types.dart` — `DeviceCommandType`(LOG_UPLOAD_REQUESTED/STATUS_REPORT_REQUESTED) + value/fromValue
- `lib/src/events/device_command_payload.dart` — `DeviceCommandPayload`(fromSocketMessage/isDeviceCommand/필드)
- `lib/appfit_core.dart` 배럴 export 2줄, `pubspec.yaml` 1.0.15→**1.1.0**, `CHANGELOG.md`, `test/device_command_payload_test.dart`(9개)

## 4. 재개 체크리스트 (남은 작업 — 순서대로)

1. **appfit_core v1.1.0 릴리즈** (정본 레포)
   - `feature/remote-log-collection`을 main에 머지(또는 main에서 cherry-pick).
   - `cd appifit_agent_core/appfit_core && bash tool/release.sh` (직접 `git tag` 금지 — 단일 진입점. packageVersion 자동 동기화).
2. **앱 pubspec 전환** (`appfit_order_agent/pubspec.yaml`)
   - 임시 `dependency_overrides:` 블록 **제거**.
   - `dependencies.appfit_core.ref` `v1.0.15` → **`v1.1.0`**.
   - `flutter pub get`.
   - ※ 현재 브랜치는 컴파일을 위해 로컬 path override가 들어가 있음(pubspec 주석 참고). 릴리즈 전까지만 유효.
3. **Slack 시크릿 + dart-define** (라이브 전제)
   - Slack 봇 토큰(`files:write` 스코프) 발급 + **운영 채널에 봇 초대**(`/invite`).
   - `.env` 에 `SLACK_BOT_TOKEN` / `SLACK_CHANNEL_ID` 두 줄만 넣으면 된다. 빌드 스크립트 6개가 전부
     `--dart-define-from-file=.env` 라 **스크립트 수정은 불필요하다**(이전 판의 "주입 라인 추가 필요"는 오기).
     미주입 시 버튼은 "설정 없음"으로 안전 실패.
4. **라이브 검증**: Android(Sunmi D3 MINI)·Windows에서 버튼 → Slack에 zip+캡션(매장명/코드/시리얼/기간) 도착 확인.
5. **네이티브 빌드 확인**: Java 신규 메서드 gradle 빌드(아직 미실행).
6. (미래) **백엔드 준비 시**: `BackendRelaySink` 구현(appfit Dio `FormData` 멀티파트) + `logUploadSinkProvider`를 그것으로 교체 + 서버가 `LOG_UPLOAD_REQUESTED` 푸시 + (필요시) `notifier_service.dart`에 `sendRaw` emit 추가(ACK/상태보고).

## 5. 테스트 방법

- **수동 버튼(MVP)**: 설정 → "로그 전송" 카드 → 날짜 프리셋 선택 → 버튼. 진행상태(정리/수집/압축/업로드) 후 Slack 채널에 zip 첨부 도착.
- **원격명령 스캐폴딩**: 가짜 소켓 메시지를 `order_socket_manager._handleAppFitEvent`에 흘리거나 `RemoteCommandHandler.handle(DeviceCommandPayload.fromSocketMessage(data))` 단위 테스트. data 예시는 §6.
- 정적/단위: 앱 `flutter analyze` + `flutter test`(현재 199 pass). 코어 `flutter test test/device_command_payload_test.dart`(9 pass).
- 엣지: 로그 0건(빈 기간) → "로그 파일이 없습니다", 봇 미초대 → `not_in_channel`, 토큰 미주입 → 안전 실패.

## 6. 서버 명령 wire 포맷 (백엔드팀 계약)

웹소켓 푸시 메시지(기존 주문 이벤트와 동일 envelope):
```json
{
  "eventType": "LOG_UPLOAD_REQUESTED",
  "payload": {
    "commandId": "uuid-상관키(ACK용)",
    "targetSerial": "DE33256H10784",   // null/생략 → 매장 전체 대상
    "shopCode": "MATA00001",            // 매장 한정(현재 매장과 다르면 무시)
    "fromDate": "2026-06-01",           // 생략 시 오늘
    "toDate": "2026-06-29"              // 생략 시 오늘
  }
}
```
- `STATUS_REPORT_REQUESTED`도 동일 envelope(payload는 target/shopCode만 의미). 현재 전송 경로 미구현(스냅샷 로깅까지).
- 클라이언트는 주문 dispatcher 진입 전 `DeviceCommandPayload.isDeviceCommand(data)`로 가로챔 → 주문 파이프라인 무영향(device command는 orderId 없음).

## 7. 리스크/주의

- **Slack 봇 토큰**: 클라이언트 바이너리에 박히면 추출 위험 → `files:write` 최소 스코프 + 단일 채널 한정. **최종형은 BackendRelaySink로 토큰을 서버에만 보관**(하이브리드 목표). Incoming Webhook은 파일 첨부 불가라 부적합.
- **Slack API**: 구 `files.upload` 폐기(2025-11). 현행 3-step 사용. Step2(upload_url)에 Authorization 헤더 금지(pre-signed). 응답은 HTTP 200이어도 body `ok`로 판정. 429는 Retry-After 1회 재시도.
- **Android 공개 경로**: `path_provider`로 `Documents/appfit` 못 얻음 → native `getLogDirPath`가 실제 기록 위치(Documents/appfit 우선 → getExternalFilesDir fallback)를 단일 제공. MANAGE_EXTERNAL_STORAGE 보유 전제.
- **flush 타이밍**: 버퍼(30개/2초)라 zip 직전 `flushLogBuffer()` 필수(Windows `_writeQueue` drain 포함).
- **대용량 zip**: in-memory라 장기간 선택 시 메모리 압박 → 기본 프리셋 짧게(오늘/7일). 일자별 로그 평균 크기 측정 후 상한 정책 검토.
- **ASCII-only**: C/C++/cmake/gradle/ps1/bat 비-ASCII 금지(Java는 무관). PowerShell UTF-8 BOM.

## 8. 확인 필요 항목
1. 운영 Slack 채널 ID + 봇 초대 완료 여부.
2. Slack 봇 토큰 주입 위치(빌드 스크립트/CI dart-define).
3. 채널 ID 매장별 분기 여부(고정 `AppEnv.slackChannelId` vs `PreferenceService` 키).
4. 일자별 로그 평균 크기 → zip 메모리 상한/기간 제한 정책.
5. (미래) 서버 inbound 프레임(ACK/상태보고) 수신 계약 — emit 스캐폴딩 활성화 시점.

> 설계 원본 플랜: `~/.claude/plans/wise-pondering-truffle.md`
