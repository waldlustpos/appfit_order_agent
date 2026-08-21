import 'package:flutter_test/flutter_test.dart';

import 'package:appfit_order_agent/services/label_printer/label_media_spec.dart';
import 'package:appfit_order_agent/utils/label_painter.dart';

/// `LabelMediaSpec.gap490x600` 이 [LabelPainter] 의 현행 상수와 정확히 일치하는지
/// 고정한다 — G30 spec 도입이 기존 3기종(Caysn/REXOD/XD5-40d) 캔버스 크기를
/// 건드리지 않았음을 보장하는 회귀 가드.
void main() {
  group('LabelMediaSpec.gap490x600 — 기존 LabelPainter 상수와 일치', () {
    test('폭/높이/여백이 LabelPainter 상수 그대로다', () {
      expect(LabelMediaSpec.gap490x600.widthDots, LabelPainter.width);
      expect(LabelMediaSpec.gap490x600.maxHeightDots, LabelPainter.height);
      expect(
          LabelMediaSpec.gap490x600.sideMarginDots, LabelPainter.defaultMargin);
    });

    test('고정 높이(갭 라벨) — variableHeight=false', () {
      expect(LabelMediaSpec.gap490x600.variableHeight, isFalse);
      // 고정 크기라 min==max 여야 clamp 가 항상 고정값 하나로 수렴한다.
      expect(LabelMediaSpec.gap490x600.minHeightDots,
          LabelMediaSpec.gap490x600.maxHeightDots);
    });

    test('rightMarginDots 생략 시 sideMarginDots 와 대칭', () {
      expect(LabelMediaSpec.gap490x600.rightMarginDots,
          LabelMediaSpec.gap490x600.sideMarginDots);
    });
  });

  group('LabelMediaSpec.continuous40 — G30 40mm', () {
    // 2026-08-21 결론: 캔버스는 용지 물리폭(320=40mm)이 아니라 실측 유효
    // 인쇄폭(280dot=35mm) 그대로다 — 인쇄 시작 위치가 하드웨어에 고정돼
    // 있어(margin 을 아무리 조정해도 시각 중앙이 안 맞았다, 3회 재현) 캔버스를
    // 물리 용지폭으로 넓게 잡아도 그 여분을 중앙 보정에 쓸 수 없었다.
    test('실측 확정값(유효 인쇄폭 근사 272dot, 물리 용지폭 320 이 아님)', () {
      expect(LabelMediaSpec.continuous40.widthDots, 272);
      expect(LabelMediaSpec.continuous40.maxHeightDots, 640); // 80mm cap
      expect(LabelMediaSpec.continuous40.variableHeight, isTrue);
    });

    test('minHeightDots 는 maxHeightDots 이하다', () {
      expect(LabelMediaSpec.continuous40.minHeightDots,
          lessThanOrEqualTo(LabelMediaSpec.continuous40.maxHeightDots));
    });

    test('좌측 여백은 0(하드웨어가 이미 여백을 두고 시작) — 우측만 여유를 둔다', () {
      final spec = LabelMediaSpec.continuous40;
      expect(spec.sideMarginDots, 0);
      expect(spec.rightMarginDots, 16);
      expect(spec.rightMarginDots, greaterThan(spec.sideMarginDots));
    });

    test('콘텐츠 우측 끝은 실측 인쇄가능 경계(280dot=35mm) 안쪽이다', () {
      final spec = LabelMediaSpec.continuous40;
      final contentRightEdge = spec.widthDots - spec.rightMarginDots;
      expect(contentRightEdge, lessThanOrEqualTo(280));
    });

    test('contentWidthDots 는 좌우 여백을 뺀 값이다', () {
      final spec = LabelMediaSpec.continuous40;
      expect(spec.contentWidthDots,
          spec.widthDots - spec.sideMarginDots - spec.rightMarginDots);
    });
  });
}
