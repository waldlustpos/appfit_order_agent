---
name: project-device-monitoring-design
description: "기기·앱 모니터링 최소 시스템 설계 확정 (docs/DEVICE_MONITORING.md, 구현 미착수) — 수신단 미정, 착수 시 미푸시 브랜치 자산 lift"
metadata: 
  node_type: memory
  type: project
  originSessionId: fe24a01d-afb1-4618-b49b-0d9027a6487b
  modified: 2026-08-24T05:10:42.291Z
---

> **낡음(2026-08-24 확인)**: 이 메모리는 설계 단계(2026-07-07) 기록이라 "구현 미착수"가 더는 사실이 아니다. 백엔드는 실배포됐고(`appfit-fleet`, [[project_appfit_fleet_backend]]), `lib/config/fleet_config.dart`의 `FleetConfig.enabled`는 커밋 9483998("fleet 윈도우에서 활성화")로 **`true`**(Windows 한정). `docs/DEVICE_MONITORING.md` 상단 배너는 여전히 "⛔ 현재 비활성"이라고 돼 있어 문서-코드 드리프트 상태 — 다음에 그 문서를 만지면 배너부터 실코드 대조할 것.

기기·앱 모니터링(실행여부/앱버전/OS/기기정보) 최소 시스템 **설계만 확정**하고 `docs/DEVICE_MONITORING.md`로 커밋(626a73e, 2026-07-07). **구현 미착수.**(→ 위 낡음 표시 참조)

핵심 결정: 설치 UUID(`Random.secure()` 32hex, SharedPreferences `KOKONUT_INSTALL_ID`) / register(정적)·heartbeat(동적 60s) 분리 / `DeviceReportSink` 추상화(기본 NoopSink) / **수신단(백엔드 vs Sentry vs Slack) 미정** — Phase 4 보류.

착수 시 주의:
- **lift 대상 스캐폴딩이 미푸시 로컬 브랜치 `feature/remote-log-collection`에만 있음** (`getOrCreateInstallId()`, `DeviceIdentityService`, `DeviceStatusReporter`, core `DeviceCommandType`). 브랜치 유실 시 설계 문서 기준 재작성. [[project-remote-log-collection]] 참조.
- appfit_core는 git 의존성(ref v1.0.15) → core `ApiRoutes` 추가는 release.sh 릴리즈+ref 범프 크로스 repo 작업. 최소 버전은 앱 로컬 라우트 상수로 시작하기로 확정.
- lifecycle 신호는 기존 `appLifecycleObserverProvider` 재사용(신규 observer 금지), 배선은 `monitoringSyncProvider` 인근.
