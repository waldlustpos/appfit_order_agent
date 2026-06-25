import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:appfit_order_agent/services/waldpos/waldpos_a01.dart';

void main() {
  group('WaldposA01.crc16Ccitt', () {
    test('표준 검증 벡터 "123456789" -> 0x29B1', () {
      final crc = WaldposA01.crc16Ccitt(utf8.encode('123456789'));
      expect(crc, 0x29B1);
    });

    test('빈 입력 -> 0xFFFF(init)', () {
      expect(WaldposA01.crc16Ccitt(const <int>[]), 0xFFFF);
    });
  });

  group('WaldposA01.buildFrame', () {
    test('프레임 구조: STX/A/VER, LEN=6 HEX ASCII, 총 길이 = base64 + 15', () {
      const json = '{"Command":"Payment","Data":"{}","Tag":null}';
      final frame = WaldposA01.buildFrame(json);

      // STX, 'A', VER("01").
      expect(frame.first, 0x02);
      expect(frame[1], 0x41);
      expect(frame[2], '0'.codeUnitAt(0));
      expect(frame[3], '1'.codeUnitAt(0));
      // ETX.
      expect(frame.last, 0x03);

      // LEN(6 HEX ASCII) == base64 payload 길이.
      final lenStr = utf8.decode(frame.sublist(4, 10));
      final len = int.parse(lenStr, radix: 16);
      final expectedBase64Len =
          utf8.encode(base64.encode(utf8.encode(json))).length;
      expect(len, expectedBase64Len);

      // 총 길이 = base64 + 15(고정 오버헤드).
      expect(frame.length, len + WaldposA01.frameOverhead);
    });
  });

  group('WaldposA01 round-trip', () {
    test('build -> parse 로 원 JSON 객체 복원 + CRC 자기검증', () {
      final original = <String, dynamic>{
        'ResultCode': '0000',
        'ResultMessage':
            '{"returnValue":"1","cardNo":"8801753104098","paymentInfo":"B"}',
      };
      final frame = WaldposA01.buildFrame(jsonEncode(original));
      final parsed = WaldposA01.parseResponse(frame);

      expect(parsed['ResultCode'], '0000');
      expect(parsed['ResultMessage'], original['ResultMessage']);
    });

    test('CRC 변조 시 예외', () {
      final frame = WaldposA01.buildFrame('{"a":1}');
      // CRC 4바이트는 ETX 직전(끝에서 2~5번째). 한 바이트를 변조.
      final tampered = List<int>.from(frame);
      tampered[tampered.length - 2] =
          tampered[tampered.length - 2] == 0x41 ? 0x42 : 0x41;
      expect(
        () => WaldposA01.parseResponse(tampered),
        throwsA(isA<WaldposA01Exception>()),
      );
    });
  });

  group('WaldposA01 레거시 폴백', () {
    test('STX + Base64 + ETX (A 마커 없음) 파싱', () {
      final payload = jsonEncode(<String, dynamic>{
        'ResultCode': '0000',
        'ResultMessage': '{"returnValue":"1","cardNo":"01011112222"}',
      });
      final base64Bytes = utf8.encode(base64.encode(utf8.encode(payload)));
      final legacy = <int>[0x02, ...base64Bytes, 0x03];

      final parsed = WaldposA01.parseResponse(legacy);
      expect(parsed['ResultCode'], '0000');
    });
  });
}
