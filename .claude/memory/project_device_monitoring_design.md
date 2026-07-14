---
name: project-device-monitoring-design
description: "기기·앱 모니터링 최소 시스템 설계 확정 (docs/DEVICE_MONITORING.md, 구현 미착수) — 수신단 미정, 착수 시 미푸시 브랜치 자산 lift"
metadata: 
  node_type: memory
  type: project
  originSessionId: fe24a01d-afb1-4618-b49b-0d9027a6487b
---

기기·앱 모니터링(실행여부/앱버전/OS/기기정보) 최소 시스템 **설계만 확정**하고 `docs/DEVICE_MONITORING.md`로 커밋(626a73e, 2026-07-07). **구현 미착수.**

핵심 결정: 설치 UUID(`Random.secure()` 32hex, SharedPreferences `KOKONUT_INSTALL_ID`) / register(정적)·heartbeat(동적 60s) 분리 / `DeviceReportSink` 추상화(기본 NoopSink) / **수신단(백엔드 vs Sentry vs Slack) 미정** — Phase 4 보류.

착수 시 주의:
- **lift 대상 스캐폴딩이 미푸시 로컬 브랜치 `feature/remote-log-collection`에만 있음** (`getOrCreateInstallId()`, `DeviceIdentityService`, `DeviceStatusReporter`, core `DeviceCommandType`). 브랜치 유실 시 설계 문서 기준 재작성. [[project-remote-log-collection]] 참조.
- appfit_core는 git 의존성(ref v1.0.15) → core `ApiRoutes` 추가는 release.sh 릴리즈+ref 범프 크로스 repo 작업. 최소 버전은 앱 로컬 라우트 상수로 시작하기로 확정.
- lifecycle 신호는 기존 `appLifecycleObserverProvider` 재사용(신규 observer 금지), 배선은 `monitoringSyncProvider` 인근.
