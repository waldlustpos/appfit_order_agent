---
name: project_fleet_store_allowlist_gate
description: "Fleet 관제 이식 + 매장 화이트리스트 게이트. 정식 도입 전까지 FleetConfig.enabled=false 로 비활성(서버통신 0)"
metadata: 
  node_type: memory
  type: project
  originSessionId: 7202b256-696c-439b-b197-b9aeb235ae84
  modified: 2026-08-21T00:24:26.208Z
---

2026-08-19. `feat/fleet-monitoring` 의 Fleet 관제를 `feat/mammoth-dedicated-build` 에 이식하고, **OTA 정적 호스트의 매장 코드 화이트리스트로 게이팅**하는 기능을 추가했다. analyze 에러 0(issue 17 = 변경 전과 동일), test 544건 전량 통과. `feat/mammoth-dedicated-build` 에 커밋 완료(미푸시).

**⛔ 최종 상태: 비활성.** 사용자가 "정식 도입 전까지 끄자, 대상 매장 정책도 나중에 다시 수립" 으로 결정해 `FleetConfig.enabled = false`(컴파일 타임 const)로 서버 통신을 통째로 막았고, 서버의 `fleet_stores.json` 도 삭제(404 확인). **실기기 검증은 끝내 못 했다.** 되돌릴 때는 그 상수 하나만 true.

**앱→관제 서버 요청은 정확히 2개뿐**이라는 게 끄기·켜기의 핵심 지식이다: ① 로그인마다 1회 목록 조회(`reconcileFleetTarget` 안의 `service.refresh()`) ② 60초 register/heartbeat. ②는 `fleetSyncProvider → fleetReporterProvider → fleetSinkProvider` 체인으로만 생기므로 첫 단계에서 끊으면 `HttpFleetSink` 인스턴스 자체가 안 생긴다. 스위치를 `AppEnv`(gitignore)나 dart-define 이 아니라 커밋되는 `FleetConfig` 에 둔 이유는, 레포에서 "지금 켜져 있나"가 안 보이면 안 되기 때문.

**이식 방법이 핵심**: `git merge` 가 아니라 **파일 단위 `git checkout`**. fleet 브랜치엔 이미 main 에 반영된 displayOrder 정렬 커밋 4개가 섞여 있고, `pubspec.yaml` 의 appfit_core ref 가 v1.1.0(현재 브랜치는 v1.2.0)이라 머지하면 다운그레이드된다. merge-base(`7cbdc00`) 이후 현재 브랜치 변경 이력이 0인 파일 12개는 통째 체크아웃, 양쪽 다 바뀐 4개(`main.dart`·`platform_service.dart`·`lifecycle_provider.dart`·`app_bar_widget.dart`)만 손으로 병합했다. v1.2.0 의 `FleetReporter` 생성자는 브랜치 사용 시그니처와 호환.

**게이트 구조** — 이중이다. `AppEnv.hasFleetConfig`(빌드타임 `.env`) AND `fleetTargetedProvider`(런타임 매장) → `fleetEnabledProvider` → sink/status/sync 셋이 함께 참조. 게이트가 뒤집히면 Riverpod 재빌드가 sink→reporter→sync 로 연쇄하고 구 reporter 는 기존 `onDispose(reporter.stop)` 이 정리한다 — 새 teardown 코드 불필요.

**설계 결정 4가지(사용자 확정)**: 목록은 전 빌드 공용 단일 파일(`http://waldpay.kokonutstamp2.com/fleet_stores.json`) / 조회 실패 시 마지막 캐시로 판정, 캐시도 없으면 OFF / 매장 코드 완전일치만(프리픽스 와일드카드 없음) / 로그인 시 1회 조회.

**요청 범위를 넘어 추가한 것**: 앱 시작 시 `fleetTargetedProvider` 를 캐시된 목록 ∩ `prefs.getId()` 로 시드. 로그인 훅만 두면 **로그인에 실패한 기기**(= 가장 관제로 보고 싶은 상태)가 대시보드에서 사라진다.

**직접 만든 새 실패경로 하나**: 게이트가 생기며 `fleetSinkProvider` 가 재빌드될 수 있게 됐는데, 구 sink 의 in-flight 응답이 dispose 된 `ref` 로 `onStatus` 를 부르면 예외가 난다. `var disposed` + `ref.onDispose` 가드로 막았다. **provider 에 새 의존을 추가할 때 "이제 재빌드될 수 있는가"를 먼저 볼 것** — 기존에 상수만 보던 provider 는 클로저에 `ref` 를 캡처해도 안전했다.

**함정 1건**: `test/config/build_brand_scope_test.dart` 는 `lib/**.dart` 전문에서 `BuildBrand` **문자열**을 찾는다 — 주석에 언급만 해도 실패한다. 새 config 파일에서 "브랜드 축을 참조하지 않는 이유"를 설명하려다 걸렸다. 문서(`docs/`)는 스캔 대상이 아니라 무관.

**남은 것**: 실기기 E2E(목록 업로드→로그인→대시보드 등장, 비대상 매장 재로그인→정지, 재시작 시 캐시 시드, 404 폴백, 원격 로그 명령 왕복), 릴리즈 APK 에서 "설정 카드는 숨겨진 채 원격 명령은 동작" 확인. `fleet_targets/fleet_stores.json` 서버 업로드(수동 scp)는 미실행.

**2026-08-21 갱신 — 게이트 구조가 셋에서 넷으로.** `fleetEnabledProvider`(`lib/providers/fleet_provider.dart`)에 `Platform.isWindows` AND 조건을 추가했다. 우선 Windows 매장 POS 에만 배포하고 Android(Sunmi)는 아직 관제하지 않기로 한 결정 — 다음 업데이트에서 이 조건은 다시 바뀔 여지가 있다(Android 포함 등). `Platform` 은 provider 파일에서 `dart:io` 직접 import(코드베이스 기존 패턴, `waldpos_scan_provider.dart` 와 동일 스타일) — 별도 헬퍼 계층 없음. `docs/DEVICE_MONITORING.md` §상단 요약도 "네 게이트"로 함께 갱신.

**같은 날 후속 — Windows 가드가 두 곳으로 분리됐다.** 사용자가 "reconcileFleetTarget 이 OS 판별을 선행하게" 요청해, 로그인마다 나가는 매장 화이트리스트 조회(`reconcileFleetTarget` 의 `service.refresh()`) 앞에도 `if (!Platform.isWindows) return;` 를 추가했다. 이유: `fleetEnabledProvider` 하나에만 있으면 Android 도 최종 판정에서만 막힐 뿐 로그인마다 조회 요청(네트워크 호출)은 여전히 나간다 — 도달하지 않을 활성화를 위한 낭비. **Android 를 다시 켤 땐 두 곳(`fleetEnabledProvider`, `reconcileFleetTarget`)의 `Platform.isWindows` 가드를 함께 지워야 한다** — 하나만 지우면 최종 판정은 Android 를 허용하는데 조회가 계속 비어서 항상 비대상으로 막히는 불일치가 생긴다. `fleet_targets/fleet_stores.json` 에 매장 4개(MMTH01066/01050/01069/01081)도 같은 세션에 추가했지만 서버 scp 업로드는 보류(사용자 확인 대기) — enabled=false 라 지금은 어차피 무영향.

관련: [[project_fleet_monitoring_branch_strategy]], [[project_device_monitoring_design]], [[project_mammoth_dedicated_build]]
