---
description: flutter analyze + dart format 검사 실행
---

아래 두 명령어를 순서대로 Bash 툴로 실행한다:

1. `flutter analyze`
2. `dart format --set-exit-if-changed lib/`

결과 요약:
- 오류/경고가 있다면 파일명:라인 형식으로 목록 출력
- 포맷이 맞지 않는 파일이 있다면 목록 출력 후 `dart format lib/` 실행 여부를 사용자에게 확인
- 모두 통과하면 "분석 통과" 한 줄로 끝낸다
