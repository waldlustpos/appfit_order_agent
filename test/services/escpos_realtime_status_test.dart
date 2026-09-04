import 'package:flutter_test/flutter_test.dart';

import 'package:appfit_order_agent/services/label_printer/windows/escpos_realtime_status.dart';

/// 순수 함수라 하드웨어 없이 검증된다.
///
/// 실기 실측(G30, 2026-09-03, 정상 상태): n=1 → 0x16, n=2/3/4 → 0x12.
void main() {
  group('dleEot', () {
    test('DLE EOT n 바이트열', () {
      expect(dleEot(kDleEotPrinter), [0x10, 0x04, 1]);
      expect(dleEot(kDleEotOffline), [0x10, 0x04, 2]);
      expect(dleEot(kDleEotError), [0x10, 0x04, 3]);
      expect(dleEot(kDleEotPaper), [0x10, 0x04, 4]);
    });
  });

  group('고정 비트 검증', () {
    test('실기 실측값은 유효하다', () {
      expect(isValidStatusByte(0x12), isTrue); // n=2/3/4 정상
      expect(isValidStatusByte(0x16), isTrue); // n=1 정상
    });

    test('고정 비트가 어긋나면 무효', () {
      expect(isValidStatusByte(0x13), isFalse, reason: 'bit0 은 항상 0');
      expect(isValidStatusByte(0x10), isFalse, reason: 'bit1 은 항상 1');
      expect(isValidStatusByte(0x02), isFalse, reason: 'bit4 는 항상 1');
      expect(isValidStatusByte(0x92), isFalse, reason: 'bit7 은 항상 0');
    });

    test('흔한 쓰레기 바이트를 상태로 받아들이지 않는다', () {
      // 이게 이 검사의 존재 이유다 — 오독하면 없는 용지없음으로 무한 대기한다.
      expect(isValidStatusByte(0x00), isFalse);
      expect(isValidStatusByte(0xFF), isFalse);
      expect(isValidStatusByte(0x0A), isFalse); // '\n'
      expect(isValidStatusByte(0x20), isFalse); // ' '
    });
  });

  group('decodeOfflineStatus (DLE EOT 2)', () {
    test('정상 — 아무 비트도 서지 않는다', () {
      final s = decodeOfflineStatus(0x12)!;
      expect(s.coverOpen, isFalse);
      expect(s.paperFeedByButton, isFalse);
      expect(s.printingStopped, isFalse);
      expect(s.errorOccurred, isFalse);
    });

    test('커버 열림 = bit2', () {
      expect(decodeOfflineStatus(0x16)!.coverOpen, isTrue);
    });

    test('용지끝 정지 = bit5 / 에러 = bit6', () {
      expect(decodeOfflineStatus(0x32)!.printingStopped, isTrue);
      expect(decodeOfflineStatus(0x52)!.errorOccurred, isTrue);
    });

    test('무효 바이트는 null', () {
      expect(decodeOfflineStatus(0xFF), isNull);
      expect(decodeOfflineStatus(0x00), isNull);
    });
  });

  group('decodePaperStatus (DLE EOT 4)', () {
    test('용지 있음', () {
      final s = decodePaperStatus(0x12)!;
      expect(s.paperEnd, isFalse);
      expect(s.nearEnd, isFalse);
    });

    test('용지 없음 = bit5+bit6 동시', () {
      expect(decodePaperStatus(0x72)!.paperEnd, isTrue);
    });

    test('용지 거의 없음 = bit2+bit3 동시', () {
      expect(decodePaperStatus(0x1E)!.nearEnd, isTrue);
    });

    test('한쪽 비트만 서면 용지없음으로 보지 않는다', () {
      // 규격상 2비트가 짝으로 움직인다. 한쪽만 보고 판정하면
      // 커버열림(bit2)을 용지 거의 없음으로 오독한다.
      expect(decodePaperStatus(0x16)!.nearEnd, isFalse,
          reason: 'bit2 만 선 것은 커버열림이지 near-end 가 아니다');
      expect(decodePaperStatus(0x32)!.paperEnd, isFalse,
          reason: 'bit5 만 선 것은 paper-end 가 아니다');
    });

    test('무효 바이트는 null', () {
      expect(decodePaperStatus(0xFF), isNull);
    });
  });

  group('describeEntryBlock', () {
    test('Android describeEntry 와 같은 어휘', () {
      expect(describeEntryBlock(coverOpen: true, paperEnd: true), '용지없음+커버열림');
      expect(describeEntryBlock(coverOpen: false, paperEnd: true), '용지없음');
      expect(describeEntryBlock(coverOpen: true, paperEnd: false), '커버열림');
    });
  });
}
