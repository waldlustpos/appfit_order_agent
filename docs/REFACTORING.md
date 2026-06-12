# 리팩토링 로드맵

2026-06-12 종합 아키텍처 감사(6개 영역 멀티 에이전트 분석 + 발견사항 적대적 검증) 결과로 확정된 로드맵입니다. 결론: **전면 리팩토링은 불필요** — 부채의 본질은 구조 붕괴가 아니라 테스트 부재(감사 시점 2.8%)이며, 처방은 "안전망(characterization test) 구축 → 그 보호 아래 점진 분해"입니다.

## 영역별 진단 (감사 시점)

| 영역 | 건강도 | 판정 |
|---|---|---|
| services | 6/10 | **양호 — 구조 개편 불필요.** 테스트만 보강 |
| providers | 5/10 | OrderProvider(~2,300L) 단일체가 유일한 대형 부채. 매니저 6개는 분리 완료 상태 |
| ui | 5/10 | 거대 파일 3개(order_detail_popup/common_dialog/app_bar_widget) — 기계적 분해 가능 |
| layering | 4/10 | UI→services 직접 import 다수 — 절반은 provider 정의가 service 파일에 있는 구조 때문 |
| core-package | 5/10 | appfit_core 검증 공백(CryptoUtils·Dio 401 retry·NotifierService 테스트 0). 소비자 2개(주문 에이전트 + DID) |
| quality | 4/10 | 테스트 커버리지가 모든 부채의 곱셈 계수 |

## Phase 0 — 완료 (chore/phase0-quick-wins)

.gitignore `!.env` 정리 / providers.dart 배럴 누수 제거 / **모델 동등성 실버그 수정**(MenuOptionModel ==, OrderMenuModel listEquals) / 빈 setState 제거 / KdsSortDirection keepAlive / mocktail + `/test` 커맨드 / 본 문서 + 가이드라인 보강. appfit_core: analysis_options.yaml + release.sh test 단계.

## Phase 1 — 단기: 테스트 안전망 (배포 사이클 무관, 상시 진행 가능)

1. **appfit_core characterization 테스트**: Dio 인터셉터 401→토큰갱신→재시도 경로, CryptoUtils AES-GCM 라운드트립(고정 벡터), NotifierService 재연결 상태머신 (소비자 2개 앱의 공통 안전망 — 최우선)
2. **앱 3-way 주문 유입 시나리오 테스트**: `ProviderContainer` + provider override 로 fake ApiService 주입 — 소켓 dedup / 폴링 병합 / refreshOrders 부활·다운그레이드 차단 가드 고정
3. **분리된 매니저 단위 테스트**: order_queue/timer/cache_manager (이미 분리돼 있어 즉시 가능)
4. **fromJson 방어**: order_model/store_model 필수 필드 `as String` 무방비 캐스트 → 실서버 응답 픽스처 기반 회귀 테스트와 함께
5. PreferenceService 직접 생성(12곳) → provider 경유 전환
6. ~~appfit_core 미사용 export `@Deprecated` 마킹~~ → **2026-06-12 재검증으로 사실상 완료/무효화**: `SerialAsyncQueue` 는 이미 `@Deprecated`(v1.0.6), `OtaUpdateManager`/`OtaStatus` 는 주문 에이전트·DID 양쪽 사용 중(감사 오판), `ApiHttpException` 은 인터셉터가 던지는 공개 예외 타입이라 유지, `AppFitTimeouts` 는 공개 설정 상수라 유지. **소비자는 3개(주문 에이전트 + DID + kiosk, RELEASE.md 참조)** — v2.0.0 제거 대상은 SerialAsyncQueue 뿐이며 kiosk grep 확인 필수
7. 테스트 작성 가이드/전용 서브에이전트 신설 검토 (이 시점에 재평가)

원칙: **"현재 동작"을 테스트로 고정** — 버그처럼 보여도 일단 고정하고, 수정은 별도 커밋으로.

### Phase 1 진행 현황 (2026-06-12)

**완료**: 코어 66케이스(crypto/ApiHttpException/Dio 401 retry/NotifierService 재연결 + connector seam — 다음 릴리즈 minor), 앱 94케이스(매니저 3종 51 + fromJson 31 + 유입 characterization 12), PreferenceService 27곳 provider 경유 전환. 전체 suite: 코어 99 / 앱 180 그린.

**미커버 (seam 필요)**: 자동접수 ON 체인(PreferenceService 전역 싱글톤 per-test 제어 불가), Sentry 쿨다운(hub 주입 없음), 캐시 merge 분기(_orderDetailCache private). **Phase 2 seam 목록**: PreferenceService 생성자/프로바이더 주입, AudioPlayer 주입(필드 이니셜라이저 생성), clock 주입(큐 1s/배치 200ms 실시간 대기 의존), OrderDetailCache 주입, Sentry hub 주입.

