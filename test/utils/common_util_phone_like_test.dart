import 'package:flutter_test/flutter_test.dart';

import 'package:appfit_order_agent/utils/common_util.dart';

/// `CommonUtil.isLikelyPhoneNumber` 계약 고정.
///
/// 멤버십 화면은 입력란 하나를 [회원조회](전화번호·회원바코드)와
/// [쿠폰사용](쿠폰코드)이 공유한다. 전화번호를 넣은 채 [쿠폰사용]을 누르면
/// 서버가 400 INVALID_REQUEST 와 함께 입력값을 그대로 되돌려주고
/// (`Invalid couponNo: 01092337380`), 그 문구가 Sentry 이슈 제목 → Slack
/// 알림까지 흘러가 **고객 전화번호가 노출됐다.** 이 판정으로 API 호출 전에 끊는다.
///
/// 이 테스트가 지키는 것은 두 방향이다:
///  - 전화번호를 놓치면 → PII 가 다시 Sentry/Slack 으로 샌다.
///  - 쿠폰번호를 전화번호로 오판하면 → 정상 쿠폰 사용이 막힌다(더 나쁜 회귀).
void main() {
  group('isLikelyPhoneNumber — 차단해야 하는 입력', () {
    test('사고 당시 실제 입력값 (휴대폰 11자리)', () {
      expect(CommonUtil.isLikelyPhoneNumber('01092337380'), isTrue);
    });

    test('일본 휴대폰 11자리', () {
      expect(CommonUtil.isLikelyPhoneNumber('09012345678'), isTrue);
    });

    test('유선 10자리 (서울 02 / 도쿄 03)', () {
      expect(CommonUtil.isLikelyPhoneNumber('0212345678'), isTrue);
      expect(CommonUtil.isLikelyPhoneNumber('0312345678'), isTrue);
    });

    test('유선 9자리 하한', () {
      expect(CommonUtil.isLikelyPhoneNumber('021234567'), isTrue);
    });

    test('앞뒤 공백은 무시하고 판정한다', () {
      expect(CommonUtil.isLikelyPhoneNumber('  01092337380 '), isTrue);
    });
  });

  group('isLikelyPhoneNumber — 통과시켜야 하는 입력', () {
    test('실제 쿠폰번호 16자리는 전화번호가 아니다', () {
      expect(CommonUtil.isLikelyPhoneNumber('5001868426241491'), isFalse);
    });

    test('0 으로 시작해도 12자리 이상이면 쿠폰번호로 본다', () {
      expect(CommonUtil.isLikelyPhoneNumber('001868426241491'), isFalse);
    });

    test('0 으로 시작하지 않으면 자릿수가 같아도 통과', () {
      expect(CommonUtil.isLikelyPhoneNumber('11092337380'), isFalse);
    });

    test('8자리 이하는 판정 대상 밖', () {
      expect(CommonUtil.isLikelyPhoneNumber('01234567'), isFalse);
    });

    test('숫자가 아닌 문자가 섞이면 쿠폰코드로 본다', () {
      expect(CommonUtil.isLikelyPhoneNumber('010-9233-7380'), isFalse);
      expect(CommonUtil.isLikelyPhoneNumber('CPN0109233738'), isFalse);
    });

    test('빈 문자열은 별도 안내 경로라 여기서는 false', () {
      expect(CommonUtil.isLikelyPhoneNumber(''), isFalse);
    });
  });
}
