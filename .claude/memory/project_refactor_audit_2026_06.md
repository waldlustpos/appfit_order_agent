---
name: project-refactor-audit-2026-06
description: "2026-06-12 종합 아키텍처 감사 결론 — 전면 리팩토링 불필요, 테스트 안전망→점진 분해 로드맵 확정 (보고서만 전달, 실행은 별도 세션)"
metadata: 
  node_type: memory
  type: project
  originSessionId: a2390304-cb0c-482c-b6c3-77d25789c870
---

2026-06-12 appfit_order_agent + appfit_core 종합 감사 완료 (45 에이전트, 53건 중 20건 적대적 검증 기각 → 18건 확정). 전체 보고서·로드맵: `/Users/kimsungchun/.claude/plans/appfit-order-agent-appifit-agent-core-lexical-naur.md`

**결론**: 전면 리팩토링 불필요. 부채 본질은 테스트 2.8%(11파일/1,206L) — "안전망 구축 → Strangler 점진 분해" 전략. services 레이어는 6/10 양호 판정이라 건드리지 말 것.

**핵심 확정 사항**:
- OrderProvider 2,282L 단일체 (manager 6개는 이미 분리됨), 3-way 주문 유입(소켓/폴링/수동) 병합 지점 부재 — 정렬 정답(orderedAt)은 order_provider.dart L1000-1002 주석에 이미 있음
- **실버그**: OrderMenuModel.operator==가 options.length만 비교 (L106-118), OrderModel.hashCode에 menus/discountTypes 누락
- appfit_core: CryptoUtils(AES-GCM)·Dio 401 retry·NotifierService 테스트 0, analysis_options.yaml 부재, release.sh에 test 단계 없음
- 앱에 mocktail/mockito 미설치 — 테스트 작성 선행조건

**중요 함정 (재발 방지)**:
- appfit_core 소비자는 2개: 주문 에이전트 + DID 앱. **BatchMergeBuffer는 DID가 3곳 사용 — export 제거 금지**. export 정리 시 양 앱 grep 필수
- .env는 커밋 안 됨(오탐 주의 — git check-ignore로 ignored 확인). 단 .gitignore 87-89행 `!.env` 모순 규칙은 정리 가치 있음
- ref.listen in build()는 Riverpod 표준 패턴 — "재구독 churn" 지적은 오탐

**Phase 0 실행 완료 (2026-06-12)**: 앱 `chore/phase0-quick-wins` 8커밋 + 패키지 `chore/lint-and-release-test` 2커밋 — 사용자가 푸시 완료. 로드맵 정본은 앱 저장소 `docs/REFACTORING.md`.

**Phase 1 실행 완료 (2026-06-12)**: 앱 `test/phase1-safety-net` 6커밋(매니저 51 + fromJson 31 + 유입 12 테스트, PreferenceService 27곳 provider 경유, 문서) + 패키지 `test/phase1-core-safety-net` 3커밋(crypto 18 + http 35 + socket 13 테스트, NotifierService connector seam — **다음 릴리즈 minor bump**). suite: 코어 99/앱 180 그린. **푸시 미실행**.

**Phase 1 핵심 발견**: ① 폴링 전용 경로 dead wiring(타이머가 onRefreshOrders만 호출 — 3-way 유입은 실질 2-way, `_unfilteredOrders` 포함 ~150줄이 살아있는 소비자 없음 확인) ② packageVersion 동기화 누락 ③ TokenManager shopCode 미검증.

**Phase 1 후속 수정 완료 (2026-06-12)**: 앱 `fix/fromjson-defense`(fromJson 방어, StoreModel 필수 필드 FormatException 설계) + 코어 `fix/token-shopcode-join`(shopCode 일치 시에만 in-flight 합류). 잔여: updateTime 동일 패턴 미적용.

