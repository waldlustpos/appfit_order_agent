# 테스트 작성·실행 가이드

AppFit 주문 에이전트의 단위/통합 테스트를 **어떻게 실행하고, 어떻게 새로 작성하는지** 한곳에서 설명한다.
테스트 철학·리팩토링 규율은 [REFACTORING.md](REFACTORING.md), 코드 스타일은 [FLUTTER_GUIDELINES.md](FLUTTER_GUIDELINES.md) §테스트 참고.

## 테스트 전략 — characterization(현재 동작 고정)

리팩토링 안전망이 목적이다. [REFACTORING.md](REFACTORING.md) 규율에 따라:

- **글루 코드**(OrderProvider·상태 병합·인터셉터 등)는 **리팩토링 전에 현재 동작을 테스트로 먼저 묶는다.** 버그처럼 보여도 일단 그대로 고정하고, 수정은 별도 커밋으로 분리한다(테스트 의도가 "동작 보존 증명"이기 때문).
- **리프 코드**(모델·단일 위젯)는 즉시 수정 가능.
- 리팩토링 절차: ① 현재 동작 characterization 테스트 추가 → ② 그린 확인 → ③ 리팩토링 → ④ 테스트가 여전히 그린이면 동작 보존 증명.

현재 이 앱의 `test/` 는 **16개 파일 / 약 181 케이스**. (별도 패키지 `appfit_core` 는 자체 테스트 약 99 케이스를 따로 보유 — [REFACTORING.md](REFACTORING.md) Phase 1 기준 합산 약 279.)

## 디렉토리 맵

```
test/
├── core/       processed_order_cache_test.dart            # (orderId,status) dedup 불변식
├── models/     order_model_test.dart                      # 값 기반 == / 깊은 비교
│               order_model_fromjson_test.dart             # fromJson 방어 파싱 (타입 어긋남/손상 항목 격리)
│               order_menu_model / order_status / store_model_fromjson
├── providers/  order_ingestion_characterization_test.dart # ★ 주문 3-way 유입(소켓/폴링/자동접수)
│               order_queue_manager_test.dart              # 버퍼 1s→정렬→throttle 방출
│               order_timer_manager_test.dart              # 폴링/캐시정리/자정 새로고침 타이머
│               order_cache_manager_test.dart              # 상세조회 캐시 + 상태 merge
│               order_socket_manager_retry_test.dart       # getOrder 재시도/backoff
│               order_state_test.dart                      # OrderState 불변성/copyWith 가드
├── services/   output_queue_service_test.dart             # 출력 멱등성 + 라벨 우선 실행
│               printer_job_queue_test.dart                # 프린터 busy/success/error 재시도
│               label_filter_strategy_test.dart
└── utils/      brand_registry_test.dart
```

**가장 먼저 볼 파일**: [../test/providers/order_ingestion_characterization_test.dart](../test/providers/order_ingestion_characterization_test.dart) — 실제 `OrderProvider`를 `ProviderContainer` + override로 통째로 인스턴스화해 유입 경로를 검증한다. 이 프로젝트의 통합 테스트 패턴이 모두 여기에 있다.

## 실행 방법

| 목적 | 명령어 |
|---|---|
| 전체 실행 | `flutter test` |
| 단일 파일 | `flutter test test/providers/order_ingestion_characterization_test.dart` |
| 디렉토리 | `flutter test test/providers/` |
| 이름으로 필터 | `flutter test --name "자동접수"` |
| 커버리지 | `flutter test --coverage` → `coverage/lcov.info` 생성 (`.gitignore` 처리됨) |
| 슬래시 커맨드 | `/test` (전체) · `/test test/models/` (경로 지정) — [.claude/commands/test.md](../.claude/commands/test.md)가 `flutter test`를 래핑 |

- **테스트 실행에 `build_runner`는 필요 없다.** 이 프로젝트는 `.mocks.dart`(mockito codegen)를 쓰지 않으며, `build_runner`는 오직 riverpod `.g.dart` 재생성용이다. 테스트만 돌릴 땐 `flutter test` 한 줄이면 된다.
- 새 **프로바이더**를 추가/수정해 `.g.dart`가 바뀌어야 할 때만: `flutter pub run build_runner build --delete-conflicting-outputs` → 그다음 `flutter test`.
- 커버리지 결과(`coverage/`)는 git에 커밋되지 않는다.

## PreferenceService seam 사용 규약 (이번 리팩토링의 핵심)

