import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'package:appfit_order_agent/i18n/strings.g.dart';
import 'package:appfit_order_agent/models/order_model.dart';
import 'package:appfit_order_agent/services/escpos_builder.dart';
import 'package:appfit_order_agent/services/platform_service.dart';

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
  /// 외부 영수증 프린터의 1행 컬럼 수 **기본값**(= CP949 인코딩 바이트 수).
  ///
  /// 기종마다 실효 컬럼이 다르다 — 48 = PR800(576dot), 42 = POSBANK A8. 같은
  /// 바이트를 보내도 42 짜리 프린터는 48 컬럼 구분선을 42 에서 접어 `-` 6개가
  /// 다음 줄로 밀리고 수량 컬럼까지 한 줄 밀린다.
  ///
  /// 폭은 기기 설정([PreferenceService.getExternalPrinterColumns])이 정본이고
  /// 이 값은 **미설정 시 폴백**이다. ESC/POS 에는 "몇 컬럼이냐" 를 묻는 표준
  /// 질의가 없어서(`GS W` 는 쓰기 전용) 자동 판별이 불가능하다 — 알려진 기종은
  /// VID:PID 로 프리시드하고(`knownPrinterColumns`), 나머지는
  /// [buildWidthRulerBytes] 눈금자로 사람이 확인한다.
  ///
  /// **42 를 기본으로 두는 이유는 "실패하는 방향"이다.** 폭을 실제보다 크게
  /// 잡으면 구분선과 수량 칸이 다음 줄로 밀려 출력물이 망가지지만, 작게 잡으면
  /// 우측 여백이 남을 뿐 읽을 수는 있다. 모르는 기종에서는 조용히 망가지는 쪽보다
  /// 여백이 남는 쪽으로 실패해야 한다. POSBANK 계열(A8·A11 실측)이 42 이고 넓은
  /// 쪽(PR800 48)은 예외 테이블로 잡는다.
  static const int defaultColumns = 42;

  /// 설정 UI 가 제시하는 폭 후보. 80mm(48) / 80mm 좁은 인쇄영역(42) / 58mm(32).
  static const List<int> columnOptions = [48, 42, 32];

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

  /// 누적된 세그먼트를 텍스트 라인으로 렌더링 (인코딩/전송 없음).
  /// raw 세그먼트 중 LF 만 개행으로 반영하고 나머지 ESC/POS 명령은 무시한다.
  /// 컬럼 정렬 테스트가 바이트 덤프 대신 라인을 직접 보게 하는 seam.
  @visibleForTesting
  List<String> toTextLines() {
    final buf = StringBuffer();
    for (final s in _segs) {
      switch (s) {
        case _TextSeg(:final text):
          buf.write(text);
        case _RawSeg(:final bytes):
          if (bytes.length == 1 && bytes.first == 0x0A) buf.write('\n');
      }
    }
    return buf.toString().split('\n');
  }

  @visibleForTesting
  static Future<List<String>> debugReceiptLines({
    required Map<String, dynamic> jsonOrder,
    bool isCancel = false,
    int width = defaultColumns,
  }) async {
    final b = ReceiptEscPosBuilder();
    await _appendReceipt(b, jsonOrder, isCancel, width, null);
    return b.toTextLines();
  }

  @visibleForTesting
  static Future<List<String>> debugOrderLines({
    required Map<String, dynamic> jsonOrder,
    bool isCancel = false,
    int width = defaultColumns,
  }) async {
    final b = ReceiptEscPosBuilder();
    await _appendOrder(b, jsonOrder, isCancel, width, null);
    return b.toTextLines();
  }

  // ---- 패딩 / 라인 폭 헬퍼 ----
  //
  // 컬럼 정렬은 "이름을 N 폭으로 우측 패딩 → 수량/금액을 M 폭으로 좌측 패딩" 만으로
  // 만들어진다. 따라서 폭 계산이 [toBytesCp949] 가 실제로 내보내는 바이트 수와
  // 정확히 일치해야 컬럼이 맞는다. 과거의 "ASCII 1 / 그 외 2" 휴리스틱은 CP949 에
  // 없는 문자(이모지 등 non-BMP, ☕ 같은 미수록 기호)에서 어긋났다 — 실제로는 '?'
  // 1 바이트로 인코딩되는데 2~4 로 셌기 때문에 수량 컬럼이 밀렸다.

  static final Map<int, int> _runeWidthCache = {};

  /// 테스트에서 플랫폼 인코더(win32 FFI)를 우회하기 위한 seam.
  @visibleForTesting
  static int Function(int rune)? runeWidthOverride;

  /// rune 하나가 CP949 로 인코딩됐을 때의 바이트 수 = 프린터 컬럼 수.
  ///
  /// Windows 는 실제 인코더([EscPos.cp949ByteLength] → `WideCharToMultiByte(949)`)로
  /// 실측한다. CP949 미수록 문자는 '?' 1 바이트를 돌려주므로 출력 바이트와 항상 일치.
  /// rune 종류가 한정적이라 캐시로 FFI 호출 비용은 사실상 0.
  static int runeWidth(int rune) {
    final override = runeWidthOverride;
    if (override != null) return override(rune);
    return _runeWidthCache.putIfAbsent(rune, () {
      if (rune < 0x80) return 1;
      if (Platform.isWindows) {
        final n = EscPos.cp949ByteLength(String.fromCharCode(rune));
        return n > 0 ? n : 1;
      }
      // Android(Java `getBytes("EUC-KR")`) 근사 — non-BMP 는 '?' 1 바이트.
      return rune > 0xFFFF ? 1 : 2;
    });
  }

  /// 문자열의 CP949 인코딩 폭(= 프린터 컬럼 수).
  static int textWidth(String s) {
    int n = 0;
    for (final r in s.runes) {
      n += runeWidth(r);
    }
    return n;
  }

  /// 인코딩 폭 기준 우측 공백 padding.
  static String padRight(String text, int totalWidth) {
    final need = totalWidth - textWidth(text);
    if (need <= 0) return text;
    return text + ' ' * need;
  }

  /// 인코딩 폭 기준 좌측 공백 padding.
  static String padLeft(String text, int totalWidth) {
    final need = totalWidth - textWidth(text);
    if (need <= 0) return text;
    return ' ' * need + text;
  }

  /// 인코딩 폭 기준 하드 wrap. 단어 경계는 보지 않는다 (한글 메뉴명 기준).
  static List<String> wrapByWidth(String s, int width) {
    if (s.isEmpty) return const [''];
    if (width <= 0) return [s];
    final out = <String>[];
    final buf = StringBuffer();
    int used = 0;
    for (final r in s.runes) {
      final w = runeWidth(r);
      if (used + w > width && used > 0) {
        out.add(buf.toString());
        buf.clear();
        used = 0;
      }
      buf.writeCharCode(r);
      used += w;
    }
    if (buf.isNotEmpty) out.add(buf.toString());
    return out;
  }

  static String separatorLine(int width) => '-' * width;

  /// 상품/옵션 한 행. 이름이 [nameW] 를 넘으면 잘라내지 않고 다음 줄로 접는다.
  /// 수량/금액([rightCols]: (텍스트, 컬럼폭))은 첫 줄에만 우측 정렬로 붙고,
  /// 이어지는 줄은 [contIndent] 만큼 들여쓴 뒤 이름만 계속 출력한다.
  static void _row(
    ReceiptEscPosBuilder b,
    String name,
    int nameW,
    List<(String, int)> rightCols, {
    String contIndent = '  ',
  }) {
    final lines = wrapByWidth(name, nameW);

    b.text(padRight(lines.first, nameW));
    for (final (text, width) in rightCols) {
      b.text(padLeft(text, width));
    }
    b.ln();

    if (lines.length == 1) return;

    // 첫 줄에서 넘친 부분을 들여쓰기 폭에 맞춰 다시 접는다.
    final rest = lines.skip(1).join();
    final contW = nameW - textWidth(contIndent);
    for (final line in wrapByWidth(rest, contW)) {
      b.textLn('$contIndent$line');
    }
  }

  // ---- 문서 빌더: 영수증 / 주문서 / 테스트 페이지 ----

  /// 영수증(RECEIPT) — 금액/세금/총액 포함.
  static Future<Uint8List> buildReceiptBytes({
    required Map<String, dynamic> jsonOrder,
    required bool isCancel,
    int width = defaultColumns,
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
    int width = defaultColumns,
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
    int width = defaultColumns,
  }) async {
    final b = ReceiptEscPosBuilder();
    _appendTestPage(b, comPort, baudRate, width);
    return await b.toBytesCp949();
  }

  /// 설정 UI "용지 폭 확인" — 폭 후보별 눈금자.
  ///
  /// ESC/POS 에는 프린터에게 컬럼 수를 묻는 표준 질의가 없다(`GS I` 로 모델명은
  /// 읽히지만 양방향 인터페이스 + 모델 테이블이 필요하고, `GS W` 는 쓰기 전용이라
  /// 프린터가 자기 인쇄 영역을 알려주지 않는다). 그래서 **사람이 눈으로 확인**한다.
  ///
  /// [columnOptions] 각 값마다 정확히 그 폭을 채우는 막대를 한 줄씩 찍는다.
  /// 용지보다 넓은 막대는 프린터가 접어서 다음 줄에 꼬리를 남기므로, **넘치지 않은
  /// 가장 위의 줄**이 곧 용지 폭이다. 안내 문구는 가장 좁은 후보(32)에서도 접히지
  /// 않도록 짧게 유지할 것 — 안내가 접히면 진단 자체가 헷갈린다.
  ///
  /// 좌측 여백(`GS L`) 때문에 좁아 보이는 경우와 구분하는 것도 이 출력의 몫이다:
  /// 막대가 왼쪽 끝에서 시작하지 않고 앞에 빈칸이 있으면 컬럼 수가 아니라 여백
  /// 문제이므로, 폭을 줄이는 대신 `GS L 0` 송출을 검토해야 한다.
  static Future<Uint8List> buildWidthRulerBytes({int? currentColumns}) async {
    final b = ReceiptEscPosBuilder();
    b
      ..init()
      ..setAlign(EscPos.alignLeft)
      ..boldOn()
      ..textLn('[용지 폭 확인]')
      ..boldOff()
      ..textLn('넘치지 않은 가장 위 줄이')
      ..textLn('현재 용지 폭입니다.')
      ..ln();

    for (final n in columnOptions) {
      b.textLn(widthRulerLine(n));
    }

    b
      ..ln()
      ..textLn('현재 설정: ${currentColumns ?? defaultColumns}칸')
      ..ln()
      ..ln()
      ..ln()
      ..cut();
    return await b.toBytesCp949();
  }

  /// 정확히 [n] 컬럼을 채우는 눈금자 한 줄. `48>----...----#` 형태.
  ///
  /// 앞의 숫자는 그 줄이 몇 칸짜리인지 알려주고, 끝의 `#` 는 "여기가 끝" 표시라
  /// 꼬리가 다음 줄로 넘어갔는지 한눈에 보인다. 모두 ASCII 라 CP949 에서 1바이트.
  @visibleForTesting
  static String widthRulerLine(int n) {
    final head = '$n>';
    final fill = n - head.length - 1;
    if (fill < 0) return head;
    return '$head${'-' * fill}#';
  }

  /// 기기 호출(DEVICE_CALL_REQUESTED) 알림 슬립 — deviceId / 일시 / 문구.
  static Future<Uint8List> buildDeviceCallBytes({
    required String deviceId,
    required String dateTime,
    required String phrase,
    int width = defaultColumns,
  }) async {
    final b = ReceiptEscPosBuilder();
    _appendDeviceCall(b, deviceId, dateTime, phrase, width);
    return await b.toBytesCp949();
  }

  // ---- 내부 헬퍼 ----

  /// 주문 JSON 의 `orderType`(IN_SHOP/TAKE_OUT) 을 매장/포장 라벨로 변환한다.
  /// `showOrderType` 이 false 면(설정 토글 OFF) null 을 반환해 인쇄를 건너뛴다.
  /// 그 외 값(레거시 H/T/C 등)은 표기하지 않는다 — 주문 상세 팝업 배지와 동일 스코프.
  static String? _orderTypeLabel(
    Map<String, dynamic> jsonOrder,
    String Function(String key, String ko) lbl,
  ) {
    if ((jsonOrder['showOrderType'] as bool?) == false) return null;
    final ot = (jsonOrder['orderType'] as String? ?? '').toUpperCase();
    return switch (ot) {
      'IN_SHOP' => lbl('type_dine_in', '매장'),
      'TAKE_OUT' => lbl('type_takeout', '포장'),
      _ => null,
    };
  }

  /// 주문 JSON 의 `source`(WALD_KIOSK 등) 를 주문서에 찍을 출처 태그로 변환한다.
  /// 주문 상세 팝업의 출처 배지(`_SourcePill`)와 동일한 문자열이며, 분류 정본은
  /// [classifyOrderSource] 하나다 — 여기서 접미사 규칙을 재구현하지 않는다.
  static String _orderSourceTag(Map<String, dynamic> jsonOrder) {
    final source = jsonOrder['source']?.toString() ?? '';
    return switch (classifyOrderSource(source)) {
      OrderSourceType.app => 'APP',
      OrderSourceType.kiosk => 'KIOSK',
      OrderSourceType.pos => 'POS',
    };
  }

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

    // PrintService 가 현재 로캘 번역을 jsonOrder['labels'] 로 주입. 누락 시 한국어 fallback.
    final labels = jsonOrder['labels'] as Map?;
    String lbl(String key, String ko) {
      final v = labels?[key];
      return v is String ? v : ko;
    }

    b
      ..init()
      ..setAlign(EscPos.alignCenter);

    if (isCancel) {
      b
        ..boldOn()
        ..setSize(EscPos.fontTall)
        ..textLn('[${lbl('cancel_receipt', '취소영수증')}]')
        ..setSize(EscPos.fontNormal)
        ..boldOff()
        ..ln();
    }

    b
      ..boldOn()
      ..setSize(EscPos.fontTall);
    final displayNum =
        (jsonOrder['displayOrderNum'] as String?)?.isNotEmpty == true
            ? jsonOrder['displayOrderNum'] as String
            : (jsonOrder['ordrSimpleId'] as String? ?? '');
    b.textLn('${lbl('order_no', '주문번호')} : $displayNum');
    final orderTypeLabel1 = _orderTypeLabel(jsonOrder, lbl);
    if (orderTypeLabel1 != null) b.textLn(orderTypeLabel1);
    b
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
      ..textLn(
          '[${lbl('datetime', '일시')}]   : ${jsonOrder['ordrDtm'] as String? ?? ''}')
      ..textLn(separatorLine(width))
      ..text(padRight(lbl('col_menu', '메뉴'), menuW))
      ..text(padLeft(lbl('col_qty', '수량'), countW))
      ..text(padLeft(lbl('col_amount', '금액'), amountW))
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

        _row(b, menuName, menuW, [
          (countStr, countW),
          (amountStr, amountW),
        ]);

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

            // 이어지는 줄은 ' -' 다음 옵션명 시작 위치에 맞춰 3칸 들여쓴다.
            _row(
              b,
              ' -$optName',
              menuW,
              [(optCountStr, countW), (optAmountStr, amountW)],
              contIndent: '   ',
            );
          }
          b.textLn(separatorLine(width));
        }
      }
    }

    b
      ..setAlign(EscPos.alignRight)
      ..textLn(
          '${lbl('taxable', '과세금액')}: ${jsonOrder['exceptTaxPrice'] ?? '0'}')
      ..textLn('${lbl('vat', '부가세')}: ${jsonOrder['taxPrice'] ?? '0'}')
      ..setAlign(EscPos.alignLeft)
      ..textLn(separatorLine(width));

    // OrderModel.toSunmiJson 이 fmt.format(...) 으로 천단위 콤마 포맷 문자열을 넣어둠.
    final orderPrice = jsonOrder['totalAmount']?.toString() ?? '0';
    final discountPrice = jsonOrder['discountAmount']?.toString() ?? '0';
    final paymentPrice = jsonOrder['paymentAmount']?.toString() ?? '0';

    final labelW = width - amountW;
    b
      ..text(padRight('${lbl('order_amount', '주문금액')} : ', labelW))
      ..text(padLeft(orderPrice, amountW))
      ..ln()
      ..text(padRight('${lbl('discount_amount', '할인금액')} : ', labelW))
      ..text(padLeft(discountPrice == '0' ? '0' : '-$discountPrice', amountW))
      ..ln()
      ..boldOn()
      ..text(padRight('${lbl('payment_amount', '결제금액')} : ', labelW))
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

    // PrintService 가 현재 로캘 번역을 jsonOrder['labels'] 로 주입. 누락 시 한국어 fallback.
    final labels = jsonOrder['labels'] as Map?;
    String lbl(String key, String ko) {
      final v = labels?[key];
      return v is String ? v : ko;
    }

    b
      ..init()
      ..setAlign(EscPos.alignCenter);

    if (isCancel) {
      b
        ..textLn('[${lbl('cancel_order', '취소주문서')}]')
        ..ln();
    }

    b
      ..boldOn()
      ..setSize(EscPos.fontTall);
    final displayNum =
        (jsonOrder['displayOrderNum'] as String?)?.isNotEmpty == true
            ? jsonOrder['displayOrderNum'] as String
            : (jsonOrder['ordrSimpleId'] as String? ?? '');
    // 주문번호 줄 전체(라벨+번호)를 fontLarge(0x11, 2x2)로 출력한다.
    // 가로 2배는 실효 컬럼을 [defaultColumns] 의 절반으로 줄인다 — 42 기준 21,
    // 48 기준 24. '주문번호: 0006' 은 2배 적용 시 28컬럼이라 양쪽 모두 프린터가
    // 줄을 접을 수 있고, 42 로 내리면 여유가 3컬럼 더 줄어든다. 접히면 라벨을
    // 줄이거나 번호만 키우는 쪽으로 되돌린다.
    b
      ..setSize(EscPos.fontLarge)
      ..textLn('${lbl('order_no', '주문번호')}: $displayNum')
      ..setSize(EscPos.fontTall);
    // 취식구분 앞에 출처 태그를 붙인다 — '[KIOSK] 매장' / '[APP] 포장'.
    // 주방용 주문서에만 붙이고 손님용 영수증은 취식구분만 유지한다.
    // 태그 노출 자체는 '키오스크 주문 주문서 및 알림소리' 설정이 켜져 있을 때만 —
    // print_service.dart 가 jsonOrder['showOrderSourceTag'] 로 주입한다.
    final orderTypeLabel0 = _orderTypeLabel(jsonOrder, lbl);
    if (orderTypeLabel0 != null) {
      final showSourceTag = jsonOrder['showOrderSourceTag'] as bool? ?? false;
      final prefix = showSourceTag ? '[${_orderSourceTag(jsonOrder)}] ' : '';
      // 주문번호 줄과 살짝 띄우기 위한 여백 한 줄.
      b
        ..ln()
        ..textLn('$prefix$orderTypeLabel0');
    }
    b
      ..setSize(EscPos.fontNormal)
      ..boldOff()
      ..ln();

    final userName = jsonOrder['userName'] as String?;
    if (userName != null && userName.isNotEmpty && userName != 'null') {
      b
        ..boldOn()
        ..setSize(EscPos.fontTall)
        ..textLn('$userName${lbl('customer_suffix', '님')}')
        ..setSize(EscPos.fontNormal)
        ..boldOff();
    }
    final kioskId = jsonOrder['kioskId'] as String?;
    if (kioskId != null && kioskId.isNotEmpty && kioskId != 'null') {
      b.textLn('${lbl('kiosk', '키오스크')}: $kioskId');
    }
    b.ln();

    b
      ..setAlign(EscPos.alignLeft)
      ..textLn(jsonOrder['storeName'] as String? ?? '')
      ..textLn(
          '[${lbl('datetime', '일시')}] : ${jsonOrder['ordrDtm'] as String? ?? ''}')
      ..textLn(separatorLine(width))
      ..text(padRight(lbl('col_menu', '메뉴'), menuW))
      ..text(padLeft(lbl('col_qty', '수량'), countW))
      ..ln()
      ..textLn(separatorLine(width));

    final menuList = jsonOrder['ordrPrdList'];
    if (menuList is List) {
      for (final m in menuList) {
        if (m is! Map) continue;
        final menuName = m['prdNm'] as String? ?? '';
        final menuCount = (m['ordrCnt'] as num?)?.toInt() ?? 0;
        final countStr = isCancel ? '-$menuCount' : '$menuCount';

        // 주방에서 잘 보이도록 메뉴/옵션 모두 세로 2배로 출력 (kokonut_order_agent_v2 와 동일).
        // fontTall(0x01)은 가로 배율 1배라 [width] 기준 컬럼 계산이 그대로 유효하다.
        // fontLarge(0x11)는 가로 2배라 패딩된 라인에 쓰면 컬럼이 깨진다.
        b.setSize(EscPos.fontTall);
        _row(b, menuName, menuW, [(countStr, countW)]);

        final options = m['optPrdList'];
        if (options is List && options.isNotEmpty) {
          for (final o in options) {
            if (o is! Map) continue;
            final optName = o['optPrdNm'] as String? ?? '';
            final optCount = (o['optPrdCnt'] as num?)?.toInt() ?? 0;
            final optCountStr = isCancel ? '-$optCount' : '$optCount';
            _row(
              b,
              ' -$optName',
              menuW,
              [(optCountStr, countW)],
              contIndent: '   ',
            );
          }
          b
            ..setSize(EscPos.fontNormal)
            ..textLn(separatorLine(width));
        }
        b
          ..setSize(EscPos.fontNormal)
          ..ln();
      }
    }

    final memo = jsonOrder['ordrMemo'] as String? ?? '';
    if (memo.isNotEmpty) {
      // 메모도 메뉴와 동일한 폰트 크기(주문서: 세로 2배)로 출력.
      b
        ..ln()
        ..setAlign(EscPos.alignCenter)
        ..setSize(EscPos.fontTall)
        ..textLn(memo)
        ..setSize(EscPos.fontNormal)
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
      ..textLn('${t.receipt.test_port}  : ${comPort ?? '-'}')
      ..textLn('${t.receipt.test_board}  : ${baudRate ?? '-'} baud')
      ..textLn('${t.receipt.datetime}  : $ts')
      ..textLn(separatorLine(innerWidth))
      ..ln()
      ..setAlign(EscPos.alignCenter)
      ..textLn('한글 ABC 0123 가나다 !@#')
      ..ln()
      ..textLn(t.receipt.test_ok)
      // 종이 절단 위치 확보용 명시적 line feed.
      ..ln()
      ..ln()
      ..ln()
      ..ln()
      ..ln()
      ..cut();
  }

  static void _appendDeviceCall(
    ReceiptEscPosBuilder b,
    String deviceId,
    String dateTime,
    String phrase,
    int width,
  ) {
    // '키오스크번호'(EUC-KR 12 byte) 기준 라벨 컬럼 폭. '일시' 라벨도 이 폭에 맞춰
    // padding 해 콜론 위치를 정렬한다.
    const labelW = 12;

    b
      ..init()
      // 상단 헤드라인 = 호출 문구(용지 확인 / 직원 호출) 자체.
      ..setAlign(EscPos.alignCenter)
      ..setSize(EscPos.fontTall)
      ..boldOn()
      ..textLn(phrase)
      ..boldOff()
      ..setSize(EscPos.fontNormal)
      ..ln()
      ..setAlign(EscPos.alignLeft)
      // 구분선은 용지 폭 전체(width)로 그린다.
      ..textLn(separatorLine(width))
      ..textLn('${padRight('키오스크번호', labelW)}: $deviceId')
      ..textLn('${padRight(t.receipt.datetime, labelW)}: $dateTime')
      ..textLn(separatorLine(width))
      // 종이 절단 위치 확보용 명시적 line feed.
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
