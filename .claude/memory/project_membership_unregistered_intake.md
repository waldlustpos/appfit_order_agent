---
name: project_membership_unregistered_intake
description: "멤버십 미가입 번호 접수 — 서버 자동가입 정책(매머드 1차)이 근거. 구현 완료, 적립 실기기 검증 대기"
metadata: 
  node_type: memory
  type: project
  originSessionId: 7e95d623-5668-4b81-826d-37930ac1e573
  modified: 2026-08-31T06:01:15.100Z
---

멤버십 화면에서 **미가입 번호도 적립/쿠폰을 받는** 기능 (2026-08-31 구현, 미커밋·미배포).

**존재 이유는 서버 정책이다** — 매머드 **1차 브랜드**(매머드커피 `0qs2vf410y3wh`)
서버는 미가입 번호의 스탬프 적립을 받아주면서 **회원을 내부적으로 가입시킨다.**
그래서 적립 직후 재조회가 정상 회원으로 응답한다. 앱은 이 정책을 브랜드로
게이팅하지 **않기로 결정**했다(fail-safe + Sentry 관찰). 상세 근거는 코드 주석에
있다: `Membership._enterUnregistered`.

실측으로 확정된 서버 동작 (실기기 로그):
- 미가입 조회는 `404` + `code: NOT_FOUND_USER` + "존재하지 않는 유저입니다."
- **`/v0/stamps/history` 와 `/v0/coupons/history` 도 같은 404 를 준다.** 유저 단위
  판정이라 성공할 수 없는 호출 → 미가입이면 내역 API 를 아예 건너뛴다.
- 아직 미검증: `/v0/stamp/earn` 이 실제로 자동가입까지 하는지(적립 실기기 테스트).

**함정 — Dio 인터셉터는 호출부보다 먼저 로깅한다.** `getUserProfile` 의 catch 절로
404 를 잡아도 core `_AppFitLogInterceptor.onError` 가 이미 Sentry 로 보낸 뒤다.
일상 동작이 된 404 를 Slack 알림에서 빼려면 **로거를 감싸야** 한다 →
`lib/services/appfit/benign_api_log_filter.dart`. 판정은 status+code+**경로**
셋 다 봐야 통과 — `/stamp/earn` 의 `NOT_FOUND_USER` 는 일부러 남겨서, 다른 브랜드
서버가 미가입 적립을 거부하면 알림으로 드러나게 했다.

연관: [[project_pii_logging_policy]] · [[project_sentry_alert_routing]] ·
[[reference_appfit_log_file_whitelist]] · [[project_appfit_core_dual_repo]]
