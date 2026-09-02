import 'dart:math' show max;

import 'package:flutter_test/flutter_test.dart';

import 'package:appfit_order_agent/services/receipt_escpos_builder.dart';

/// 영수증/주문서 컬럼 정렬 characterization.
///
/// 컬럼은 "이름을 N 폭으로 우측 패딩 → 수량/금액을 M 폭으로 좌측 패딩" 만으로 만들어지므로,
/// 검증 대상은 "각 라인의 인코딩 폭이 정확히 용지 폭인가" + "수량 숫자가 항상 같은 열에서
/// 끝나는가" 두 가지다.
///
/// **폭은 파라미터화한다**: 42(POSBANK A8) 와 48(PR800) 두 기종을 모두 돈다.
/// [ReceiptEscPosBuilder.defaultColumns] 를 어느 쪽으로 바꾸든 정렬 명제가 깨지지
/// 않아야 하며, 실제로 48 하드코딩 시절엔 42 기종에서 구분선이 6칸 밀렸다.
///
/// 실제 CP949 인코더(win32 FFI)는 [ReceiptEscPosBuilder.runeWidthOverride] 로 대체해
/// 결정론적으로 만든다 — 테스트가 호스트 플랫폼에 의존하지 않게 한다.
void main() {
  const countW = 10;

  setUp(() {
    // CP949 규칙: ASCII 1 byte, CP949 수록 문자 2 byte, 미수록 문자는 '?' 1 byte.
    ReceiptEscPosBuilder.runeWidthOverride = (rune) {
      if (rune < 0x80) return 1;
      if (_notInCp949(rune)) return 1;
      return 2;
    };
  });

  tearDown(() => ReceiptEscPosBuilder.runeWidthOverride = null);

  test('defaultColumns 는 "실패하는 방향"이 안전한 쪽 — 좁은 값이어야 한다', () {
    // 폭을 실제보다 크게 잡으면 구분선·수량 칸이 밀려 출력물이 망가지고, 작게
    // 잡으면 여백만 남는다. 모르는 기종에서는 후자로 실패해야 한다.
    // 넓은 기종(PR800 48)은 knownPrinterColumns 프리시드가 되찾아 온다.
    expect(ReceiptEscPosBuilder.defaultColumns,
        lessThanOrEqualTo(ReceiptEscPosBuilder.columnOptions.reduce(max)));
    expect(ReceiptEscPosBuilder.columnOptions,
        contains(ReceiptEscPosBuilder.defaultColumns));
  });

  group('widthRulerLine — 눈금자 한 줄은 정확히 그 폭이어야 한다', () {
    // 이 명제가 깨지면 눈금자가 거짓말을 한다: 48줄이 실제로 47칸이면 42짜리
    // 프린터에서도 안 접혀서 "48이 맞다"고 오판하게 된다.
    for (final n in ReceiptEscPosBuilder.columnOptions) {
      test('$n 칸 줄의 폭은 정확히 $n', () {
        final line = ReceiptEscPosBuilder.widthRulerLine(n);
        expect(ReceiptEscPosBuilder.textWidth(line), n, reason: line);
        expect(line, startsWith('$n>'));
        expect(line, endsWith('#'));
      });
    }
  });

  group('textWidth', () {
    test('ASCII 1, 한글 2', () {
      expect(ReceiptEscPosBuilder.textWidth('ABC'), 3);
      expect(ReceiptEscPosBuilder.textWidth('아메리카노'), 10);
      expect(ReceiptEscPosBuilder.textWidth('ICE 아메리카노'), 4 + 10);
    });

    test('CP949 미수록 문자는 1 (이모지 = non-BMP, ☕ = BMP 미수록)', () {
      // 옛 휴리스틱은 이모지를 4(서로게이트 페어 x 2), ☕ 를 2 로 셌다 → 컬럼 밀림의 원인.
      expect(ReceiptEscPosBuilder.textWidth('🧋'), 1);
      expect(ReceiptEscPosBuilder.textWidth('☕'), 1);
    });
  });

  group('wrapByWidth', () {
    test('폭을 넘으면 rune 경계에서 접는다', () {
      // 한글 3자 = 6 폭.
      expect(
          ReceiptEscPosBuilder.wrapByWidth('아메리카노라떼', 6), ['아메리', '카노라', '떼']);
    });

    test('폭 이하면 그대로 한 줄', () {
      expect(ReceiptEscPosBuilder.wrapByWidth('아메리카노', 28), ['아메리카노']);
    });
  });

  // 42 = POSBANK A8, 48 = PR800. 두 기종 모두에서 같은 정렬 명제가 성립해야 한다.
  for (final width in const [42, 48]) {
    final receiptMenuW = width - countW - 10; // 영수증: 수량 + 금액 컬럼을 뺀 나머지
    final orderMenuW = width - countW; // 주문서: 금액 컬럼이 없다

    group('[$width 폭] 영수증 상품 라인', () {
      test('모든 라인이 정확히 $width 폭 — 수량/금액 컬럼이 밀리지 않는다', () async {
        final lines = await _receiptItemLines(
          _order(items: [
            _item('아메리카노', 1, 4500),
            _item('ICE 카페라떼', 2, 5000),
          ]),
          width: width,
        );

        for (final line in lines) {
          expect(ReceiptEscPosBuilder.textWidth(line), width, reason: line);
        }
      });

      test('CP949 미수록 문자(이모지)가 있어도 컬럼 유지 — 회귀 방지 핵심', () async {
        final lines = await _receiptItemLines(
          _order(items: [
            _item('아메리카노', 1, 4500),
            _item('버블티🧋', 1, 5500),
            _item('핸드드립☕', 2, 6000),
          ]),
          width: width,
        );

        for (final line in lines) {
          expect(ReceiptEscPosBuilder.textWidth(line), width, reason: line);
        }
        // 수량 숫자가 끝나는 열이 모든 줄에서 동일해야 한다.
        final countEnds = lines.map((l) => _countColumnEnd(l, receiptMenuW));
        expect(countEnds.toSet(), {receiptMenuW + countW});
      });

      test('취소 영수증의 -수량 / -금액 접두도 컬럼을 깨지 않는다', () async {
        final lines = await _receiptItemLines(
          _order(items: [_item('아메리카노', 12, 4500)]),
          isCancel: true,
          width: width,
        );
        expect(lines.first.trimRight(), endsWith('-54,000'));
        expect(ReceiptEscPosBuilder.textWidth(lines.first), width);
      });
    });

    group('[$width 폭] 긴 메뉴명 — 잘라내지 않고 둘째 줄로 접는다', () {
      test('영수증: 수량/금액은 첫 줄에 정렬 유지, 이름은 둘째 줄로 이어짐', () async {
        // 16자 x 2 = 32 폭 > menuW (42→22, 48→28) 이라 양쪽 폭에서 모두 접힌다.
        const name = '시그니처흑임자크림라떼라지사이즈';
        final lines = await _receiptItemLines(
          _order(items: [_item(name, 1, 6500)]),
          width: width,
        );

        expect(lines.length, 2);
        expect(lines[0], startsWith('시그니처'));
        expect(lines[0].trimRight(), endsWith('6,500'));
        expect(ReceiptEscPosBuilder.textWidth(lines[0]), width);

        // 잘림(…) 없이 이름 전체가 보존된다. 한글 1자 = 2 폭이라 첫 줄에 담기는
        // 글자 수는 menuW 의 절반이며, menuW 가 짝수라 패딩 없이 꽉 찬다.
        final firstChars = receiptMenuW ~/ 2;
        final joined = lines[0].substring(0, firstChars) + lines[1].trim();
        expect(joined, name);
        expect(lines[1], startsWith('  ')); // 이어지는 줄 들여쓰기
        expect(lines.every((l) => !l.contains('…')), isTrue);
      });

      test('주문서: 메뉴 폭 $orderMenuW 기준으로 접힌다', () async {
        const name = '시그니처흑임자크림라떼라지사이즈에스프레소샷추가';
        final lines = await _orderItemLines(
          _order(items: [_item(name, 3, 6500)]),
          width: width,
        );

        expect(lines.length, greaterThan(1));
        expect(ReceiptEscPosBuilder.textWidth(lines[0]), width);
        expect(lines[0].trimRight(), endsWith('3'));
        expect(_countColumnEnd(lines[0], orderMenuW), orderMenuW + countW);
      });
    });

    group('[$width 폭] 옵션 라인', () {
      test('옵션 수량이 상품 수량과 같은 열에서 끝난다', () async {
        final lines = await _orderItemLines(
          _order(items: [
            _item('아메리카노', 1, 4500, options: [
              _option('샷추가', 2, 500),
              _option('휘핑크림', 1, 300),
            ]),
          ]),
          width: width,
        );

        final rows = lines.where((l) => !l.startsWith('-')).toList();
        for (final line in rows) {
          expect(ReceiptEscPosBuilder.textWidth(line), width, reason: line);
          expect(_countColumnEnd(line, orderMenuW), orderMenuW + countW);
        }
        expect(rows[1], startsWith(' -샷추가'));
      });
    });
  }
}

