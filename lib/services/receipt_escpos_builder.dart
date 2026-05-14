import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'escpos_builder.dart';
import 'platform_service.dart';

/// 영수증 / 주문서 / 테스트 페이지의 ESC/POS 문서를 만드는 플랫폼-무관 빌더.
///
/// 양 플랫폼(Windows COM/Winspool, Android USB) 모두 [toBytesCp949] 결과를 사용.
/// Native(Java/Windows) 측에서 추가 인코딩 없이 byte stream 그대로 전송.
sealed class _Seg {
  const _Seg();
}

class _RawSeg extends _Seg {
  final List<int> bytes;
  const _RawSeg(this.bytes);
}

class _TextSeg extends _Seg {
  final String text;
  const _TextSeg(this.text);
}

class ReceiptEscPosBuilder {
  final List<_Seg> _segs = [];

  void raw(List<int> bytes) => _segs.add(_RawSeg(bytes));
  void text(String s) => _segs.add(_TextSeg(s));
  void textLn(String s) {
    text(s);
    raw(EscPos.lf);
  }

  void ln() => raw(EscPos.lf);
  void init() => raw(EscPos.init);
  void cut() => raw(EscPos.cutPaper);
  void setSize(int mode) => raw(EscPos.setSize(mode));
  void setAlign(int align) => raw(EscPos.setAlign(align));
  void boldOn() => raw(EscPos.boldOn);
  void boldOff() => raw(EscPos.boldOff);

  /// PNG 이미지를 ESC/POS 래스터 비트맵 명령으로 변환해 raw 세그먼트로 추가.
  /// Windows / Android 모두 동일한 비트맵 바이트가 출력된다.
  Future<void> addImageRaster(Uint8List imageBytes) async {
    try {
      final codec = await ui.instantiateImageCodec(imageBytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;

      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) {
        image.dispose();
        return;
      }

      final rgba = byteData.buffer.asUint8List();
      final width = image.width;
      final height = image.height;
      final byteWidth = (width + 7) ~/ 8;

      final bitData = Uint8List(byteWidth * height);
      int byteIndex = 0;
      int bitInByte = 0;

      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final pixelIndex = ((y * width) + x) * 4;
          final r = rgba[pixelIndex];
          final g = rgba[pixelIndex + 1];
          final b = rgba[pixelIndex + 2];

          final gray = ((0.299 * r + 0.587 * g + 0.114 * b).toInt());
          final bit = (gray < 128) ? 1 : 0;

          if (bit == 1) {
            bitData[byteIndex] |= (0x80 >> bitInByte);
          }

          bitInByte++;
          if (bitInByte == 8) {
            bitInByte = 0;
            byteIndex++;
          }
        }
        if (bitInByte != 0) {
          byteIndex++;
          bitInByte = 0;
        }
      }

      final xL = byteWidth & 0xFF;
      final xH = (byteWidth >> 8) & 0xFF;
      final yL = height & 0xFF;
      final yH = (height >> 8) & 0xFF;

      raw([0x1D, 0x76, 0x30, 0x00, xL, xH, yL, yH]);
      raw(bitData);