**핵심 발견 (수정 후보 — 테스트 보호 확보됨, 별도 커밋으로)**:
1. **폴링 전용 경로 dead wiring**: OrderTimerManager 가 onRefreshOrders 만 호출 — `_pollNewOrders→_mergeOrdersIntoUnfilteredList` 전체가 도달 불가. 3-way 유입은 실질 **2-way**. Phase 2 항목 1은 "병합 지점 신설"이 아니라 **dead 경로 삭제 vs 복구 결정**으로 재정의
2. ~~[코어] `AppFitConfig.packageVersion`(1.0.10) ↔ pubspec(1.0.11) 동기화 누락~~ → **해결** (fix/token-shopcode-join 브랜치, 릴리즈 전 선반영)
3. ~~[코어] TokenManager in-flight 발급 합류 시 shopCode 불일치 검증 없음~~ → **해결** (fix/token-shopcode-join — shopCode 일치 시에만 합류, 테스트 갱신). **코어 변경 누적분(connector seam + 이 수정)은 v1.0.12 minor 릴리즈 필요**
4. [앱] OrderQueueManager 크로스 스테이지 중복 차단이 NEW 대기 중 상태 전이(DONE 등)를 drop — 상태 유실 가능 (행동 변경 — Phase 2 카나리와 함께)
5. [앱] 소켓 유입은 append 만(orderedAt 재정렬 없음) — UI 순서 역전 가능 (행동 변경 — Phase 2 정렬 정본 작업과 함께)
6. ~~[앱] fromJson 타입 방어 구멍~~ → **해결** (fix/fromjson-defense — 방어 코드 + 테스트 기대 갱신. 잔여: updateTime 동일 패턴 미적용)
7. [앱] settings/login 등 화면별 세부 quirk 은 각 테스트 파일 주석 참조

## Phase 2 — 중기: 구조 리팩토링 (항목당 독립 릴리즈 + 1매장 카나리 1주 권장)

1. ~~**데이터 유입 단일 병합 지점**~~ → **1단계 완료 (2026-06-12)**: dead 폴링 경로(_pollNewOrders/_processPollingNewOrders/_mergeOrdersIntoUnfilteredList, _unfilteredOrders, onPollNewOrders — 275줄) 삭제. 유입은 소켓 + refreshOrders 2-way 로 확정. 잔여: 소켓 append vs refreshOrders 정렬(orderedAt) 이원화 통일 + `_lastKnownOrderSequence`(현재 write-only) 정리. ApiService.getNewOrders 도 앱 내 호출처 소멸 — 코어 v2.0.0 정리 후보
2. **OrderProvider 슬리밍** (Strangler): seam 확보 → characterization 고정 → 같은 파일 내 순수 함수 추출 → 매니저로 이동 → 콜백 양방향 변이 제거. **추출과 이동은 별도 커밋** (diff 리뷰 가능성 유지). 목표 ~800L 코디네이터
3. 3개 캐시(Processed/Detail/RecentRemovals) 갱신을 OrderCacheManager 로 집중, 상태·캐시 롤백 일관화
4. UI 분해: common_dialog(→다이얼로그별 파일) → login_screen 자체 다이얼로그 공용화 → order_detail_popup 상태변경 로직 provider 이동 → app_bar_widget 분할
5. settings_label_test_section 의 스트레스 테스트/mock 생성 로직 → `lib/dev/` 격리
6. appfit_core v2.0.0 (deprecated export 제거 — **소비자 3개 앱(주문 에이전트·DID·kiosk) 동시 grep 확인 + 마이그레이션**)

주의: Phase 2 진행 중에는 주문 도메인(OrderProvider 반경) 기능 작업을 같은 스프린트에 두지 않는다.

## Phase 3 — 장기 (트리거 충족 시에만)

- 플랫폼 분기 추상화: 3번째 플랫폼 추가 또는 `Platform.is*` 분기 파일 20개 초과 시
- main.dart bootstrap 추출: import 50개 초과 시
- UI→services 직접 import 잔여 해소: 해당 파일을 수정하는 작업에 동승 (provider 정의를 service 파일에서 분리하는 작업과 묶어서)
- 핵심 경로(주문 유입·상태전이·출력 큐·core 인증) 커버리지 60%+

## 하지 말 것 (감사에서 오탐/불필요로 판정)

- services 레이어 전면 개편 (DI 혼용/retry 중복/고결합 주장 모두 검증에서 기각)
- providers↔services "순환 의존 해소" (순환은 실재하지 않음)
- 전 화면 ConsumerWidget 일괄 전환 / `ref.listen` in build() "재구독 churn 수정" (Riverpod 표준 패턴)
- freezed 모델 전환 (CLAUDE.md 절대 규칙 위반)
- OrderProvider 빅뱅 재작성 (운영 POS — Strangler 절차만 허용)
- appfit_core `BatchMergeBuffer` export 제거 (DID 앱 사용 중)
- release.sh 우회 릴리즈 (단일 진입점 정책)

## 작업 규율

- 구조 커밋과 기능 커밋을 같은 브랜치에 섞지 않는다 (장수 브랜치 재발 방지 — 항목당 단명 브랜치, 1~2주 내 머지)
- 글루 코드(OrderProvider·병합·인터셉터)는 테스트 먼저, 리프 코드(모델·단일 위젯)는 즉시 수정 가능
- 모든 Phase 2 항목은 `flutter analyze` 클린 + `flutter test` 그린 + 양 플랫폼(Android/Windows) 스모크 후 머지