// ---- helpers ----

/// 테스트용 CP949 미수록 판정. 실제 테이블 대신 이 테스트가 쓰는 문자만 다룬다.
bool _notInCp949(int rune) => rune > 0xFFFF || rune == 0x2615; // 🧋 등 / ☕

Map<String, dynamic> _order({required List<Map<String, dynamic>> items}) => {
      'displayOrderNum': 'A-1',
      'storeName': '테스트매장',
      'ordrDtm': '2026-07-14 10:00:00',
      'ordrPrdList': items,
    };

Map<String, dynamic> _item(
  String name,
  int qty,
  int price, {
  List<Map<String, dynamic>> options = const [],
}) =>
    {
      'prdNm': name,
      'ordrCnt': qty,
      'prdPrc': price,
      'optPrdList': options,
    };

Map<String, dynamic> _option(String name, int qty, int price) => {
      'optPrdNm': name,
      'optPrdCnt': qty,
      'optPrdPrc': price,
    };

/// 수량 셀의 오른쪽 끝 열. 이름 폭 [nameW] 뒤부터 countW(10) 만큼이 수량 셀이므로,
/// 수량 문자열이 끝나는 열이 항상 nameW + countW 여야 컬럼이 맞는 것이다.
int _countColumnEnd(String line, int nameW) {
  final cell = _slice(line, nameW, nameW + 10);
  return nameW + 10 - (cell.length - cell.trimRight().length);
}

