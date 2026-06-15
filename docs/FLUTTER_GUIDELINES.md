# Flutter 개발 가이드라인


## 코드 스타일 및 네이밍

- **네이밍**: 클래스는 `PascalCase`, 변수/함수/enum 값은 `camelCase`, 파일은 `snake_case`
- **줄 길이**: 80자 이하 권장
- **간결성**: 선언적이고 함수형 패턴을 선호하며, 코드는 명확하면서도 최대한 짧게 작성
- **SOLID 원칙**: 단일 책임, 개방-폐쇄, 리스코프 치환, 인터페이스 분리, 의존성 역전 원칙 적용
- **합성 우선**: 상속보다 합성(composition)을 선호하여 복잡한 위젯과 로직 구성
- **약어 지양**: 축약어를 피하고, 의미 있고 일관성 있는 이름 사용
- **화살표 함수**: 단순한 한 줄 함수에는 화살표(`=>`) 구문 사용

### import 규칙

- **프로젝트 내부 import 는 `package:` 형태만**: `lib/` 안의 다른 파일을 참조할 때는 상대 경로(`import '../utils/foo.dart'`)가 아니라 항상 `import 'package:appfit_order_agent/utils/foo.dart'` 형태를 사용한다.
- **근거**: 프로젝트 내부 import 를 `package:` 로 통일하면 파일 이동 시 import 가 깨지지 않고(이동에 불변), stale import 를 컴파일 에러로 잡을 수 있다. `analysis_options.yaml` 의 `always_use_package_imports: true` 린트로 강제된다 — 상대 import 는 분석 단계에서 걸린다.
- **`directives_ordering` 은 비활성(정렬 강제 아님)**: import 알파벳 정렬은 의도적으로 켜지 않았다. flutter_lints 기본 세트에 없고, 자동 fix 가 없어 수백 줄 수동 정렬이 필요하며, deferred import 등 주석이 붙은 지시문을 정렬하면 주석-지시문 연결이 끊기기 때문. import 순서는 자유.

## Dart 모범 사례

### Null Safety
- Dart의 null safety를 적극 활용하며 sound null-safe 코드 작성
- `!` 연산자는 값이 non-null임이 보장될 때만 사용, 남용 금지
- `int.tryParse()`, `double.tryParse()` 등 안전한 타입 변환 사용

### 비동기 처리
- 비동기 작업에는 `Future`와 `async`/`await`를 사용하고, 반드시 오류 처리 포함
- 비동기 이벤트 시퀀스에는 `Stream` 사용
- UI 스레드 차단을 피하기 위해 무거운 계산은 `compute()`로 별도 Isolate에서 실행
- **동기 FFI 호출은 Isolate.run 으로 boxing (Windows 전용)**: Windows 에서 Dart FFI 로 직접 호출하는 native API — `autoreplyprint.dll` (라벨 프린터 SDK), `serial_port_win32` (외부 영수증 COM), `win32` 등 — 의 동기 호출은 USB 스택 / OS 자원 race 환경에서 main isolate event loop 를 수백ms~수초 block 한다. `Isolate.run<T>(() {...})` 안에서 SDK 호출을 실행하고 결과 (primitive / record / handle 의 raw `address`) 만 cross-isolate 로 받는 패턴 사용. `unawaited` 만으로는 main thread block 해소되지 않음 (함수 본체의 동기 부분이 event loop 점유). 라벨 backend 의 `_enumerateUsbPortsAsync` / `_tryOpenUsbAsync` 가 reference.

  Android 는 MethodChannel 이 native 측 별도 thread (`receiptPrintExecutor` 등) 에서 처리하므로 Dart main isolate block 위험이 없어 같은 패턴 불필요. Dart FFI 경로가 새로 추가될 때만 의식적으로 적용.
- **UI 트리거가 backoff 큐의 결과를 await 하지 말 것 (fire-and-forget)**: `PrinterJobQueue` 처럼 백오프 + final-failure 콜백을 자체적으로 관리하는 큐는 호출자(다이얼로그/버튼) 가 future 를 await 하면 backoff 끝까지 (최대 137s) UI 가 묶인다. `unawaited(queue.add(...))` 또는 동등 패턴 사용. 결과 표시가 필요하면 `Future.timeout` 으로 짧은 시간만 기다리고 시간 초과 시 백그라운드 진행 안내(설정 화면 "외부 프린터 테스트 출력" 8s timeout reference).

### 패턴 매칭 및 Switch
- 코드를 간결하게 만드는 곳에서 패턴 매칭 활용
- 가능한 경우 exhaustive `switch` 표현식 사용 (`break` 불필요)
- 여러 값을 반환해야 할 때 Record 타입 사용 고려

### 예외 처리
- `try-catch` 블록으로 예외를 처리하고, 상황에 적합한 예외 타입 사용
- 프로젝트 고유 상황에는 커스텀 예외 사용 (`lib/exceptions/api_exceptions.dart` 참조)
- 코드가 조용히 실패하지 않도록 에러를 적절히 처리

