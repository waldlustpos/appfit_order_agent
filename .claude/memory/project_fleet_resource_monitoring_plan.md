---
name: project_fleet_resource_monitoring_plan
description: "Fleet에 기기 저장공간/메모리 현황 추가 — 설계 완료, 구현 미착수"
metadata: 
  node_type: memory
  type: project
  originSessionId: d1693d6b-f3bc-4c29-94f3-2087243849f8
  modified: 2026-08-20T01:33:50.467Z
---

Fleet(기기 관제) heartbeat에 저장공간·메모리 여유/전체 바이트를 실어 보내고 [[project_appfit_fleet_backend]] 대시보드에 표시하는 설계를 완료해 `/Users/kimsungchun/.claude/plans/fleet-golden-matsumoto.md`에 저장함. 구현은 아직 시작 안 함(2026-08-20).

**결정된 방식**: 네이티브 코드 직접 작성(Android `NativeMethodHandler.java`에 `getDeviceResources` 케이스 + `StatFs`/`ActivityManager.MemoryInfo`, Windows는 `windows/runner/` C++이 아니라 이 프로젝트 관례대로 `win32` Dart 패키지를 deferred import로 — `GetDiskFreeSpaceEx`/`GlobalMemoryStatusEx`). 후보였던 `system_info2` 패키지(저장공간+메모리 API 동시 제공)는 pub.dev에서 "게시자 미검증"으로 플래그되어 공급망 리스크로 기각.

**범위**: 앱(`order_agent_fleet_snapshot.dart`의 `FleetRuntime.extra`에 담음, `FleetDeviceInfo`엔 절대 넣지 않음 — 넣으면 register가 값 바뀔 때마다 재발화) + 백엔드(`appfit-fleet`의 devices 테이블 컬럼 4개 추가, D1 마이그레이션은 로컬 검증 후 원격은 별도 사용자 확인 필요) 둘 다 포함.

appfit_core(공통 레포) 수정은 불필요 — `extra` 슬롯이 이미 공개 API라 태그+푸시+ref 범프([[project_appfit_core_dual_repo]]) 안 거쳐도 됨.

**Why**: 매장 기기의 저장공간·메모리 부족이 인쇄 실패/크래시의 선행 지표가 될 수 있는데 지금은 관제에서 확인 불가.
**How to apply**: 이 기능을 다시 착수할 때 plan 파일을 먼저 열어서 파일 경로·줄 번호·정확한 코드 스니펫을 재활용할 것 — Android/Windows 네이티브 삽입 지점, 백엔드 index.ts/schema.sql/dashboard.ts 수정 지점까지 이미 직접 코드 검증 완료된 상태.