/// 폭(바이트) 기준 부분 문자열. ASCII 만 다루는 셀이라 rune 수 = 폭.
String _slice(String line, int from, int to) {
  final buf = StringBuffer();
  int w = 0;
  for (final r in line.runes) {
    final rw = ReceiptEscPosBuilder.runeWidth(r);
    if (w >= from && w < to) buf.writeCharCode(r);
    w += rw;
  }
  return buf.toString();
}

/// 영수증 본문에서 상품/옵션 라인만 추출 (헤더~구분선 이후, 합계 이전).
Future<List<String>> _receiptItemLines(
  Map<String, dynamic> order, {
  bool isCancel = false,
  required int width,
}) async =>
    _itemLines(await ReceiptEscPosBuilder.debugReceiptLines(
        jsonOrder: order, isCancel: isCancel, width: width));

Future<List<String>> _orderItemLines(
  Map<String, dynamic> order, {
  bool isCancel = false,
  required int width,
}) async =>
    _itemLines(await ReceiptEscPosBuilder.debugOrderLines(
        jsonOrder: order, isCancel: isCancel, width: width));

/// '메뉴/수량' 헤더 다음 구분선 이후부터, 합계/과세 블록 전까지.
List<String> _itemLines(List<String> lines) {
  final headerIdx = lines.indexWhere((l) => l.startsWith('메뉴'));
  final start = headerIdx + 2; // 헤더 + 구분선
  final out = <String>[];
  for (final l in lines.skip(start)) {
    if (l.trim().isEmpty) continue;
    if (l.contains('과세금액') || l.contains('주문금액')) break;
    out.add(l);
  }
  return out;
}