**dead 폴링 경로 삭제 + v1.0.12 릴리즈 완료 (2026-06-12, 사용자 승인)**: 앱 `refactor/remove-dead-polling-path` — OrderProvider 2,283→2,008줄(275줄 삭제), 유입은 소켓+refreshOrders 2-way 확정, `_lastKnownOrderSequence`는 write-only 잔존(후속 정리 후보), ApiService.getNewOrders 호출처 소멸. 코어 **v1.0.12 태그 470c41d** release.sh 경유 배포(새 test 게이트 첫 실전 통과), CHANGELOG에 v1.0.11 소급 항목 보완. 앱 ref v1.0.12 갱신 완료(테스트 179 그린). **DID·kiosk 앱의 ref 갱신은 미수행** — 토큰 shopCode 버그 수정이 포함되므로 권장. 앱 브랜치 3개(fix/fromjson-defense, refactor/remove-dead-polling-path 포함 체인) 푸시 미실행. 다음: Phase 2 잔여(소켓 유입 정렬 통일, 큐 상태 전이 drop — 카나리 필요), UI 분해.

**추가 함정**: `git tag | tail`은 사전순 정렬이라 v1.0.10/v1.0.11이 v1.0.5보다 앞에 와서 누락된 것처럼 보임 — 태그 확인은 `sort -V` 필수 (v1.0.11은 리모트에 정상 존재). appifit_agent_core 저장소는 `.claude/`를 gitignore(로컬 전용 정책), 앱 저장소의 `docs/`는 `docs/*` 화이트리스트 방식.

**2026-06-15 — 베이스라인 리셋 + Phase 2 결정 + 병행 안전작업 배치(6 단명 브랜치)**: 사용자 결정 = 57커밋 `refactor/remove-dead-polling-path`를 1주 카나리 후 main FF 머지, 동시에 seam+리프 리팩토링 병행. 모든 단명 브랜치는 main이 아니라 **`refactor/remove-dead-polling-path`(곧 main)에서 분기**(테스트 인프라가 거기만 있음). 배치 6브랜치(각 base+1~2): `chore/dev-isolation-label-test`(라벨 fixture→lib/dev, 위젯 714→596) · `refactor/seam-orderdetailcache`(OrderDetailCache 주입 provider + 캐시 merge 테스트) · `refactor/split-common-dialog`(common_dialog 838→383, ConfirmDialog/UpdateProgressDialog/dialogTitle 분리 + 데드 showExitDialog 제거) · `fix/small-debts`(updateTime fromJson 방어 + _lastKnownOrderSequence 표기 정정) · `refactor/seam-audioplayer`(AudioPlayer 팩토리 주입 + 채널 mock→mocktail fake) · `refactor/seam-preferenceservice`(자동접수 ON characterization). **미푸시 잔여 2개: chore/dev-isolation-label-test, refactor/seam-preferenceservice**.

**Phase 2 핵심 발견/정정**:
- base에 codegen 드리프트 누락분 있었음(31981c5/0c36c4e가 provider 소스 바꾸고 .g.dart 재생성 누락) → base에 `chore(codegen)` + `coverage/` gitignore 2커밋 추가, 피처 브랜치 리베이스. **앞으로 build_runner는 base에서 한 번 돌려 .g.dart 동기 확인 권장**.
- **PreferenceService seam은 이미 존재**(31981c5가 직접 생성 제거 완료) — 평가의 "직접 호출 2곳" 블로커는 stale. getter가 SharedPreferences 라이브 read(캐싱 없음)라 `setAutoReceipt(true)` 토글로 자동접수 테스트 가능(production 변경 불필요).
- `_lastKnownOrderSequence`는 write-only 아님(소켓 콜백·_updateLastKnownOrderSequence가 읽고 갱신, 단 소비처인 폴링 getNewOrders endDate 삭제로 무용) — 제거 후보.
- seam 진행: OrderDetailCache·AudioPlayer ✅, PreferenceService 이미존재 ✅, **Clock(테스트 속도용, 레버리지 최저)·Sentry hub(구현 부재) 잔여**. 병행 배치는 여기서 일단락.
- 미수행 외부: DID 앱 ref v1.0.8→v1.0.12(토큰 보안 수정 포함, 권장), kiosk 앱도 동일.

관련: [[project-ui-refresh]] [[feedback-appfit-core-release]]
