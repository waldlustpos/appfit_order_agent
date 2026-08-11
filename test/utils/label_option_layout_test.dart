import 'package:flutter_test/flutter_test.dart';

import 'package:appfit_order_agent/utils/label_painter.dart';

/// 라벨 옵션 셀 배치(`LabelPainter.optionCells`) 기하학 고정.
///
/// 렌더 없는 순수 함수라 Pretendard 로딩과 무관하게 검증할 수 있다.
/// 여기서 잠그는 불변식 2가지:
///   1) 세로 예약(84px)을 절대 넘지 않는다 → DETAIL 구분선/메모가 밀려
///      브랜드별 하단 여백(paik 49px)이 잘리는 사고를 구조적으로 막는다.
///   2) 2열 모드 col1 우측 끝이 구분선 끝과 정확히 일치한다 → 종전 5px 침범 재발 방지.
void main() {
  const double contentWidth =
      LabelPainter.width - LabelPainter.defaultMargin * 2; // 340
  const double dividerRight =
      LabelPainter.width - LabelPainter.defaultMargin; // 415

  group('optionCells — 1열 모드 (n <= optionSingleColumnMax)', () {
    test('옵션이 없으면 빈 리스트', () {
      expect(LabelPainter.optionCells(0), isEmpty);
      expect(LabelPainter.optionCells(-1), isEmpty);
    });

    for (var n = 1; n <= LabelPainter.optionSingleColumnMax; n++) {
      test('n=$n → 1열 $n행, 셀 폭이 콘텐츠 폭 전체(340)', () {
        final cells = LabelPainter.optionCells(n);

        expect(cells.length, n);
        for (var i = 0; i < n; i++) {
          expect(cells[i].maxWidth, contentWidth,
              reason: '1열 모드는 폭을 2배로 쓰는 것이 목적이다');
          expect(cells[i].x, LabelPainter.defaultMargin);
          expect(cells[i].y, i * LabelPainter.optionRowHeight);
        }
      });
    }
  });

  group('optionCells — 2열 모드 (n > optionSingleColumnMax)', () {
    test('n=4 → 2열 2행, 셀 폭 164', () {
      final cells = LabelPainter.optionCells(4);

      expect(cells.length, 4);
      const expectedWidth =
          (contentWidth - LabelPainter.optionColGutter) / 2; // 164
      for (final cell in cells) {
        expect(cell.maxWidth, expectedWidth);
      }
      expect(cells.map((c) => c.x).toSet(), {
        LabelPainter.defaultMargin,
        LabelPainter.defaultMargin +
            expectedWidth +
            LabelPainter.optionColGutter,
      });
      expect(
          cells.map((c) => c.y).toSet(), {0.0, LabelPainter.optionRowHeight});
    });

    test('col1 우측 끝이 옵션 구분선 끝(415)과 정확히 일치한다', () {
      // 종전 구현은 x=255 / maxWidth=165 라 우측 끝이 420 으로 5px 침범했다.
      final cells = LabelPainter.optionCells(4);
      final col1 = cells.firstWhere((c) => c.x > LabelPainter.defaultMargin);

      expect(col1.x + col1.maxWidth, dividerRight);
    });

    test('optionMaxShown 개까지는 모든 행을 꽉 채운다', () {
      final cells = LabelPainter.optionCells(LabelPainter.optionMaxShown);

      expect(cells.length, LabelPainter.optionMaxShown);
      expect(
        cells.map((c) => c.y).toSet().length,
        LabelPainter.optionMaxRows,
      );
    });

    test('초과분은 clamp (호출부가 마지막 셀을 +N 으로 표기)', () {
      expect(
        LabelPainter.optionCells(LabelPainter.optionMaxShown + 3).length,
        LabelPainter.optionMaxShown,
      );
      expect(LabelPainter.optionCells(100).length, LabelPainter.optionMaxShown);
    });
  });

  group('optionCells — 세로 예약 불변식', () {
    test('어떤 옵션 개수에서도 예약 높이를 넘지 않는다', () {
      for (var n = 1; n <= 30; n++) {
        final cells = LabelPainter.optionCells(n);
        final maxBottom = cells
            .map((c) => c.y + LabelPainter.optionRowHeight)
            .reduce((a, b) => a > b ? a : b);

        expect(
          maxBottom,
          lessThanOrEqualTo(LabelPainter.optionReservedHeight),
          reason: 'n=$n 에서 옵션이 DETAIL 구분선을 침범한다',
        );
      }
    });

    test('예약 높이는 행 높이 × 최대 행수와 일치한다', () {
      expect(
        LabelPainter.optionReservedHeight,
        LabelPainter.optionRowHeight * LabelPainter.optionMaxRows,
      );
    });
  });

  group('optionCells — 모든 셀이 콘텐츠 영역 안에 있다', () {
    test('좌측 마진 이상 / 우측 구분선 이하', () {
      for (var n = 1; n <= 10; n++) {
        for (final cell in LabelPainter.optionCells(n)) {
          expect(cell.x, greaterThanOrEqualTo(LabelPainter.defaultMargin),
              reason: 'n=$n');
          expect(cell.x + cell.maxWidth, lessThanOrEqualTo(dividerRight),
              reason: 'n=$n');
        }
      }
    });
  });
}
