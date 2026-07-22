---
name: project_sentry_crons_liveness
description: "Sentry Crons로 \"앱 실행중\" 실시간 판정 end-to-end 검증(테스트만, 미도입). HTTP envelope 체크인 + tool 스크립트, 8.14.2엔 SDK API 없음"
metadata: 
  node_type: memory
  type: project
  originSessionId: edfe4dbe-f08c-458d-ab5b-0aa020e22d4f
  modified: 2026-07-22T01:36:58.772Z
---

Sentry **Crons(check-in 모니터)** 로 "기기가 앱 실행중인가"를 실시간 판정 가능 — 2026-07-22 end-to-end 검증(도입 아님, 1회 테스트).

**왜 Crons인가**: 현행 MonitoringService는 세션OFF(`enableAutoSessionTracking=false`)+트레이싱0 → 정상 앱은 Sentry 무흔적이라 "실행중" 판정 불가(에러/flapping만 도달). 세션을 켜도 실시간 uptime은 아님. Crons만이 "heartbeat 끊기면 감지" liveness 정답.

**검증된 동작**: HTTP **envelope 체크인**(`POST https://<host>/api/<projectId>/envelope/`, item type `check_in`, `monitor_config` 동봉)으로 **인증토큰·대시보드 없이 모니터 자동 upsert**. heartbeat 정지 → margin 경과 후 Sentry가 **missed 자동판정** → **`monitor_check_in_failure`(category outage) 이슈 생성**. 실측: 모니터 ok→error, missed 누적, 이슈 APPFIT-ORDER-AGENT-48 생성(정리: 모니터 삭제 + 이슈 resolved 완료).

**How to apply**:
- 도구: [tool/cron_heartbeat_test.dart](tool/cron_heartbeat_test.dart) (dev 전용, 앱 무관, `--count`/`--send-fail`/`--interval`). DSN은 `.env` SENTRY_DSN 파싱. 저장소 루트에서 `dart run`.
- 모니터 삭제 = org-level `DELETE /api/0/organizations/waldlust/monitors/<slug>/` (`.env` SENTRY_AUTH_TOKEN 스코프로 202 성공). project-level 경로는 404.
- **제약**: 락된 `sentry` 8.14.2 엔 `captureCheckIn` SDK API **없음**(grep 0). in-app SDK 경로는 `sentry_flutter` 9.x 업그레이드(듀얼레포 릴리즈) 전제 — 계획 `plans/sentry-immutable-bengio.md`. HTTP 경로는 SDK 무관하게 지금 가능.
- **비용**: Crons는 **모니터 개수당 과금** → fleet(매장/기기당 모니터) 도입 시 비용·입도(매장 vs 기기) 결정 필요.
- **미확인**: 이 이슈(무 store_id → catch-all)가 실제 `#appfit-alert-test` Slack까지 라우팅됐는지는 도구로 Slack을 못 읽어 미검증. 설계상 catch-all→test 채널 기대([[project_sentry_alert_routing]]).

관련: [[project_device_monitoring_design]](자체 heartbeat 정공법·미구현), [[project_sentry_alert_routing]], [[project_order_flow_simplification]].
