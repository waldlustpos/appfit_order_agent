import 'package:flutter_test/flutter_test.dart';
import 'package:appfit_order_agent/config/membership_config.dart';

/// 1회 적립 개수 상한(=10) 과 키패드 입력 차단 규칙 고정.
///
/// 상한은 세 곳(입력란 힌트 문구·초과 에러 문구·키패드 차단)이 같은 상수를
/// 보게 되어 있는데, 문구는 i18n JSON 이라 컴파일러가 지켜주지 못한다. 그래서
/// 상수 값 자체를 여기서 날숫자로 못 박는다 — 값을 바꿀 때 이 테스트가 깨지면
/// 3개 로캘 문구도 같이 확인하라는 신호다.
///
/// 판정이 **자릿수가 아니라 값** 기준이라는 점이 핵심이다. 과거에는
/// `length >= 2` 로 막아 문구는 "최대 20개"인데 99까지 입력됐다.
void main() {
  group('maxStampPerAccrual — 정책 값 고정', () {
    test('1회 적립 상한은 10개다', () {
      // 날숫자로 쓴다. 상수를 그대로 참조하면 값이 바뀌어도 통과해 무의미하다.
      expect(MembershipConfig.maxStampPerAccrual, 10);
    });
  });

  group('allowsStampDigit — 키패드/하드웨어 키 입력 차단', () {
    test('상한 이하는 받는다', () {
      expect(MembershipConfig.allowsStampDigit('', '1'), isTrue); // 1
      expect(MembershipConfig.allowsStampDigit('', '9'), isTrue); // 9
      expect(MembershipConfig.allowsStampDigit('1', '0'), isTrue); // 10 = 상한
    });

    test('상한 초과는 입력 단계에서 막는다', () {
      expect(MembershipConfig.allowsStampDigit('1', '1'), isFalse); // 11
      // 자릿수 제한이던 시절에는 통과했다 — 값 판정으로 바뀐 것을 못 박는다.
      expect(MembershipConfig.allowsStampDigit('9', '0'), isFalse); // 90
      expect(MembershipConfig.allowsStampDigit('2', '0'), isFalse); // 20
    });

    test('세 자리 이상은 값 판정만으로 자연히 막힌다', () {
      expect(MembershipConfig.allowsStampDigit('10', '0'), isFalse); // 100
      expect(MembershipConfig.allowsStampDigit('10', '1'), isFalse); // 101
    });

    test('숫자로 파싱되지 않는 입력은 거부한다', () {
      // 스탬프 모드에서는 도달하지 않는 경로지만, 파싱 실패를 통과시키면
      // 상한이 조용히 무력화되므로 닫아 둔다.
      expect(MembershipConfig.allowsStampDigit('abc', '1'), isFalse);
      expect(MembershipConfig.allowsStampDigit('', ''), isFalse);
    });
  });
}