## Flutter 모범 사례

### 위젯 구성
- 위젯(특히 `StatelessWidget`)은 불변으로 유지
- 큰 `build()` 메서드는 작은 private Widget 클래스로 분리 (헬퍼 메서드가 아닌 별도 Widget 클래스 사용)
- 가능한 모든 곳에서 `const` 생성자 사용하여 불필요한 리빌드 감소
- `build()` 메서드 내에서 네트워크 호출, 복잡한 계산 등 비용이 큰 작업 수행 금지

### 리스트 성능
- 긴 리스트에는 `ListView.builder` 또는 `SliverList`로 지연 로딩 구현
- KDS 카드 그리드 등 대량 데이터 표시 시 특히 중요

## 프로젝트별 패턴

### Riverpod 사용 규칙
- 새 프로바이더는 `@Riverpod` 어노테이션 + `riverpod_generator` 사용
- 앱 생명주기 동안 유지해야 하는 상태에는 `@Riverpod(keepAlive: true)` 적용
- **keepAlive 판단 기준**: 화면 전환·구독 해제 후에도 값이 유지되어야 하면 `keepAlive: true`(도메인 상태·설정·모드 토글 등 대부분), 화면을 벗어나면 초기화되는 것이 맞는 일시 상태만 autoDispose(기본값). 같은 도메인의 프로바이더 그룹(예: `kds_unified_providers.dart`) 안에서는 keepAlive 여부를 통일
- 간단한 상태에는 `StateProvider` 사용 가능 (예: `homeTabIndexProvider`)
- 수동 `StateNotifierProvider`는 예외적으로만 허용 — 유일한 예외는 `BlinkStateNotifier`(생성자에서 `Timer.periodic` + `ref.listen` 초기화가 `@riverpod build()` 구조와 맞지 않음). 새 프로바이더에 수동 패턴을 쓰려면 같은 수준의 구조적 사유가 필요
- 비동기 데이터 로딩에는 `AsyncValue` 타입으로 로딩/에러 상태를 명확히 처리
- UI에서의 구분: 상태 구독은 `ref.watch()`, 일회성 읽기는 `ref.read()` 사용
- 프로바이더 생성 후 반드시 `dart run build_runner build --delete-conflicting-outputs` 실행

### 수동 JSON 직렬화
- 모델 클래스는 `lib/models/`에 수동 작성 (freezed/json_serializable 코드 생성 미사용)
- 각 모델에 `factory fromJson(Map<String, dynamic> json)` 팩토리 생성자 구현
- `toJson()` 메서드와 `copyWith()` 메서드 수동 구현
- JSON 파싱 실패에 대비한 `try-catch`, `tryParse()` 등 안전한 파싱 적용
- 타입 어긋남 방어: 숫자/날짜는 `json['key']?.toString()` 후 `tryParse` (직캐스트 `as String`/`as num` 금지)
- 목록 파싱은 항목별 try-catch 로 격리 — 1건 손상 시 해당 항목만 `logger.e` 로그 후 스킵, 정상 항목 유지
- 필수 필드(예: StoreModel.strId/name)는 silent 기본값 대신 누락 키를 명시한 `FormatException` throw
- Enum은 `fromCode()` 팩토리로 서버 코드와 매핑 (예: `OrderStatus.fromCode('2003')`)

### 모델 동등성 구현 (==/hashCode)
- 모델에 `operator ==`를 정의하면 `hashCode`도 반드시 함께 정의 — `a == b`이면 `a.hashCode == b.hashCode` 계약 유지
- List 필드는 `listEquals()`로 깊은 비교, hashCode 에는 `Object.hashAll(list)` 사용 — `list.length`만 비교/해시하면 내용이 다른 객체가 equal 판정됨 (OrderMenuModel.options 실버그 사례)
- 중첩 모델(예: `MenuOptionModel`)도 값 기반 `==`/`hashCode`를 정의해야 상위 모델의 `listEquals`가 의미를 가짐
- 비교 키에서 의도적으로 제외하는 필드(mutable 필드, 내부 캐시, 파생값)는 `OrderModel.==` 상단처럼 주석으로 명시
- `==` 변경 시 사용처 영향 사전 확인: Set/Map 키 사용, `contains`/`indexOf`/`remove`, `listEquals` 호출 지점을 grep — 동등성 테스트(`test/models/`)에 케이스 추가 필수

### Navigator 라우팅
- `MaterialApp`의 `routes` 맵에 고정 라우트 정의 (`/login`, `/home`, `/settings`)
- 화면 전환: `Navigator.pushReplacementNamed()`, `Navigator.pushNamedAndRemoveUntil()` 사용
- `PopScope`로 뒤로가기 버튼 동작 제어
- go_router는 사용하지 않음