      image.dispose();
    } catch (_) {
      // 비트맵 로딩 실패 시 무시하고 계속 출력.
    }
  }

  /// 누적된 세그먼트를 EUC-KR(CP949) 바이트 스트림으로 직렬화.
  /// Windows / Android 모두 이 결과를 그대로 USB/COM 으로 송출 → 양 플랫폼 hex 일치.
  ///
  /// 플랫폼별 인코딩 전략:
  /// - Windows: 동기 win32 `WideCharToMultiByte` (codepage 949).
  /// - Android: native MethodChannel `encodeCp949Batch` (Java `getBytes("EUC-KR")`)
  ///   로 텍스트 segments 일괄 위탁. Dart 측 win32 의존을 안드로이드에서 트리거하지
  ///   않기 위한 우회.
  Future<Uint8List> toBytesCp949() async {
    // 텍스트 segments 만 모아서 한 번에 인코딩 (배치). 그 후 순서대로 합침.
    final texts = <String>[];
    for (final s in _segs) {
      if (s is _TextSeg) texts.add(s.text);
    }

    List<Uint8List> encoded;
    if (texts.isEmpty) {
      encoded = const [];
    } else if (Platform.isAndroid) {
      try {
        final res = await platform.invokeMethod<List<dynamic>>(
          'encodeCp949Batch',
          {'texts': texts},
        );
        encoded = res!
            .map((e) => e is Uint8List ? e : Uint8List.fromList(e as List<int>))
            .toList(growable: false);
      } catch (_) {
        // Native 호출 실패 시 ASCII fallback (한글 깨짐) — 출력은 되게 한다.
        encoded = texts
            .map((t) => Uint8List.fromList(
                t.codeUnits.map((c) => c < 0x80 ? c : 0x3F).toList()))
            .toList(growable: false);
      }
    } else {
      // Windows: 동기 win32 호출. EscPos.encodeCp949 reference 는 이 분기 안에서만.
      encoded = texts.map(EscPos.encodeCp949).toList(growable: false);
    }

    final bb = BytesBuilder();
    int ti = 0;
    for (final s in _segs) {
      switch (s) {
        case _RawSeg(:final bytes):
          bb.add(bytes);
        case _TextSeg():
          bb.add(encoded[ti++]);
      }
    }
    return bb.toBytes();
  }

  // ---- 패딩 / 라인 폭 헬퍼 (EUC-KR 바이트 휴리스틱 — 한글 2, ASCII 1) ----

  /// EUC-KR 바이트 길이 휴리스틱.
  /// - 한글 음절(U+AC00..U+D7A3): 2 byte
  /// - 그 외 BMP non-ASCII(한자/특수 등): 2 byte (보수적)
  /// - ASCII: 1 byte
  /// Windows 의 [EscPos.cp949ByteLength] 결과와 한글/ASCII 범위에서 동일.
  static int eucKrLen(String s) {
    int n = 0;
    for (final c in s.codeUnits) {
      if (c < 0x80) {
        n += 1;
      } else {
        n += 2;
      }
    }
    return n;
  }

  /// 바이트 길이 기준 우측 공백 padding.
  static String padRight(String text, int totalWidth) {
    final need = totalWidth - eucKrLen(text);
    if (need <= 0) return text;
    return text + ' ' * need;
  }

  /// 바이트 길이 기준 좌측 공백 padding.
  static String padLeft(String text, int totalWidth) {
    final need = totalWidth - eucKrLen(text);
    if (need <= 0) return text;
    return ' ' * need + text;
  }

  static String separatorLine(int width) => '-' * width;

  // ---- 문서 빌더: 영수증 / 주문서 / 테스트 페이지 ----

  /// 영수증(RECEIPT) — 금액/세금/총액 포함.
  static Future<Uint8List> buildReceiptBytes({
    required Map<String, dynamic> jsonOrder,
    required bool isCancel,
    int width = 48,
    Uint8List? logoImageBytes,
  }) async {
    final b = ReceiptEscPosBuilder();
    await _appendReceipt(b, jsonOrder, isCancel, width, logoImageBytes);
    return await b.toBytesCp949();
  }

  /// 주문서(ORDER) — 금액 없이 메뉴/수량만.
  static Future<Uint8List> buildOrderBytes({
    required Map<String, dynamic> jsonOrder,
    required bool isCancel,
    int width = 48,
    Uint8List? logoImageBytes,
  }) async {
    final b = ReceiptEscPosBuilder();
    await _appendOrder(b, jsonOrder, isCancel, width, logoImageBytes);
    return await b.toBytesCp949();
  }

  /// 설정 UI "테스트 출력" 페이지.
  static Future<Uint8List> buildTestPageBytes({
    String? comPort,
    int? baudRate,
    int width = 48,
  }) async {
    final b = ReceiptEscPosBuilder();
    _appendTestPage(b, comPort, baudRate, width);
    return await b.toBytesCp949();
  }

  // ---- 내부 헬퍼 ----

  static Future<void> _appendReceipt(
    ReceiptEscPosBuilder b,
    Map<String, dynamic> jsonOrder,
    bool isCancel,
    int width,
    Uint8List? logoImageBytes,
  ) async {
    // 영수증의 메뉴 / 수량 / 금액 컬럼 폭. 합이 width 와 같아야 한다.
    const countW = 10;
    const amountW = 10;
    final menuW = width - countW - amountW;

    b
      ..init()
      ..setAlign(EscPos.alignCenter);

    if (isCancel) {
      b
        ..textLn('[취소영수증]')
        ..ln();
    }

    b
      ..boldOn()
      ..setSize(EscPos.fontTall);
    final displayNum =
        (jsonOrder['displayOrderNum'] as String?)?.isNotEmpty == true
            ? jsonOrder['displayOrderNum'] as String
            : (jsonOrder['ordrSimpleId'] as String? ?? '');
    b
      ..textLn('주문번호 : $displayNum')
      ..setSize(EscPos.fontNormal)
      ..boldOff()
      ..ln()
      ..setAlign(EscPos.alignLeft)
      ..textLn(jsonOrder['storeName'] as String? ?? '');

    final storePhone = jsonOrder['storePhone'] as String?;
    if (storePhone != null && storePhone.isNotEmpty) {
      b.textLn('TEL      : $storePhone');
    }
    // 사업자번호는 /v0/shop 응답 추가 후 storeBusinessNumber 키로 주입 예정.

    b
      ..textLn('[일시]   : ${jsonOrder['ordrDtm'] as String? ?? ''}')
      ..textLn(separatorLine(width))
      ..text(padRight('메뉴', menuW))
      ..text(padLeft('수량', countW))
      ..text(padLeft('금액', amountW))
      ..ln()
      ..textLn(separatorLine(width));

    final menuList = jsonOrder['ordrPrdList'];
    if (menuList is List) {
      for (final m in menuList) {
        if (m is! Map) continue;
        final menuName = m['prdNm'] as String? ?? '';
        final menuCount = (m['ordrCnt'] as num?)?.toInt() ?? 0;
        final menuPrice = (m['prdPrc'] as num?)?.toDouble() ?? 0.0;
        final total = (menuPrice * menuCount).toInt();
        final countStr = isCancel ? '-$menuCount' : '$menuCount';
        final amountStr = isCancel ? '-${_priceFmt(total)}' : _priceFmt(total);

        b
          ..text(padRight(menuName, menuW))
          ..text(padLeft(countStr, countW))
          ..text(padLeft(amountStr, amountW))
          ..ln();

        final options = m['optPrdList'];
        if (options is List && options.isNotEmpty) {
          for (final o in options) {
            if (o is! Map) continue;
            final optName = o['optPrdNm'] as String? ?? '';
            final optCount = (o['optPrdCnt'] as num?)?.toInt() ?? 0;
            final optPrice = (o['optPrdPrc'] as num?)?.toDouble() ?? 0.0;
            final optTotal = (optPrice * optCount).toInt();
            final optCountStr = isCancel ? '-$optCount' : '$optCount';
            final optAmountStr =
                isCancel ? '-${_priceFmt(optTotal)}' : _priceFmt(optTotal);

            b
              ..text(padRight(' -$optName', menuW))
              ..text(padLeft(optCountStr, countW))
              ..text(padLeft(optAmountStr, amountW))
              ..ln();
          }
          b.textLn(separatorLine(width));
        }
      }
    }

    b
      ..setAlign(EscPos.alignRight)
      ..textLn('과세금액: ${jsonOrder['exceptTaxPrice'] ?? '0'}')
      ..textLn('부 가 세: ${jsonOrder['taxPrice'] ?? '0'}')
      ..setAlign(EscPos.alignLeft)
      ..textLn(separatorLine(width));

    // OrderModel.toSunmiJson 이 fmt.format(...) 으로 천단위 콤마 포맷 문자열을 넣어둠.
    final orderPrice = jsonOrder['totalAmount']?.toString() ?? '0';
    final discountPrice = jsonOrder['discountAmount']?.toString() ?? '0';
    final paymentPrice = jsonOrder['paymentAmount']?.toString() ?? '0';

    final labelW = width - amountW;
    b
      ..text(padRight('주문금액 : ', labelW))
      ..text(padLeft(orderPrice, amountW))
      ..ln()
      ..text(padRight('할인금액 : ', labelW))
      ..text(padLeft(discountPrice == '0' ? '0' : '-$discountPrice', amountW))
      ..ln()
      ..boldOn()
      ..text(padRight('결제금액 : ', labelW))
      ..text(padLeft(paymentPrice, amountW))
      ..ln()
      ..boldOff();

    final memo = jsonOrder['ordrMemo'] as String? ?? '';
    if (memo.isNotEmpty) {
      b
        ..ln()
        ..setAlign(EscPos.alignCenter)
        ..textLn(memo)
        ..setAlign(EscPos.alignLeft);
    }

    b
      ..setAlign(EscPos.alignCenter)
      ..ln();
    if (logoImageBytes != null) {
      await b.addImageRaster(logoImageBytes);
    }
    b
      ..ln()
      ..ln()
      ..ln()
      ..cut();
  }

  static Future<void> _appendOrder(
    ReceiptEscPosBuilder b,
    Map<String, dynamic> jsonOrder,
    bool isCancel,
    int width,
    Uint8List? logoImageBytes,
  ) async {
    // 주문서는 금액 없이 메뉴 / 수량만. 컬럼 폭: 메뉴(width-10) / 수량(10).
    const countW = 10;
    final menuW = width - countW;

    b
      ..init()
      ..setAlign(EscPos.alignCenter);

    if (isCancel) {
      b
        ..textLn('[취소주문서]')
        ..ln();
    }

    b
      ..boldOn()
      ..setSize(EscPos.fontTall);
    final displayNum =
        (jsonOrder['displayOrderNum'] as String?)?.isNotEmpty == true
            ? jsonOrder['displayOrderNum'] as String
            : (jsonOrder['ordrSimpleId'] as String? ?? '');
    b
      ..textLn('주문번호: $displayNum')
      ..setSize(EscPos.fontNormal)
      ..boldOff()
      ..ln();

    final userName = jsonOrder['userName'] as String?;
    if (userName != null && userName.isNotEmpty && userName != 'null') {
      b
        ..boldOn()
        ..setSize(EscPos.fontTall)
        ..textLn('$userName님')
        ..setSize(EscPos.fontNormal)
        ..boldOff();
    }
    final kioskId = jsonOrder['kioskId'] as String?;
    if (kioskId != null && kioskId.isNotEmpty && kioskId != 'null') {
      b.textLn('키오스크: $kioskId');
    }
    b.ln();

    b
      ..setAlign(EscPos.alignLeft)
      ..textLn(jsonOrder['storeName'] as String? ?? '')
      ..textLn('[일시] : ${jsonOrder['ordrDtm'] as String? ?? ''}')
      ..textLn(separatorLine(width))
      ..text(padRight('메뉴', menuW))
      ..text(padLeft('수량', countW))
      ..ln()
      ..textLn(separatorLine(width));

    final menuList = jsonOrder['ordrPrdList'];
    if (menuList is List) {
      for (final m in menuList) {
        if (m is! Map) continue;
        final menuName = m['prdNm'] as String? ?? '';
        final menuCount = (m['ordrCnt'] as num?)?.toInt() ?? 0;
        final countStr = isCancel ? '-$menuCount' : '$menuCount';

        b
          ..text(padRight(menuName, menuW))
          ..text(padLeft(countStr, countW))
          ..ln();

        final options = m['optPrdList'];
        if (options is List && options.isNotEmpty) {
          for (final o in options) {
            if (o is! Map) continue;
            final optName = o['optPrdNm'] as String? ?? '';
            final optCount = (o['optPrdCnt'] as num?)?.toInt() ?? 0;
            final optCountStr = isCancel ? '-$optCount' : '$optCount';
            b
              ..text(padRight(' -$optName', menuW))
              ..text(padLeft(optCountStr, countW))
              ..ln();
          }
          b.textLn(separatorLine(width));
        }
        b.ln();
      }
    }

    final memo = jsonOrder['ordrMemo'] as String? ?? '';
    if (memo.isNotEmpty) {
      b
        ..ln()
        ..setAlign(EscPos.alignCenter)
        ..textLn(memo)
        ..setAlign(EscPos.alignLeft);
    }

    b
      ..setAlign(EscPos.alignCenter)
      ..ln();
    if (logoImageBytes != null) {
      await b.addImageRaster(logoImageBytes);
    }
    b
      ..ln()
      ..ln()
      ..cut();
  }

  static void _appendTestPage(
    ReceiptEscPosBuilder b,
    String? comPort,
    int? baudRate,
    int width,
  ) {
    final now = DateTime.now();
    final ts =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';

    final innerWidth = width > 16 ? width - 16 : width;

    b
      ..init()
      ..setAlign(EscPos.alignCenter)
      ..setSize(EscPos.fontLarge)
      ..textLn('PRINTER TEST')
      ..setSize(EscPos.fontNormal)
      ..ln()
      ..textLn('AppFit Order Agent')
      ..ln()
      ..setAlign(EscPos.alignLeft)
      ..textLn(separatorLine(innerWidth))
      ..textLn('포트  : ${comPort ?? '-'}')
      ..textLn('보드  : ${baudRate ?? '-'} baud')
      ..textLn('일시  : $ts')
      ..textLn(separatorLine(innerWidth))
      ..ln()
      ..setAlign(EscPos.alignCenter)
      ..textLn('한글 ABC 0123 가나다 !@#')
      ..ln()
      ..textLn('이 영수증이 보이면 정상')
      // 종이 절단 위치 확보용 명시적 line feed.
      ..ln()
      ..ln()
      ..ln()
      ..ln()
      ..ln()
      ..cut();
  }

  static String _priceFmt(int v) {
    final s = v.toString();
    final buf = StringBuffer();
    final neg = s.startsWith('-');
    final digits = neg ? s.substring(1) : s;
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
      buf.write(digits[i]);
    }
    return neg ? '-${buf.toString()}' : buf.toString();
  }
}
