import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:appfit_order_agent/services/label_printer/label_media_spec.dart';
import 'package:appfit_order_agent/utils/label_draw_ops.dart';

/// 라벨 프린터의 **실제 인쇄 가능폭을 실물에서 자로 읽기 위한** 진단 이미지.
///
/// 어떤 painter/spec 에도 묶이지 않는 독립 진단기다 — 물리 용지폭 전체를 캔버스로
/// 잡고 mm 눈금과 폭 전체를 채우는 검정 바를 인쇄해, **어디서 잘리는지** 를 눈으로
/// 확정한다.
///
/// 이게 필요한 이유(2026-08-21, 40mm 실측에서 확인): 프린터 SDK 는 로드된 용지 폭을
/// 보고하지 않는다(`getRecLineWidth()`=576 은 헤드 물리 최대폭이지 용지폭이 아니다 —
/// G30 은 40/58mm 를 가이드 부품으로 고정하는 구조). 게다가 40mm 용지의 실제 인쇄
/// 가능 영역은 물리폭 40mm 가 아니라 **35mm** 였고, 인쇄 시작 위치 자체가 하드웨어에
/// 고정돼 있어 소프트웨어 margin 으로 중앙 정렬이 불가능했다. 이 두 사실은 전부
/// 이 눈금자 출력물을 자로 읽어서만 확인됐다.
///
/// **판독 규율**: 1회 판독을 신뢰하지 않는다. 40mm 때도 3회 재현으로 확정했다.
///
/// ⚠️ Android 전송 경로(`BixolonPosDriver.printBitmap`)의 clamp 상한이 용지폭이면
/// 눈금자 자체가 그 지점에서 잘려 **가짜 실측값**이 나온다. 상한은 반드시 헤드 물리
/// 최대폭(`MAX_PRINT_WIDTH_DOTS`)이어야 한다.
class LabelRulerTestImage {
  const LabelRulerTestImage._();

  /// 203dpi 기준 mm 당 도트 수. 실물 자와 대조하는 이미지이므로 8 로 반올림하지 않고
  /// 실제 값을 쓴다(58mm 기준 오차 0.06mm → 0.5dot 수준이라 실무 차이는 없지만,
  /// 눈금자는 정확한 게 존재 이유다).
  static const double dotsPerMm = 203 / 25.4;

  static const double _canvasHeight = 260;

  // ── 각 섹션의 상단 Y (dots) ─────────────────────────────────────────────
  static const double _clipBarTop = 4;
  static const double _clipBarHeight = 24;
  static const double _rulerBaseline = 40;
  static const double _tickMinor = 10;
  static const double _tickMid = 18;
  static const double _tickMajor = 26;
  static const double _numberTop = 70;
  static const double _numberFontSize = 13;
  static const double _blockStripTop = 96;
  static const double _blockStripHeight = 20;
  static const double _markerTop = 124;
  static const double _markerFontSize = 16;
  static const double _specTop = 152;
  static const double _specBarHeight = 14;
  static const double _textTop = 186;
  static const double _textFontSize = 15;
  static const double _textLineHeight = 20;

  /// [paperWidthMm] 물리 용지폭 전체를 캔버스로 잡은 눈금자 PNG.
  ///
  /// [overlaySpec] 을 주면 그 spec 의 콘텐츠 영역(좌우 여백 제외)을 별도 바로 겹쳐
  /// 그린다 — "계획한 콘텐츠 폭이 실제 인쇄 가능 영역 안에 들어가는가" 를 한 장에서
  /// 같이 판정하기 위함. spec 의 `widthDots` 가 캔버스보다 넓으면 그 초과분도 그대로
  /// 보이므로 잘못된 spec 을 바로 알아챌 수 있다.
  static Future<Uint8List> generate({
    required double paperWidthMm,
    LabelMediaSpec? overlaySpec,
  }) async {
    final double width = (paperWidthMm * dotsPerMm).roundToDouble();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final ops = _RulerDrawOps();

    final black = Paint()
      ..color = Colors.black
      ..isAntiAlias = false;

    // 흰 배경.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width, _canvasHeight),
      Paint()..color = Colors.white,
    );

    // ── ① 잘림 지시 바 — 캔버스 폭 전체를 채우는 solid 검정 ────────────────
    // 가장 중요한 신호. 실물에서 이 바가 몇 mm 에서 끊기는지가 곧 유효 인쇄폭이다.
    canvas.drawRect(
      Rect.fromLTWH(0, _clipBarTop, width, _clipBarHeight),
      black,
    );