`PreferenceService`는 factory 싱글톤이지만 내부적으로 `SharedPreferences`를 **라이브로(캐싱 없이)** 읽는다. 이 성질을 이용해 테스트에서 자동접수 ON/OFF 같은 설정 분기를 제어한다. 실제 사용처는 [order_ingestion_characterization_test.dart](../test/providers/order_ingestion_characterization_test.dart) 그룹 `(e)`.

**3단계**:

```dart
// ① setUpAll — mock SharedPreferences 시드 (기본 자동접수 OFF)
//    마이그레이션/프린터·업데이트 기본값/환경 복원 분기는 마커 키로 스킵.
SharedPreferences.setMockInitialValues(<String, Object>{
  V2MigrationService.KEY_MIGRATION_V2_COMPLETED: true,
  PreferenceService.KEY_PRINTER_DEFAULT_SET: true,
  PreferenceService.KEY_UPDATE_DEFAULT_SET: true,
  PreferenceService.KEY_ENVIRONMENT: 'live',
  PreferenceService.KEY_AUTO_RECEIPT: false,
});
await PreferenceService().init();

// ② 분기를 검증할 테스트에서만 라이브 토글 + 원복
await PreferenceService().setAutoReceipt(true);
addTearDown(() => PreferenceService().setAutoReceipt(false));

// ③ 토글 "후"에 Provider를 build — build()가 getAutoReceipt()를 그 시점에 읽는다
final h = await _buildProvider();
h.notifier.queueOrderExternal(_order(orderNo: 'A'));
await _wait(1600);
expect(h.api.statusUpdates, contains(('A', OrderStatus.PREPARING)));
```

**주의 3가지**:

1. **순서** — `setAutoReceipt`는 반드시 `_buildProvider()` *전에*. `build()`가 그 시점 값으로 분기를 결정한다.
2. **원복** — 싱글톤이라 토글이 다음 테스트로 누수된다. 반드시 `addTearDown`으로 되돌린다.
3. **기본값 함정** — `getAutoReceipt()`의 코드상 기본값은 `true`(현재 동작)다. 그래서 setUpAll에서 `KEY_AUTO_RECEIPT: false`를 **명시적으로** 시드해 OFF를 대비군으로 고정한다. 대부분의 유입(소켓/폴링) 테스트는 OFF로 두고 유입 경로만 관찰하고, 자동접수 PUT 체인은 그룹 `(e)`에서만 ON으로 검증한다.

## 테스트 작성 패턴

- **수동 fake + `noSuchMethod`** (mockito/mocktail 대신 권장): 유입 경로가 쓰는 메서드만 손으로 구현한 `_FakeApiService` 등을 만들고, 나머지는 `noSuchMethod`로 throw 되게 둔다. **예기치 않은 호출이 즉시 표면화**되는 게 장점. [order_ingestion_characterization_test.dart](../test/providers/order_ingestion_characterization_test.dart) `_FakeApiService` 참고. (`mocktail`은 dev_dependencies에 있지만 현재 미사용이며, [FLUTTER_GUIDELINES.md](FLUTTER_GUIDELINES.md)는 Mock보다 Fake/Stub을 우선한다.)
- **`ProviderContainer(overrides: [...])`**: Riverpod 의존성을 fake로 주입. `addTearDown(container.dispose)`를 잊지 말 것.
- **`fakeAsync`**: 타이머/배치 윈도우(버퍼 1s, 배치 200ms, 폴링 30s 등) 검증은 가상 시간으로 — [order_queue_manager_test.dart](../test/providers/order_queue_manager_test.dart), [order_timer_manager_test.dart](../test/providers/order_timer_manager_test.dart). `fake_async`는 `flutter_test`의 전이 의존성이라 직접 의존성 추가 불필요. 단, `OrderProvider` 통합 테스트는 플랫폼 채널 mock·비동기 API와 얽혀 있어 실시간 `_wait()`로 처리한다.
- **플랫폼 채널 / SharedPreferences mock**: audioplayers·프린터 등 플랫폼 의존은 `setMockMethodCallHandler`로 무력화, 설정은 `SharedPreferences.setMockInitialValues`로 시드.
- **패턴**: AAA(Arrange-Act-Assert) 또는 Given-When-Then 준수.

## 커밋 전 체크리스트

모든 커밋은 다음을 만족해야 한다([REFACTORING.md](REFACTORING.md) 규율):

- `flutter analyze` — 경고 0(클린)
- `flutter test` — 전부 그린
