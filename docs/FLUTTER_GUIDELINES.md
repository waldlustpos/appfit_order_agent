# Flutter 개발 가이드라인


## 코드 스타일 및 네이밍

- **네이밍**: 클래스는 `PascalCase`, 변수/함수/enum 값은 `camelCase`, 파일은 `snake_case`
- **줄 길이**: 80자 이하 권장
- **간결성**: 선언적이고 함수형 패턴을 선호하며, 코드는 명확하면서도 최대한 짧게 작성
- **SOLID 원칙**: 단일 책임, 개방-폐쇄, 리스코프 치환, 인터페이스 분리, 의존성 역전 원칙 적용
- **합성 우선**: 상속보다 합성(composition)을 선호하여 복잡한 위젯과 로직 구성
- **약어 지양**: 축약어를 피하고, 의미 있고 일관성 있는 이름 사용
- **화살표 함수**: 단순한 한 줄 함수에는 화살표(`=>`) 구문 사용

## Dart 모범 사례

### Null Safety
- Dart의 null safety를 적극 활용하며 sound null-safe 코드 작성
- `!` 연산자는 값이 non-null임이 보장될 때만 사용, 남용 금지
- `int.tryParse()`, `double.tryParse()` 등 안전한 타입 변환 사용

### 비동기 처리
- 비동기 작업에는 `Future`와 `async`/`await`를 사용하고, 반드시 오류 처리 포함
- 비동기 이벤트 시퀀스에는 `Stream` 사용
- UI 스레드 차단을 피하기 위해 무거운 계산은 `compute()`로 별도 Isolate에서 실행

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
- 간단한 상태에는 `StateProvider` 사용 가능 (예: `homeTabIndexProvider`)
- 비동기 데이터 로딩에는 `AsyncValue` 타입으로 로딩/에러 상태를 명확히 처리
- UI에서의 구분: 상태 구독은 `ref.watch()`, 일회성 읽기는 `ref.read()` 사용
- 프로바이더 생성 후 반드시 `dart run build_runner build --delete-conflicting-outputs` 실행

### 수동 JSON 직렬화
- 모델 클래스는 `lib/models/`에 수동 작성 (freezed/json_serializable 코드 생성 미사용)
- 각 모델에 `factory fromJson(Map<String, dynamic> json)` 팩토리 생성자 구현
- `toJson()` 메서드와 `copyWith()` 메서드 수동 구현
- JSON 파싱 실패에 대비한 `try-catch`, `tryParse()` 등 안전한 파싱 적용
- Enum은 `fromCode()` 팩토리로 서버 코드와 매핑 (예: `OrderStatus.fromCode('2003')`)

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