    // ── ② mm 눈금 ────────────────────────────────────────────────────────
    final int lastMm = paperWidthMm.floor();
    for (int mm = 0; mm <= lastMm; mm++) {
      final double x = (mm * dotsPerMm).roundToDouble();
      if (x > width - 1) break;
      final double len =
          mm % 10 == 0 ? _tickMajor : (mm % 5 == 0 ? _tickMid : _tickMinor);
      canvas.drawRect(
        Rect.fromLTWH(x, _rulerBaseline, 1, len),
        black,
      );
      if (mm % 5 == 0) {
        // 숫자는 눈금 중앙 정렬. 단 양 끝은 캔버스 밖으로 나가지 않게 클램프한다
        // — 잘리면 판독 자체가 안 된다.
        final double cx = x.clamp(_numberFontSize, width - _numberFontSize);
        ops.drawText(canvas, '$mm', Offset(cx, _numberTop),
            fontSize: _numberFontSize, align: TextAlign.center);
      }
    }

    // ── ③ 5mm 교대 블록 스트립 ────────────────────────────────────────────
    // 바가 어디서 끊겼는지 세어서 읽을 수 있게 하는 보조 신호. 검정 바 하나만으로는
    // 경계 근처에서 "잘린 것"과 "원래 거기까지"가 구분이 안 될 때가 있다.
    for (int mm = 0; mm < lastMm; mm += 10) {
      final double x0 = (mm * dotsPerMm).roundToDouble();
      final double x1 = ((mm + 5) * dotsPerMm).roundToDouble().clamp(0, width);
      if (x0 >= width) break;
      canvas.drawRect(
        Rect.fromLTRB(
            x0, _blockStripTop, x1, _blockStripTop + _blockStripHeight),
        black,
      );
    }

    // ── ④ CL / CR 마커 — 캔버스 양 끝 ────────────────────────────────────
    ops.drawText(canvas, 'CL', const Offset(2, _markerTop),
        fontSize: _markerFontSize, isBold: true);
    ops.drawText(canvas, 'CR', Offset(width - 2, _markerTop),
        fontSize: _markerFontSize, isBold: true, align: TextAlign.right);

    // ── ⑤ spec 콘텐츠 영역 오버레이 ──────────────────────────────────────
    if (overlaySpec != null) {
      final double sl = overlaySpec.sideMarginDots;
      final double sr = overlaySpec.widthDots - overlaySpec.rightMarginDots;
      canvas.drawRect(
          Rect.fromLTRB(sl, _specTop, sr, _specTop + _specBarHeight), black);
      ops.drawText(canvas, 'SL', Offset(sl, _specTop + _specBarHeight + 2),
          fontSize: 12, isBold: true);
      ops.drawText(canvas, 'SR', Offset(sr, _specTop + _specBarHeight + 2),
          fontSize: 12, isBold: true, align: TextAlign.right);
    }

    // ── ⑥ 파라미터 텍스트 ────────────────────────────────────────────────
    final lines = <String>[
      'canvas ${width.toInt()}d = ${paperWidthMm.toStringAsFixed(0)}mm @203dpi',
      if (overlaySpec != null)
        'spec w=${overlaySpec.widthDots.toInt()}d'
            ' L=${overlaySpec.sideMarginDots.toInt()}'
            ' R=${overlaySpec.rightMarginDots.toInt()}'
            ' content=${overlaySpec.contentWidthDots.toInt()}d',
      'read: where does the top bar stop?',
    ];
    for (int i = 0; i < lines.length; i++) {
      ops.drawText(canvas, lines[i], Offset(0, _textTop + i * _textLineHeight),
          fontSize: _textFontSize, maxWidth: width, maxLines: 1);
    }

    final picture = recorder.endRecording();
    final img = await picture.toImage(width.toInt(), _canvasHeight.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw Exception('Failed to generate label ruler image bytes');
    }
    return byteData.buffer.asUint8List();
  }
}

/// [LabelDrawOps] 는 painter 용 mixin 이라 인스턴스 메서드다. 진단기는 painter 가
/// 아니므로 최소 홀더만 둔다.
class _RulerDrawOps with LabelDrawOps {}
