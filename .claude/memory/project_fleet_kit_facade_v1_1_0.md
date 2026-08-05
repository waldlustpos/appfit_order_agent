---
name: project_fleet_kit_facade_v1_1_0
description: appfit_core v1.1.0 FleetKit 파사드 릴리즈 + order_agent/did 적용 완료 상태
metadata: 
  node_type: memory
  type: project
  originSessionId: b72dd119-21b4-4b80-936c-03c94cbcf3b6
  modified: 2026-08-05T05:33:49.023Z
---

appfit_core v1.1.0 릴리즈 완료(commit 9fe47c1+28b1c23, tag v1.1.0, origin push 완료). `FleetKit` 파사드가 앱당 fleet 채택 비용을 ~510줄→~40줄로 줄임. [project_fleet_monitoring](project_fleet_monitoring.md)의 후속.

**core 신규 파일**: `src/device/device_probe.dart`(AppFitDeviceProbe/PlatformDeviceProbe), `src/fleet/fleet_identity.dart`(FleetIdentityResolver — 배타적 슬롯: 앱이 identity 주입 시 core 기본 구현 자체가 생성 안 됨), `fleet_app_state.dart`(FleetAppState — 앱이 매 틱 주는 유일한 값), `fleet_snapshot_assembler.dart`(범용화된 스냅샷 빌더 + extra 필드 스칼라 정제), `fleet_kit.dart`(파사드, WidgetsBindingObserver 내장). `FleetConnectionStatus`/`ObservingFleetSink`는 order_agent에서 core로 승격. `FleetRuntime.extra`(Map, 2KB 상한) 신규 — FleetDeviceInfo에는 절대 미포함(넣으면 fingerprint 오염→boot_count 크래시루프 지표 훼손).

**order_agent**: ref v1.0.18→v1.1.0 + 로컬 fleet_connection_status.dart/observing_fleet_sink.dart 삭제 + app_bar_widget.dart import 정리(원자적 커밋, order_agent 자체 브랜치 feat/fleet-monitoring에 로컬 커밋만, 미푸시). **FleetKit 전체 이전은 하지 않음** — 실기기 파일럿 대기 중이라 배선을 안 건드림. 기존 fleet_provider.dart(138줄) 그대로 유지.

**did**: 최초 fleet 채택 완료(main 브랜치에 로컬 커밋 a68d6fa, 미푸시). `MainActivity.java`에 `getDeviceSerial` 네이티브 핸들러 신규 추가(order_agent에서 이식, Sunmi 분기 제외 — DID는 일반 Android 셋톱박스). `lib/providers/fleet_provider.dart` 신규(32줄), `commandHandler` 미주입(로그수집 기능 없음 → UNSUPPORTED 자동). `preventive_restart_service.dart`에 재시작 전 `reportClosing()` 훅 추가.

**의도적으로 스킵한 것**: `extra['restartReason']` 값 실제 채워넣기(6시간 예방재시작 원인 표시) — `readAppState`가 동기 클로저라 재시작 직전 영속화한 플래그를 다음 부팅에서 비동기로 읽어와야 하는 부트스트랩 복잡도 대비 가치가 낮다고 판단. `reportClosing()` 훅만 연결. 서버측 crash-loop 임계값 app_type별 분리(appfit-fleet 레포)도 미착수.

**did/test/widget_test.dart**: Flutter 기본 카운터 템플릿이 그대로 남아있어 원래부터(fleet 작업과 무관하게) 실패 중이었음(git stash로 확인). DID 실제 UI와 무관한 죽은 테스트.

**Why**: 세 번째 앱(did) 채택 시 앱당 코드량이 과도(~510줄)했고 DID의 Windows 기기정보 수집에 실제 버그(deviceModel=Unknown)까지 있었음 — 공용화가 실질 가치 있었음.

**How to apply**: 네 번째 앱(kiosk 등) 붙일 때는 `appfit_core/docs/FLEET_ADOPTION.md` 절차 그대로 따르면 ~34줄. order_agent를 FleetKit으로 이전하는 PR은 "실기기 파일럿 안정화 2주 후"가 게이트 — 그 전에 만지면 파일럿 결과 오염. core 다음 마이너 릴리스 후보: `FleetRuntime.extra` 실사용례(restartReason), monitoring probe 통합([project_ui_perf_audit_2026_07](project_ui_perf_audit_2026_07.md)류 후속과 무관,별도).

## v1.1.1 — DID 실기기(IM-H092) 첫 테스트에서 발견 (2026-08-05)

**증상**: 로그에 `(noop) register/heartbeat` 만 찍히고 대시보드(`appfit-fleet.sckim.workers.dev`)에 기기가 안 보임.

**근본 원인 (설정 누락, 코드 버그 아님)**: DID `.env` 에 `FLEET_BASE_URL`/`FLEET_DEVICE_KEY` 자체가 없었음 — order_agent 는 이미 있었지만 DID 는 이번에 처음 추가하는 앱이라 `.env` 값 자체가 비어 있었음. → order_agent `.env` 의 값(서버 `DEVICE_KEYS` 는 앱 구분 없는 공유 Bearer 키)을 그대로 복사해 DID `.env` 에 추가. `flutter run --dart-define-from-file=.env` 로 재실행하면 HttpFleetSink 로 전환된다.

**부수 발견 + 실제 버그 (core 수정)**: 로그의 `연결 상태 전환: disabled → connected` 자체도 오판이었음 — `FleetKit` 이 목적지가 `NoopFleetSink` 여도 항상 `ObservingFleetSink` 로 감싸서, Noop 이 늘 `success:true` 를 돌려주는 걸 그대로 "connected" 로 반영했음. order_agent 원본 `fleetSinkProvider` 는 Noop 일 때 감싸지 않는 조건이 있었는데 FleetKit 파사드로 옮기며 빠뜨림. **v1.1.1 (commit 31def23, tag 푸시완료)** 로 수정: `destination.isConfigured` 일 때만 감쌈 + 회귀 테스트 추가(`fleet_kit_test.dart`). DID ref 도 v1.1.1 로 재범프(commit 8bb212e, 로컬만).

**Why**: "DID 채택은 항상 뭔가를 찾아낸다"는 v1.1.0 릴리스 노트의 예상이 실제로 적중한 사례.
**How to apply**: 다음 앱 온보딩 때도 `.env` 에 FLEET_BASE_URL/FLEET_DEVICE_KEY 를 빠뜨리기 쉬우니 `FLEET_ADOPTION.md` 체크리스트에 명시적으로 강조할 것. `(noop)` 로그가 보이면 항상 dart-define 누락부터 의심.