### 로깅
- 전역 `logger` 인스턴스 사용 (`lib/utils/logger.dart`)
- 레벨별 사용: `logger.d()` (디버그), `logger.i()` (정보), `logger.w()` (경고), `logger.e()` (에러)
- 모듈별 태그 활용: `logToFile(tag: LogTag.API, message: '...')`
- 파일 로깅은 Whitelist 태그 기반 필터링 적용 (UI_ACTION, SYSTEM, PLATFORM, WEBSOCKET, LIFECYCLE 등)
- `print()` 대신 항상 `logger` 사용
- **모듈별 메시지 prefix 컨벤션** (운영 로그 grep 분리용):

  | prefix | 사용처 |
  |---|---|
  | `[ReceiptQueue]` | `OutputQueueService._processReceiptItem` |
  | `[LabelQueue]` | `OutputQueueService._processLabelItem` |
  | `[OutputQueue]` | `OutputQueueService.clear()` 등 큐 자체 라이프사이클 |
  | `[PrinterQueue]` | `PrinterJobQueue` (영수증 송출 글로벌 직렬 큐) |
  | `[ComPortPrint]` | `ComPortPrintService` (Windows COM 저수준) |
  | `[WindowsTransport]` | `WindowsTransport.send` |
  | `[LabelPrinter]` | `WindowsLabelPrinterBackend` (Windows FFI) |
  | `[Label]` | `OutputService.printOrderLabels` (운영 식별자 + ★ 누락 마커) |
  | `[ExternalReceiptPrinter]` | `ExternalReceiptPrinter` (플랫폼-무관 진입점) |

  같은 prefix 를 두 곳에서 재사용하지 말 것 — grep 분리가 어려워짐. `[Label]` 은 라벨 운영 식별자로 예약, `OutputQueueService` 안에서는 `[ReceiptQueue]` / `[LabelQueue]` 사용.

### 테마 및 스타일
- `lib/constants/app_styles.dart`의 `AppStyles` 클래스에 색상, 폰트 크기, 버튼 스타일 등 중앙화
- 새 스타일 추가 시 `AppStyles`에 정적 상수/팩토리 메서드로 추가
- Material 3 활성화 (`useMaterial3: true`)
- 커스텀 폰트: `SpoqaHanSansNeo` (기본), `Pretendard` 사용
- 하드코딩된 색상/크기 값은 `AppStyles` 상수로 추출하여 일관성 유지

## 레이아웃 모범 사례

### Row/Column 구성
- **`Expanded`**: 남은 공간을 채워야 할 때 사용
- **`Flexible`**: 축소는 가능하되 확장은 불필요할 때 사용 (같은 Row/Column에서 `Expanded`와 혼용 금지)
- **`Wrap`**: Row/Column에서 오버플로가 발생할 때 다음 줄로 넘기기 위해 사용

### 스크롤 및 리스트
- **`SingleChildScrollView`**: 고정 크기의 콘텐츠가 뷰포트보다 클 때 사용
- **`ListView.builder`**: 긴 리스트에 지연 로딩 적용
- **`LayoutBuilder`**: 반응형 레이아웃을 위해 가용 공간 기반 의사결정 시 사용

### 오버플로 방지
- **`FittedBox`**: 자식 위젯을 부모 크기에 맞게 스케일링
- 텍스트 오버플로 시 `TextOverflow.ellipsis`, `maxLines` 활용

## 테스트 가이드라인

- **단위 테스트**: `package:test`로 도메인 로직, 서비스 레이어 테스트
- **위젯 테스트**: `package:flutter_test`로 UI 컴포넌트 테스트
- **통합 테스트**: `package:integration_test`로 전체 사용자 흐름 검증
- **패턴**: AAA(Arrange-Act-Assert) 또는 Given-When-Then 패턴 준수
- **Mock 선호도**: Mock보다 Fake/Stub 우선 사용, 필요 시 `mocktail` 활용
- **테스트 실행**: `flutter test` 또는 `flutter test test/<파일_경로>`
- **상세**: 실행 옵션·characterization 전략·PreferenceService seam·fake/`fakeAsync` 패턴은 [TESTING.md](TESTING.md) 참고

## 접근성 (A11Y)

- **색상 대비**: 텍스트와 배경 간 최소 **4.5:1** 대비율 유지 (WCAG 2.1 기준)
- **동적 텍스트 크기**: 시스템 글꼴 크기 변경 시 UI가 정상 작동하는지 확인
- **시맨틱 레이블**: `Semantics` 위젯으로 UI 요소에 명확한 설명 제공
- **스크린 리더**: TalkBack (Android) 테스트 권장

## 문서화 규칙

- 모든 공개 API에 `///` dartdoc 주석 작성
- 첫 문장은 마침표로 끝나는 간결한 요약
- 복잡하거나 명확하지 않은 코드에만 주석 작성 — 코드 자체로 설명되는 경우 주석 불필요
- 뒤따르는(trailing) 주석 금지
- 코드가 **무엇을** 하는지가 아니라 **왜** 그렇게 하는지 설명
