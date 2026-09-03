import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:appfit_order_agent/services/label_printer/label_media_spec.dart';
import 'package:appfit_order_agent/utils/continuous58_label_painter.dart';

/// `Continuous58LabelPainter` 의 세로 가변 계약 + 옵션 1열 기하 고정.
///
/// **절대 픽셀값을 단언하지 말 것** — flutter test 환경에는 Pretendard 가 로드되지
/// 않아 실기기와 advance 폭이 다르다(기존 continuous_label_painter_test.dart /
/// label_painter_fit_test.dart 와 같은 제약). 여기서는 폰트에 의존하지 않는 것만
/// 검증한다: ① 콘텐츠 유무에 따른 상대적 증감 ② gap 상수 합산 산수 ③ 셀 기하.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  double measure(Continuous58LabelPainter painter, LabelMediaSpec spec) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final bottom = painter.paintAndMeasure(
        canvas, Size(spec.widthDots, spec.maxHeightDots));
    recorder.endRecording();
    return bottom;
  }

  group('paintAndMeasure — 콘텐츠에 따른 상대적 높이', () {
    test('옵션·메모가 없는 라벨이 있는 라벨보다 낮다', () {
      const spec = LabelMediaSpec.continuous58;

      final minimal = Continuous58LabelPainter(
        spec: spec,
        menuName: '아메리카노',
        options: const [],
        shopOrderNo: '0001',
      );
      final full = Continuous58LabelPainter(
        spec: spec,
        menuName: '아이스 바닐라 라떼 (레귤러 사이즈)',
        options: const ['옵션A', '옵션B', '옵션C', '옵션D', '옵션E'],
        shopOrderNo: '0001-1',
        temperature: 'ICE',
        sizeOption: 'R',
        beanType: '다크',
        memo: '얼음 적게 주세요 감사합니다 오늘도 좋은 하루 되세요',
      );

      expect(measure(minimal, spec), lessThan(measure(full, spec)));
    });

    test('반환 높이는 항상 0 이상이다(빈 라벨도 크래시 없음)', () {
      const spec = LabelMediaSpec.continuous58;
      final empty = Continuous58LabelPainter(
        spec: spec,
        menuName: '',
        options: const [],
      );
      expect(measure(empty, spec), greaterThanOrEqualTo(0));
    });

    test('검정 반전 바는 서브정보가 있을 때만 세로를 차지한다', () {
      const spec = LabelMediaSpec.continuous58;
      final without = Continuous58LabelPainter(
        spec: spec,
        menuName: '',
        options: const [],
      );
      final with_ = Continuous58LabelPainter(
        spec: spec,
        menuName: '',
        options: const [],
        temperature: 'ICE',
      );
      expect(
        measure(with_, spec) - measure(without, spec),
        Continuous58LabelPainter.subInfoBarHeight +
            Continuous58LabelPainter.gapUnit,
      );
    });
  });

  group('가변 높이 clamp 산수 (generateContinuous58LabelImage 와 동일 공식)', () {
    // 폰트 메트릭을 아예 안 타게 구성한다 — menuName/subInfo/memo/표시번호/QR 을
    // 전부 비우면 남는 것은 고정 상수(헤더 높이 + gap + 구분선)뿐이고, 옵션은
    // optionRowHeight(고정 상수)만큼만 누적되므로 개수로 높이가 결정된다.
    //
    // 기대값은 painter 의 gap 상수를 직접 합산해서 만든다(매직넘버 하드코딩 금지)
    // — 실물 튜닝으로 gap 이 바뀌어도 이 테스트가 검증하는 불변식(빈 섹션은 자기
    // 높이도 gap 도 더하지 않는다 + 구분선은 항상 그린다)은 그대로 유지된다.
    const double emptyBaseline = Continuous58LabelPainter.topMargin +
        Continuous58LabelPainter.headerHeight +
        Continuous58LabelPainter.gapUnit + // 헤더 뒤
        1 + // 구분선
        Continuous58LabelPainter.gapUnit; // 구분선 뒤

    test('빈 콘텐츠는 고정 상수 합과 정확히 같다 (빈 섹션이 gap 을 남기지 않는다)', () {
      const spec = LabelMediaSpec.continuous58;
      final painter =
          Continuous58LabelPainter(spec: spec, menuName: '', options: const []);
      expect(measure(painter, spec), emptyBaseline);
    });

    test('빈 콘텐츠는 그보다 큰 minHeightDots 로 올림 clamp', () {
      final floorSpec = LabelMediaSpec(
        widthDots: 384,
        maxHeightDots: 640, // 상한은 넉넉히 — 이 테스트에서 개입 안 하게.
        minHeightDots: emptyBaseline + 60, // 자연 높이보다 확실히 크게.
        sideMarginDots: 0,
        rightMarginDots: 16,
        variableHeight: true,
      );
      final painter = Continuous58LabelPainter(
          spec: floorSpec, menuName: '', options: const []);
      final bottom = measure(painter, floorSpec);
      final h = (bottom + Continuous58LabelPainter.bottomMarginDots)
          .clamp(floorSpec.minHeightDots, floorSpec.maxHeightDots);
      expect(h, floorSpec.minHeightDots);
    });

    test('옵션 5개는 1열 5행 높이만큼 더한다', () {
      const spec = LabelMediaSpec.continuous58;
      final painter = Continuous58LabelPainter(
        spec: spec,
        menuName: '',
        options: const ['A', 'B', 'C', 'D', 'E'],
      );
      // 5개 → 1열 5행. 2열 3행(=3행 높이)으로 접지 않는 것이 이 레이아웃의 계약이다
      // (2열은 2026-09-03 폐기).
      expect(
        measure(painter, spec),
        emptyBaseline +
            5 * Continuous58LabelPainter.optionRowHeight +
            Continuous58LabelPainter.gapUnit,
      );
    });

    test('옵션이 많은 라벨은 그보다 작은 maxHeightDots 로 내림 clamp', () {
      const double eightOptionsBaseline = emptyBaseline +
          8 * Continuous58LabelPainter.optionRowHeight +
          Continuous58LabelPainter.gapUnit;
      final ceilingSpec = LabelMediaSpec(
        widthDots: 384,
        maxHeightDots: eightOptionsBaseline - 10, // 자연 높이보다 확실히 작게.
        minHeightDots: 40, // 하한은 넉넉히 낮게.
        sideMarginDots: 0,
        rightMarginDots: 16,
        variableHeight: true,
      );
      final painter = Continuous58LabelPainter(
        spec: ceilingSpec,
        menuName: '',
        options: const ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H'],
      );
      final bottom = measure(painter, ceilingSpec);
      expect(bottom, eightOptionsBaseline);

      final h = (bottom + Continuous58LabelPainter.bottomMarginDots)
          .clamp(ceilingSpec.minHeightDots, ceilingSpec.maxHeightDots);
      expect(h, ceilingSpec.maxHeightDots);
    });
  });

  group('optionCellsFor — 1열 기하', () {
    const double contentWidth = 368; // continuous58 의 콘텐츠 폭(384 - 0 - 16)

    List<dynamic> cells(int n) =>
        Continuous58LabelPainter.optionCellsFor(n, contentWidth: contentWidth);

    test('0개는 빈 목록', () {
      expect(cells(0), isEmpty);
    });

    test('개수와 무관하게 1열 — 셀 폭이 항상 콘텐츠 폭 전체', () {
      // 2열이던 시절의 경계(3/4개)를 포함해 훑는다 — 여기서 폭이 반으로 접히면
      // 2열 분기가 되살아난 것이다.
      for (final n in [1, 2, 3, 4, 5, 8]) {
        final c = cells(n);
        expect(c.length, n);
        for (final cell in c) {
          expect(cell.x, 0);
          expect(cell.maxWidth, contentWidth);
        }
      }
    });

    test('위→아래 한 줄씩 — 행 간격이 정확히 optionRowHeight', () {
      final c = cells(6);
      for (int i = 1; i < c.length; i++) {
        expect(c[i].x, c[0].x);
        expect(c[i].y - c[i - 1].y,
            closeTo(Continuous58LabelPainter.optionRowHeight, 0.001));
      }
    });

    test('optionMaxShown 초과분은 잘라낸다(+N 은 호출부 책임)', () {
      final c = cells(20);
      expect(c.length, Continuous58LabelPainter.optionMaxShown);
    });

    test('1열이므로 행 수가 곧 표시 개수다', () {
      final c = cells(20);
      final lastRow = c.last.y / Continuous58LabelPainter.optionRowHeight;
      expect(lastRow, Continuous58LabelPainter.optionMaxShown - 1);
    });

    test('어떤 셀도 콘텐츠 폭을 벗어나지 않는다', () {
      for (final n in [1, 2, 3, 4, 5, 8, 20]) {
        for (final cell in cells(n)) {
          expect(cell.x, greaterThanOrEqualTo(0));
          expect(
              cell.x + cell.maxWidth, lessThanOrEqualTo(contentWidth + 0.001));
        }
      }
    });
  });
}
