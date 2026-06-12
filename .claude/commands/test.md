---
description: 앱 단위 테스트 실행 (flutter test)
---

아래 명령어를 Bash 툴로 실행한다:

1. `flutter test`
2. 인자가 주어지면 해당 경로만: `flutter test $ARGUMENTS` (예: `/test test/models/`)

결과 요약:
- 실패가 있다면 파일별로 실패 테스트 이름과 기대/실제 값을 목록 출력
- 컴파일 에러로 로드 실패한 테스트 파일은 별도로 구분해 보고
- 모두 통과하면 "테스트 N개 통과" 한 줄로 끝낸다

참고:
- 테스트는 mock 없이 실제 모델/순수 함수 직접 검증이 기본 패턴 (test/models/ 참조)
- mock 이 필요한 경우 mocktail 사용 (dev_dependencies 에 포함됨)
