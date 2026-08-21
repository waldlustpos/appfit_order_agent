import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:appfit_order_agent/services/label_printer/label_media_spec.dart';
import 'package:appfit_order_agent/utils/continuous_label_painter.dart';

/// `ContinuousLabelPainter.paintAndMeasure` 의 세로 가변 계약 고정.
///
/// **절대 픽셀값을 단언하지 말 것** — flutter test 환경에는 Pretendard 가
/// 로드되지 않아 실기기와 advance 폭이 다르다(기존 label_painter_fit_test.dart
/// 와 같은 제약). 여기서는 clamp 산수 자체와 콘텐츠 유무에 따른 상대적
/// 증감만 검증한다. 실제 높이 판정은 설정 화면 라벨 테스트 출력으로 육안 확인.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  double measure(ContinuousLabelPainter painter, LabelMediaSpec spec) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final bottom = painter.paintAndMeasure(
        canvas, Size(spec.widthDots, spec.maxHeightDots));
    recorder.endRecording();
    return bottom;
  }

  group('paintAndMeasure — 콘텐츠에 따른 상대적 높이', () {
    test('옵션·메모가 없는 라벨이 있는 라벨보다 낮다', () {
      const spec = LabelMediaSpec.continuous40;

      final minimal = ContinuousLabelPainter(
        spec: spec,
        menuName: '아메리카노',
        options: const [],
        shopOrderNo: '0001',
      );
      final full = ContinuousLabelPainter(
        spec: spec,
        menuName: '아이스 바닐라 라떼 (레귤러 사이즈)',
        options: const ['옵션A', '옵션B', '옵션C', '옵션D', '옵션E'],
        shopOrderNo: '0001-1',
        memo: '얼음 적게 주세요 감사합니다 오늘도 좋은 하루 되세요',
      );

      final minimalH = measure(minimal, spec);
      final fullH = measure(full, spec);

      expect(minimalH, lessThan(fullH));
    });

    test('반환 높이는 항상 0 이상이다(빈 라벨도 크래시 없음)', () {
      const spec = LabelMediaSpec.continuous40;
      final empty = ContinuousLabelPainter(
        spec: spec,
        menuName: '',
        options: const [],
      );
      expect(measure(empty, spec), greaterThanOrEqualTo(0));
    });
  });

  group('가변 높이 clamp 산수 (generateContinuousLabelImage 와 동일 공식)', () {
    // 두 시나리오 모두 폰트 메트릭과 무관하게 **손으로 검산 가능한 고정값**만
    // 사용한다 — menuName/subinfo/memo 를 비워 TextPainter 확률적 layout(실기기
    // 폰트 의존)을 아예 안 타게 하고, 옵션은 optionRowHeight(고정 상수)만큼만
    // 누적되므로(자동축소 폭 계산과 무관) 개수로 높이가 결정된다.
    //
    // 기대값은 painter 의 gap 상수를 직접 합산해서 계산한다(매직넘버 하드코딩
    // 금지) — 실물 튜닝으로 gap 값이 또 바뀌어도 이 테스트가 검증하는 불변식
    // (섹션 gap 을 빠짐없이 합산한다)은 그대로 유지된다.
    //
    // gapSubInfoToMenuName 은 여기 포함하지 않는다 — subInfo(beanType/
    // temperature/sizeOption) 를 전부 비워 두므로 그 gap 은 조건부로 스킵된다
    // (subInfo 없을 때 QR→메뉴명 간격은 gapQrToSubInfo 하나만 담당하도록
    // 바뀐 설계, 2026-08-21).
    const double emptyBaseline = ContinuousLabelPainter.topMargin +
        ContinuousLabelPainter.headerHeight +
        ContinuousLabelPainter.gapHeaderToDisplayNum +
        ContinuousLabelPainter.gapDisplayNumToQr +
        ContinuousLabelPainter.gapQrToSubInfo +
        ContinuousLabelPainter.gapMenuNameToOptions +
        ContinuousLabelPainter.gapOptionsToDivider +
        ContinuousLabelPainter.gapDividerToMemo;
    const double fiveOptionsBaseline =
        emptyBaseline + 5 * ContinuousLabelPainter.optionRowHeight;

    test('빈 콘텐츠는 그보다 큰 minHeightDots 로 올림 clamp', () {
      final floorSpec = LabelMediaSpec(
        widthDots: 320,
        maxHeightDots: 640, // 상한은 넉넉히 — 이 테스트에서 개입 안 하게.
        minHeightDots: emptyBaseline + 60, // 자연 높이보다 확실히 크게.
        sideMarginDots: 12,
        variableHeight: true,
      );
      final painter =
          ContinuousLabelPainter(spec: floorSpec, menuName: '', options: const []);
      final bottom = measure(painter, floorSpec);
      expect(bottom, emptyBaseline);

      final h = (bottom + ContinuousLabelPainter.bottomMarginDots)
          .clamp(floorSpec.minHeightDots, floorSpec.maxHeightDots);
      expect(h, floorSpec.minHeightDots);
    });

    test('5개 옵션은 그보다 작은 maxHeightDots 로 내림 clamp', () {
      final ceilingSpec = LabelMediaSpec(
        widthDots: 320,
        maxHeightDots: fiveOptionsBaseline - 10, // 자연 높이보다 확실히 작게.
        minHeightDots: 40, // 하한은 넉넉히 낮게 — 이 테스트에서 개입 안 하게.
        sideMarginDots: 12,
        variableHeight: true,
      );
      final painter = ContinuousLabelPainter(
        spec: ceilingSpec,
        menuName: '',
        options: const ['옵션A', '옵션B', '옵션C', '옵션D', '옵션E'],
      );
      final bottom = measure(painter, ceilingSpec);
      expect(bottom, fiveOptionsBaseline);

      final h = (bottom + ContinuousLabelPainter.bottomMarginDots)
          .clamp(ceilingSpec.minHeightDots, ceilingSpec.maxHeightDots);
      expect(h, ceilingSpec.maxHeightDots);
    });
  });
}
