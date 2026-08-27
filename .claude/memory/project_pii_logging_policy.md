---
name: project_pii_logging_policy
description: "로그·Sentry 개인정보 정책 확정 — 전화번호는 마스킹, 회원바코드·쿠폰번호는 원문(가명 추적키), 실명 가능 닉네임은 아예 미기록. 서버 message 는 6자리+ 숫자열 마스킹."
metadata: 
  node_type: memory
  type: project
  originSessionId: 96e6a53a-9e0a-4a24-bd64-abfb355bec14
  modified: 2026-08-27T07:53:23.864Z
---

2026-08-27 전면 점검으로 확정한 정책. 기준은 **"로그 파일은 기기 밖으로 나간다"** — zip → Slack 채널 업로드(설정화면 로그 수집), 로컬 로그서버(HTTP 8080, 무인증), Windows 6개월 보관.

**3분류:**
- **전화번호** → `CommonUtil.maskTail` 로 뒤 4자리만. 그 자체로 사람을 지목하는 값.
- **회원바코드·쿠폰번호** → **원문 유지**. 회원 DB 를 거쳐야 사람으로 환원되는 가명 식별자라 로그끼리 맞대조하는 추적 키로 쓴다. (2026-06-23 커밋이 바코드를 `maskTail` 하고 있었는데 이번에 원문으로 통일.)
- **실명일 수 있는 닉네임(`userName`)·자유입력(`note`)** → **마스킹이 아니라 미기록.** 마스킹해도 매장 단위 소규모 모집단에서는 식별력이 거의 안 떨어진다.

**적용 지점(당시):** `getOrder` 원본 응답 전체 로그 삭제 + logger.dart 의 `[getOrder]` 화이트리스트 예외 제거 / 주문 상세 팝업 로그를 `회원바코드:` 한 줄로 교체(`OrderModel.userBarcode` 를 `data.user.barcode` 에서 신설 파싱, 상세 전용 필드라 `withDetailsFrom` 필수) / `MembershipInfo.toString()` 에서 userName 제거.

**서버 message 함정 (핵심):** 서버가 입력값을 그대로 되돌려주는 메시지(`Invalid couponNo: 01092337380`)가 있다. `ApiHttpException.toString()` 이 Sentry 이슈 **제목**이라, 이게 Slack 알림까지 나갔다. 경로는 `templatePath` 가 `{id}` 로 가리는데 **message 쪽으로 되살아난 것.** → core v1.4.0 에서 `ApiHttpException.redactDigitRuns`(6자리+ 숫자열을 같은 길이 `*` 로) 를 만들고 `fromDio` **생성 시점**에 마스킹. 앱도 같은 함수를 쓴다(`api_error_mapper` breadcrumb, `api_service._handleError` 의 `logger.w`) — 규칙이 두 벌로 갈라지면 한쪽만 새는 구멍이 생긴다. 길이를 보존하는 이유는 자릿수가 진단 단서(11=전화번호, 16=쿠폰번호)라서.

**유출 없음으로 확인한 곳:** core 소켓 수신 로그(`_formatSocketMessage` 는 필드 선별 — 닉네임/전화 없음), 영수증·라벨 파이프라인(출력물엔 쓰지만 로그엔 없음), 카드번호(`maskCardNo` 가 파싱 시점 적용이라 원본 PAN 이 메모리에도 없음), Android 네이티브 Log, print/debugPrint.

관련: [[reference_appfit_log_file_whitelist]] · [[project_coupon_input_phone_misentry]] · [[project_appfit_core_dual_repo]]
