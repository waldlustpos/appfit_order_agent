---
name: project_coupon_input_phone_misentry
description: "멤버십 입력란 하나를 회원조회·쿠폰사용이 공유 → 전화번호를 쿠폰으로 보내 400, 서버 메시지가 Sentry 제목→Slack 으로 전화번호 유출. 앱 차단 + core v1.4.0 마스킹/benign."
metadata: 
  node_type: memory
  type: project
  originSessionId: 96e6a53a-9e0a-4a24-bd64-abfb355bec14
  modified: 2026-08-27T07:53:49.368Z
---

**증상:** Sentry 이슈 `HTTP 400 POST /v0/coupon/{id}/use-without-item · INVALID_REQUEST · Invalid couponNo: 01092337380` 이 Slack 으로. 제목에 고객 전화번호가 그대로.

**구조적 원인 (우연 아님):** `membership_screen.dart` 는 입력란 하나(`_inputController`)를 [회원조회](전화번호·회원바코드)와 [쿠폰사용](쿠폰코드)이 공유한다. 전화번호를 넣은 채 [쿠폰사용]을 누르는 오조작은 계속 재발한다.

**3층 대응 (2026-08-27, 전부 완료):**
1. **앱 — 호출 전 차단**: `CommonUtil.isLikelyPhoneNumber`(`^0\d{8,10}$`) 로 `_useCouponDirectly` 초입에서 끊고 안내 다이얼로그. 400 자체가 안 나면 Sentry·PII·Slack 노이즈가 전부 없다. 판정을 **일부러 좁게** 잡았다 — 실제 쿠폰번호는 16자리에 `0` 으로 시작하지 않아(`5001868426241491`) 겹치지 않는다. **오탐으로 정상 쿠폰을 막는 쪽이 더 나쁜 회귀**라 국가별 번호 체계로 넓히지 말 것. 테스트 `test/utils/common_util_phone_like_test.dart` 가 양방향 고정.
2. **core — 마스킹**: `ApiHttpException.redactDigitRuns` 로 서버 message 의 6자리+ 숫자열 마스킹. [[project_pii_logging_policy]] 참고.
3. **core — benign 분류**: `SentryAppFitLogger.benignServerCodesByPath` 신설. `INVALID_REQUEST` 는 범용 코드라 전역 `benignServerCodes` 에 넣으면 **우리가 잘못된 본문을 보낸 진짜 결함까지 묻힌다** → 템플릿 경로 키로 `'/v0/coupon/{id}/use-without-item': {'INVALID_REQUEST'}` 만 허용. 판정은 `isBenign()` 단일 진입점.

**배포:** appfit_core v1.4.0 태그·푸시 완료(`tool/release.sh`), 앱 `pubspec.yaml` ref 를 v1.4.0 으로 범프 완료. 앱 릴리즈 빌드는 아직 안 함.

관련: [[project_pii_logging_policy]] · [[feedback_appfit_core_release]] · [[project_appfit_core_dual_repo]]
