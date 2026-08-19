---
name: project_fleet_store_allowlist_gate
description: "Fleet 관제를 feat/mammoth-dedicated-build 에 이식 + 대상 매장 화이트리스트 게이트 추가 (커밋 완료·미푸시, 실기기 미검증)"
metadata: 
  node_type: memory
  type: project
  originSessionId: 7202b256-696c-439b-b197-b9aeb235ae84
  modified: 2026-08-19T01:13:13.483Z
---

2026-08-19. `feat/fleet-monitoring` 의 Fleet 관제를 `feat/mammoth-dedicated-build` 에 이식하고, **OTA 정적 호스트의 매장 코드 화이트리스트로 게이팅**하는 기능을 추가했다. analyze 에러 0(issue 17 = 변경 전과 동일), test 544건 전량 통과. `feat/mammoth-dedicated-build` 에 **커밋 완료(미푸시) · 실기기 미검증.** 서버에는 `fleet_stores.json`(MMTH00084 단독) 업로드까지 마침.

**이식 방법이 핵심**: `git merge` 가 아니라 **파일 단위 `git checkout`**. fleet 브랜치엔 이미 main 에 반영된 displayOrder 정렬 커밋 4개가 섞여 있고, `pubspec.yaml` 의 appfit_core ref 가 v1.1.0(현재 브랜치는 v1.2.0)이라 머지하면 다운그레이드된다. merge-base(`7cbdc00`) 이후 현재 브랜치 변경 이력이 0인 파일 12개는 통째 체크아웃, 양쪽 다 바뀐 4개(`main.dart`·`platform_service.dart`·`lifecycle_provider.dart`·`app_bar_widget.dart`)만 손으로 병합했다. v1.2.0 의 `FleetReporter` 생성자는 브랜치 사용 시그니처와 호환.

**게이트 구조** — 이중이다. `AppEnv.hasFleetConfig`(빌드타임 `.env`) AND `fleetTargetedProvider`(런타임 매장) → `fleetEnabledProvider` → sink/status/sync 셋이 함께 참조. 게이트가 뒤집히면 Riverpod 재빌드가 sink→reporter→sync 로 연쇄하고 구 reporter 는 기존 `onDispose(reporter.stop)` 이 정리한다 — 새 teardown 코드 불필요.

**설계 결정 4가지(사용자 확정)**: 목록은 전 빌드 공용 단일 파일(`http://waldpay.kokonutstamp2.com/fleet_stores.json`) / 조회 실패 시 마지막 캐시로 판정, 캐시도 없으면 OFF / 매장 코드 완전일치만(프리픽스 와일드카드 없음) / 로그인 시 1회 조회.

**요청 범위를 넘어 추가한 것**: 앱 시작 시 `fleetTargetedProvider` 를 캐시된 목록 ∩ `prefs.getId()` 로 시드. 로그인 훅만 두면 **로그인에 실패한 기기**(= 가장 관제로 보고 싶은 상태)가 대시보드에서 사라진다.

**직접 만든 새 실패경로 하나**: 게이트가 생기며 `fleetSinkProvider` 가 재빌드될 수 있게 됐는데, 구 sink 의 in-flight 응답이 dispose 된 `ref` 로 `onStatus` 를 부르면 예외가 난다. `var disposed` + `ref.onDispose` 가드로 막았다. **provider 에 새 의존을 추가할 때 "이제 재빌드될 수 있는가"를 먼저 볼 것** — 기존에 상수만 보던 provider 는 클로저에 `ref` 를 캡처해도 안전했다.

**함정 1건**: `test/config/build_brand_scope_test.dart` 는 `lib/**.dart` 전문에서 `BuildBrand` **문자열**을 찾는다 — 주석에 언급만 해도 실패한다. 새 config 파일에서 "브랜드 축을 참조하지 않는 이유"를 설명하려다 걸렸다. 문서(`docs/`)는 스캔 대상이 아니라 무관.

**남은 것**: 실기기 E2E(목록 업로드→로그인→대시보드 등장, 비대상 매장 재로그인→정지, 재시작 시 캐시 시드, 404 폴백, 원격 로그 명령 왕복), 릴리즈 APK 에서 "설정 카드는 숨겨진 채 원격 명령은 동작" 확인. `fleet_targets/fleet_stores.json` 서버 업로드(수동 scp)는 미실행.

관련: [[project_fleet_monitoring_branch_strategy]], [[project_device_monitoring_design]], [[project_mammoth_dedicated_build]]
