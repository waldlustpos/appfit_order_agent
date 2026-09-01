import 'package:flutter_test/flutter_test.dart';

import 'package:appfit_order_agent/services/label_printer/label_media_spec.dart';
import 'package:appfit_order_agent/utils/label_painter.dart';

/// `LabelMediaSpec.gap490x600` 이 [LabelPainter] 의 현행 상수와 정확히 일치하는지
/// 고정한다 — G30 spec 도입이 갭 라벨 기종(Caysn D2/D3, REXOD RXLA-561) 캔버스 크기를
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

  group('LabelMediaSpec.continuous58 — G30 58mm', () {
    // 눈금자 테스트 실기기 판독(2026-08-26): 인쇄 가능 영역 **52.5mm(≈420dot)**.
    // widthDots=412 는 거기서 8dot(1mm) 여유를 뺀 값 — continuous40 이 280 경계에서
    // 272 를 쓴 것과 같은 규칙. 값을 바꾸는 순간 이 테스트가 실패해 근거(실측 판독)를
    // 남기도록 강제한다.
    test('실측 확정값(유효 인쇄폭 52.5mm=420dot 경계에서 8dot 여유)', () {
      expect(LabelMediaSpec.continuous58.widthDots, 412);
      expect(LabelMediaSpec.continuous58.maxHeightDots, 640);
      expect(LabelMediaSpec.continuous58.minHeightDots, 300);
      expect(LabelMediaSpec.continuous58.variableHeight, isTrue);
    });

    test('40mm 값의 비례 확대가 아니다', () {
      // docs/PRINTER_FLOW.md §3.5 가 명시적으로 금지한 것 — 40mm 는 40mm 가이드
      // 전용 실측이라 58mm 에서 같은 비율이 성립한다는 보장이 없다. 실제로
      // 비례 확대(58×35/40=50.75mm)와 실측(52.5mm)은 1.75mm 어긋났다.
      final ratio = LabelMediaSpec.continuous58.widthDots /
          LabelMediaSpec.continuous40.widthDots;
      expect(ratio, isNot(closeTo(58 / 40, 0.01)));
    });

    test('유효 인쇄폭 경계(52.5mm=420dot) 안쪽이다 — 콘텐츠 우측 끝까지', () {
      final spec = LabelMediaSpec.continuous58;
      expect(spec.widthDots, lessThan(420));
      expect(spec.widthDots - spec.rightMarginDots, lessThan(420));
    });

    test('40mm 보다 넓다 — 콘텐츠 폭도 마찬가지', () {
      expect(LabelMediaSpec.continuous58.widthDots,
          greaterThan(LabelMediaSpec.continuous40.widthDots));
      expect(LabelMediaSpec.continuous58.contentWidthDots,
          greaterThan(LabelMediaSpec.continuous40.contentWidthDots));
    });

    test('물리 용지폭(58mm=464dot)과 헤드 최대폭(576dot)을 넘지 않는다', () {
      expect(LabelMediaSpec.continuous58.widthDots, lessThanOrEqualTo(464));
      expect(LabelMediaSpec.continuous58.widthDots, lessThanOrEqualTo(576));
    });

    test('contentWidthDots 는 좌우 여백을 뺀 값이다', () {
      final spec = LabelMediaSpec.continuous58;
      expect(spec.contentWidthDots,
          spec.widthDots - spec.sideMarginDots - spec.rightMarginDots);
    });
  });

  group('continuousForPaperMm — 설정값 → spec', () {
    test('58 만 continuous58, 나머지는 전부 40mm 폴백', () {
      expect(LabelMediaSpec.continuousForPaperMm(58),
          same(LabelMediaSpec.continuous58));
      expect(LabelMediaSpec.continuousForPaperMm(40),
          same(LabelMediaSpec.continuous40));
      // 알 수 없는 값은 좁은 쪽(잘릴 위험 없음)으로 떨어뜨린다.
      expect(LabelMediaSpec.continuousForPaperMm(0),
          same(LabelMediaSpec.continuous40));
      expect(LabelMediaSpec.continuousForPaperMm(80),
          same(LabelMediaSpec.continuous40));
    });
  });
}
