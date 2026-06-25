import 'dart:convert';

/// waldpos_agent 통신용 A01 전문 빌더/파서 + CRC.
///
/// 순수 함수 모음 (Flutter/Riverpod 의존 X) -- 단위 테스트 자유.
///
/// ## A01 프레임 구조 (실측 기준: kiosk_v4 PosProtocol 동일)
/// ```
/// STX(1=0x02) + 'A'(1=0x41) + VER(2 ASCII "01") + LEN(6 HEX ASCII)
/// + BASE64(N) + CRC(4 HEX ASCII) + ETX(1=0x03)
/// ```
///
/// - LEN : BASE64 페이로드 바이트 길이를 대문자 HEX 6자리 ASCII (예: 768 -> "000300").
/// - CRC : VER + LEN + BASE64 의 CRC-16/CCITT-FALSE -> 대문자 HEX 4자리 ASCII.
/// - 전문 총 길이 = BASE64 길이 + 15.
///
/// 주의: 가이드 문서에는 LEN 이 4바이트 BigEndian 바이너리로 적혀 있으나, 실제
/// 에이전트는 LEN 을 ASCII HEX 텍스트로 파싱한다(2026-06-23 E2E 에서 4byte BE 는
/// "LEN 파싱 실패" 로 거부됨). kiosk_v4 PosProtocol 과 동일한 6자리 HEX 를 사용한다.
///
/// ## CRC-16/CCITT-FALSE 사양
/// - poly = 0x1021, init = 0xFFFF, no reflect, no final XOR.
///
/// (waldpos_agent 측 구현과 동일해야 함 -- 변경 시 양쪽 동시 변경 필요)
class WaldposA01 {
  WaldposA01._();

  static const int stx = 0x02;
  static const int etx = 0x03;
  static const int headerByte = 0x41; // 'A'
  static const String version = '01';

  /// 고정 오버헤드 = STX(1)+'A'(1)+VER(2)+LEN(6)+CRC(4)+ETX(1) = 15.
  static const int frameOverhead = 15;

  /// BASE64 시작 오프셋 = STX(1)+'A'(1)+VER(2)+LEN(6) = 10.
  static const int base64Offset = 10;

  /// A01 프레임 빌드. [requestJson]은 `{Command, Data, Tag}` 형태의 JSON 문자열.
  ///
  /// 반환: 송신 바이트 시퀀스(STX 부터 ETX 까지 전체).
  static List<int> buildFrame(String requestJson) {
    final base64Bytes = utf8.encode(base64.encode(utf8.encode(requestJson)));
    final verBytes = utf8.encode(version);

    // LEN : BASE64 길이를 대문자 HEX 6자리 ASCII.
    final lenStr =
        base64Bytes.length.toRadixString(16).toUpperCase().padLeft(6, '0');
    final lenBytes = utf8.encode(lenStr);

    // CRC : VER + LEN + BASE64 대상, 대문자 HEX 4자리.
    final crcValue =
        crc16Ccitt(<int>[...verBytes, ...lenBytes, ...base64Bytes]);
    final crcBytes =
        utf8.encode(crcValue.toRadixString(16).toUpperCase().padLeft(4, '0'));

    return <int>[
      stx,
      headerByte,
      ...verBytes,
      ...lenBytes,
      ...base64Bytes,
      ...crcBytes,
      etx,
    ];
  }

  /// A01 응답 파싱 -> `{ResultCode, ResultMessage}`.
  ///
  /// 응답 2번째 바이트가 'A'(0x41)가 아니면 레거시(STX + BASE64 + ETX)로
  /// 폴백 파싱한다(에이전트 응답 프레이밍 불확실성 방어).
  /// CRC 불일치/형식 오류 시 [WaldposA01Exception] 을 던진다.
  static Map<String, dynamic> parseResponse(List<int> data) {
    if (data.isEmpty) {
      throw const WaldposA01Exception('empty response');
    }
    if (data.first != stx || data.last != etx) {
      throw const WaldposA01Exception('missing STX/ETX');
    }

    // 레거시 폴백: 'A' 마커 없음 -> STX/ETX 제거 후 base64 디코딩.
    if (data.length < 2 || data[1] != headerByte) {
      final inner = data.sublist(1, data.length - 1);
      return _decodeBase64Json(inner);
    }

    // A01 : BASE64 는 offset 10 부터, 끝에서 CRC(4)+ETX(1) 을 제외한 구간.
    if (data.length < frameOverhead) {
      throw const WaldposA01Exception('frame too short');
    }
    final verBytes = data.sublist(2, 4);
    final lenBytes = data.sublist(4, base64Offset);
    final base64End = data.length - 5; // CRC(4) + ETX(1) 제외
    if (base64End < base64Offset) {
      throw const WaldposA01Exception('length mismatch');
    }
    final base64Bytes = data.sublist(base64Offset, base64End);
    final crcBytes = data.sublist(base64End, base64End + 4);

    // CRC 검증 (VER + LEN + BASE64).
    final expectedCrc =
        crc16Ccitt(<int>[...verBytes, ...lenBytes, ...base64Bytes]);
    final expectedCrcStr =
        expectedCrc.toRadixString(16).toUpperCase().padLeft(4, '0');
    final actualCrcStr = utf8.decode(crcBytes).toUpperCase();
    if (expectedCrcStr != actualCrcStr) {
      throw WaldposA01Exception(
          'CRC mismatch: actual=$actualCrcStr expected=$expectedCrcStr');
    }

    return _decodeBase64Json(base64Bytes);
  }

  static Map<String, dynamic> _decodeBase64Json(List<int> base64Bytes) {
    final jsonStr = utf8.decode(base64.decode(utf8.decode(base64Bytes)));
    final decoded = jsonDecode(jsonStr);
    if (decoded is! Map<String, dynamic>) {
      throw const WaldposA01Exception('response JSON is not an object');
    }
    return decoded;
  }

  /// CRC-16/CCITT-FALSE 계산 (poly=0x1021, init=0xFFFF, no reflect, no final XOR).
  ///
  /// 검증 벡터: `"123456789"` ASCII -> `0x29B1`.
  static int crc16Ccitt(List<int> data) {
    var crc = 0xFFFF;
    for (final byte in data) {
      crc ^= (byte << 8);
      for (var i = 0; i < 8; i++) {
        if ((crc & 0x8000) != 0) {
          crc = ((crc << 1) ^ 0x1021) & 0xFFFF;
        } else {
          crc = (crc << 1) & 0xFFFF;
        }
      }
    }
    return crc;
  }
}

/// A01 응답 파싱 실패(형식/CRC 오류).
class WaldposA01Exception implements Exception {
  final String message;
  const WaldposA01Exception(this.message);
  @override
  String toString() => 'WaldposA01Exception: $message';
}
