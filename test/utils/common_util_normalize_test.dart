import 'package:flutter_test/flutter_test.dart';

import 'package:appfit_order_agent/utils/common_util.dart';

/// `CommonUtil.normalizeInlineText` 계약 고정.
///
/// 서버 메뉴명/옵션명에는 **실제 개행(LF)** 과 **이스케이프가 안 풀린 리터럴
/// `\n`(백슬래시+n 2글자)** 이 둘 다 섞여 온다. 종전 코드는 리터럴만 지워
/// 실제 LF 가 통과했고, `maxLines: 1` 위젯/TextPainter 가 이를 하드
/// 라인브레이크로 처리해 **개행 뒤 내용이 통째로 사라졌다**.
void main() {
  group('normalizeInlineText — 리터럴 백슬래시+n', () {
    test('리터럴 \\n 은 공백 1칸이 된다', () {
      expect(CommonUtil.normalizeInlineText(r'바닐라\n라떼'), '바닐라 라떼');
    });

    test('리터럴 \\r\\n 도 공백 1칸 (2칸이 되면 교체 순서가 틀린 것)', () {
      expect(CommonUtil.normalizeInlineText(r'바닐라\r\n라떼'), '바닐라 라떼');
    });

    test('리터럴 \\r 단독도 공백 1칸', () {
      expect(CommonUtil.normalizeInlineText(r'바닐라\r라떼'), '바닐라 라떼');
    });

    test('백슬래시 조각이 남지 않는다', () {
      expect(CommonUtil.normalizeInlineText(r'A\nB'), isNot(contains(r'\')));
    });
  });

  group('normalizeInlineText — 실제 제어문자 개행', () {
    test('LF 는 공백 1칸', () {
      expect(CommonUtil.normalizeInlineText('바닐라\n라떼'), '바닐라 라떼');
    });

    test('CRLF 는 공백 1칸', () {
      expect(CommonUtil.normalizeInlineText('바닐라\r\n라떼'), '바닐라 라떼');
    });

    test('CR 단독도 공백 1칸', () {
      expect(CommonUtil.normalizeInlineText('바닐라\r라떼'), '바닐라 라떼');
    });

    test('연속 개행도 공백 1칸으로 접힌다', () {
      expect(CommonUtil.normalizeInlineText('바닐라\n\n\n라떼'), '바닐라 라떼');
    });
  });

  group('normalizeInlineText — 혼재·공백 정리', () {
    test('리터럴과 실제 개행이 섞여도 전부 접힌다', () {
      expect(CommonUtil.normalizeInlineText('A\\nB\nC'), 'A B C');
    });

    test('개행 앞뒤에 이미 공백이 있어도 1칸으로 축약된다', () {
      expect(CommonUtil.normalizeInlineText('A \n B'), 'A B');
    });

    test('탭도 공백 1칸으로 축약된다', () {
      expect(CommonUtil.normalizeInlineText('A\t\tB'), 'A B');
    });

    test('앞뒤 개행·공백은 trim 된다', () {
      expect(CommonUtil.normalizeInlineText('\n  아메리카노  \n'), '아메리카노');
    });
  });

  group('normalizeInlineText — 무해성 (건드리면 안 되는 입력)', () {
    test('null 은 빈 문자열', () {
      expect(CommonUtil.normalizeInlineText(null), '');
    });

    test('빈 문자열은 빈 문자열', () {
      expect(CommonUtil.normalizeInlineText(''), '');
    });

    test('개행 없는 문자열은 원문 그대로', () {
      const name = '아이스 바닐라 라떼 (레귤러)';
      expect(CommonUtil.normalizeInlineText(name), name);
    });

    test('전각공백(U+3000)은 보존한다 — 일본어 메뉴명의 시각 간격', () {
      // 반각 공백으로 축약해버리면 일본어 상품명 간격이 무너진다.
      const name = 'バニラ　ラテ';
      expect(CommonUtil.normalizeInlineText(name), name);
    });

    test('개행만으로 이루어진 값은 빈 문자열 — 호출부 isNotEmpty 필터가 걸러낸다', () {
      expect(CommonUtil.normalizeInlineText('\n\n'), '');
      expect(CommonUtil.normalizeInlineText(r'\n'), '');
    });
  });
}
