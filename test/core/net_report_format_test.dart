import 'package:appfit_order_agent/core/net/net_report_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatClock', () {
    test('한 자리 시/분에 0 을 채운다', () {
      expect(formatClock(DateTime(2026, 8, 11, 9, 5)), '09:05');
    });

    test('자정은 00:00', () {
      expect(formatClock(DateTime(2026, 8, 11)), '00:00');
    });
  });

  group('formatStamp', () {
    // 날짜가 빠지면 지연 도착한 이벤트를 "오늘 장애" 로 오독한다 —
    // 2026-08-11 PAIK00002 에서 실제로 그랬다. 이 테스트가 그 방지선이다.
    test('월-일을 반드시 포함한다', () {
      expect(formatStamp(DateTime(2026, 8, 11, 21, 7)), '08-11 21:07');
    });

    test('한 자리 월/일에 0 을 채운다', () {
      expect(formatStamp(DateTime(2026, 1, 2, 3, 4)), '01-02 03:04');
    });
  });

  group('formatRange', () {
    test('같은 날이면 끝 시각의 날짜를 생략한다', () {
      expect(
        formatRange(
          DateTime(2026, 8, 11, 21, 9),
          DateTime(2026, 8, 11, 21, 19),
        ),
        '08-11 21:09~21:19',
      );
    });

    test('자정을 넘기면 끝에도 날짜를 붙인다', () {
      expect(
        formatRange(
          DateTime(2026, 8, 11, 23, 55),
          DateTime(2026, 8, 12, 0, 7),
        ),
        '08-11 23:55~08-12 00:07',
      );
    });

    test('같은 월-일이라도 해가 다르면 날짜를 붙인다', () {
      expect(
        formatRange(
          DateTime(2025, 8, 11, 21, 0),
          DateTime(2026, 8, 11, 21, 0),
        ),
        '08-11 21:00~08-11 21:00',
        reason: '읽는 사람은 헷갈리겠지만, 같은 날로 뭉개서 1년을 0분으로 보이게 하는 것보다 낫다',
      );
    });
  });

  group('formatDuration', () {
    test('1분 미만은 초만', () {
      expect(formatDuration(const Duration(seconds: 41)), '41초');
      expect(formatDuration(Duration.zero), '0초');
    });

    test('59초 → 60초 경계', () {
      expect(formatDuration(const Duration(seconds: 59)), '59초');
      expect(formatDuration(const Duration(seconds: 60)), '1분 0초');
    });

    test('실제 장애 길이 (2026-08-11 PAIK00002)', () {
      expect(formatDuration(const Duration(seconds: 581)), '9분 41초');
    });

    test('1시간부터는 초를 버린다', () {
      expect(
          formatDuration(const Duration(minutes: 59, seconds: 59)), '59분 59초');
      expect(formatDuration(const Duration(hours: 1, minutes: 3, seconds: 30)),
          '1시간 3분');
    });

    test('음수는 0초로 흡수한다 (시계 역행)', () {
      expect(formatDuration(const Duration(seconds: -3)), '0초');
    });
  });
}
