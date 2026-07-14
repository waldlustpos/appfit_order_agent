---
name: project_remote_log_collection
description: "기기 로그 원격 수집→Slack 전송 + 관재 토대 — feature 브랜치 구현 완료, 릴리즈/라이브테스트 대기"
metadata: 
  node_type: memory
  type: project
  originSessionId: 30cfbf89-8cf4-4792-878d-4b19699092fa
---

기기 로그를 수동 버튼/웹소켓 원격명령으로 트리거 → 기간 로그 zip → Slack 첨부 전송하는 기능 + 관재(원격관리) 토대(기기 식별자, 상태 스냅샷). AnyDesk 수동 로그 수집을 대체.

**갱신(2026-07-07): 설정버튼 경로만 main 계열로 통합.** 새 브랜치 `feat/log-upload-slack`(off main `626a73e`)에 `feature/remote-log-collection` **머지 커밋 `8531292`** 생성(로컬만, 미푸시, main 미변경). 사용자가 "로그파일 Slack 직접 첨부" 재요청(Sentry attachment 안 검토했으나 봇토큰 불필요·크기제한 없음 이유로 SlackDirectSink 채택으로 회귀). **소켓 트리거(remote_command_handler + order_socket_manager 1.5 블록) 제외** — appfit_core v1.1.0 DeviceCommand 의존이라, v1.0.15 유지 위해 삭제(pubspec dependency_overrides도 제거). analyze ERROR 0, `flutter test` +201 pass. 남은 것: **Slack 봇토큰(files:write)+채널초대+`.env`에 SLACK_BOT_TOKEN/SLACK_CHANNEL_ID**(빌드는 `--dart-define-from-file=.env`라 스크립트 수정 불필요, docs/BUILD.md 반영), 라이브 검증(D3 MINI/Windows), main 병합·푸시. 소켓 트리거는 appfit_core v1.1.0 릴리즈 후 후속.

**상태(2026-06-30, 이전): 코드 완료, main 미변경, 미푸시.** 양 레포 모두 브랜치 `feature/remote-log-collection`:
- 앱 appfit_order_agent: 커밋 `353cd07`(+docs), 핵심 `08ff001`. analyze 에러 0, `flutter test` 199 pass.
- 코어 appifit_agent_core/appfit_core: 커밋 `650cefd`, version 1.0.15→**1.1.0**(DeviceCommandType/DeviceCommandPayload 추가, additive). 테스트 9 pass.

**핸드오프 문서**: `appfit_order_agent/docs/REMOTE_LOG_COLLECTION.md` (재개 체크리스트·파일맵·서버 wire 포맷·리스크 전부). 설계 원본: `~/.claude/plans/wise-pondering-truffle.md`.

**아키텍처**: 하이브리드 sink — 지금은 SlackDirectSink(현행 3-step files API, 구 files.upload 폐기), 추후 BackendRelaySink(스텁)로 교체. `lib/services/log_collection/` + `lib/services/monitoring/device_identity_service.dart`(Sunmi 시리얼>Windows MachineGuid>설치UUID). 웹소켓 기기명령은 order_socket_manager에서 dispatcher 진입 전 가로채기(RemoteCommandHandler) — 서버 푸시는 미래, 버튼이 실동작.

**재개 시 남은 gated 작업**(순서): ①appfit_core `tool/release.sh`로 v1.1.0 릴리즈 ②앱 pubspec의 **임시 dependency_overrides(로컬 path) 제거 + appfit_core ref v1.0.15→v1.1.0** ③Slack 봇토큰(files:write)+채널 초대, build_main.sh/build_windows.ps1에 `--dart-define=SLACK_BOT_TOKEN/SLACK_CHANNEL_ID` ④라이브 테스트(D3 MINI/Windows) ⑤네이티브 gradle 빌드 확인.

**Why**: 사용자가 "여기까지 마무리, 추후 이어서 구현·테스트" 요청. 백엔드 작업 불가 시점이라 소켓은 스캐폴딩만, 릴리즈는 아웃바운드라 보류함.
**How to apply**: 이 기능 재개 시 위 문서를 먼저 읽고 gated 체크리스트대로. appfit_core 릴리즈는 [[feedback_appfit_core_release]] 규칙(release.sh 단일 진입점, 직접 tag 금지) 준수. 현재 앱 pubspec에 로컬 override가 있으니 릴리즈 전까지만 유효함에 주의.
