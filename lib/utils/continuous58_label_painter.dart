import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:qr/qr.dart';

import 'package:appfit_order_agent/services/label_printer/label_media_spec.dart';
import 'package:appfit_order_agent/utils/brand_assets.dart';
import 'package:appfit_order_agent/utils/label_draw_ops.dart';

/// BIXOLON G30 연속 용지(58mm, 세로 가변) 전용 painter.
///
/// [ContinuousLabelPainter](40mm)와 **별개 레이아웃**이다. 40mm 의 확대판이 아니다 —
/// 목업 기준 요소 배치가 다르다:
///
/// | | 40mm | 58mm(이 파일) |
/// |---|---|---|
/// | 헤더 | 로고 좌 / 날짜 1줄 중앙 / n·N 우 | 날짜 **2줄 좌** / 로고 중앙 / n·N 우 |
/// | 표시번호·QR | 둘 다 중앙, 세로로 쌓임 | 번호 좌 + QR 우, **한 행에 나란히** |
/// | 서브정보 | 평문 1줄 | **콘텐츠 폭 전체 검정 바 + 흰 굵은 글씨** |
/// | 옵션 | 1열 | **2열** |
///
/// 세로 가변 계약은 40mm 과 동일하다 — [paintAndMeasure] 가 콘텐츠 하단 Y 를
/// 반환하고 [generateContinuous58LabelImage] 가 그 높이만 래스터화한다.
///
/// **폰트 절대 크기는 목업 비율이 아니라 40mm 검증값에 맞춘다.** 목업 비율을 그대로
/// dot 으로 환산하면 메뉴명이 19dot 수준으로 40mm(26dot)보다 작아진다 — 넓은 용지가
/// 오히려 덜 보이는 역전이라 채택하지 않았다. 목업은 배치·비례의 기준으로만 쓴다.
class Continuous58LabelPainter extends CustomPainter with LabelDrawOps {
  final LabelMediaSpec spec;
  final String menuName;
  final List<String> options;
  final String? shopOrderNo;

  /// 헤더 좌측에 찍는 날짜 텍스트. `'M/d\nHH:mm:ss'` **2줄** 포맷 — 목업 기준
  /// (40mm 의 1줄 포맷과 다르다).
  final String? headerDateText;

  final String? beanType;
  final String? temperature;
  final String? sizeOption;
  final String? memo;
  final String? qrData;
  final ui.Image? logoImage;
  final int? orderIndex;
  final int? orderTotal;
  final int qrErrorCorrectLevel;

  const Continuous58LabelPainter({
    required this.spec,
    required this.menuName,
    required this.options,
    this.shopOrderNo,
    this.headerDateText,
    this.beanType,
    this.temperature,
    this.sizeOption,
    this.memo,
    this.qrData,
    this.logoImage,
    this.orderIndex,
    this.orderTotal,
    this.qrErrorCorrectLevel = QrErrorCorrectLevel.M,
  });

  // ── 레이아웃 상수 ────────────────────────────────────────────────────────
  // 폭 관련 값은 전부 spec.contentWidthDots 를 참조한다 — continuous58 의 widthDots
  // 가 실측으로 확정되면 자동 반응한다(40mm painter 와 같은 설계).

  static const double topMargin = 4;
  static const double bottomMarginDots = 12;

  /// 섹션 사이 공통 간격.
  static const double gapUnit = 16;

  static const double headerHeight = 46;
  static const double headerLogoSize = 40;

  /// 날짜 2줄(17 x 1.2 x 2 = 40.8)이 [headerHeight] 안에 들어가는 크기.
  static const double headerFontSize = 17;
  static const int headerDateMaxLines = 2;

  static const double displayNumFontSize = 72;
  static const double displayNumFontSizeMin = 44;

  static const double qrSize = 140;

  /// 표시번호와 QR 사이 간격. QR quiet zone 이 번호를 침범하는 문제는 간격이 아니라
  /// `drawCrispQr` 의 `clampQuietLeftTo` 로 막는다 — 간격으로 막으려면 32dot 이상이
  /// 필요해 가로 폭이 아깝고, modulePx 에 따라 흔들리는 취약한 불변식이 된다.
  static const double gapNumToQr = 16;

  static const double subInfoBarHeight = 42;

  /// 검정 반전 바의 흰 글씨. 반전 인쇄는 흰 획이 두 번 얇아진다 — threshold 210
  /// 이진화가 안티앨리어싱 경계를 검정으로 밀고(①), 감열지에서 주변 검정이 번져
  /// 들어온다(②). 그래서 다른 본문 요소(옵션 20 / 메모 22)보다 크게 잡는다.
  ///
  /// 실기기 1차 출력에서 "가독성 떨어짐" 피드백을 받아 20 → 24 로 올리고
  /// [subInfoStrokeWidth] 를 함께 넣었다(2026-08-26).
  static const double subInfoFontSize = 24;

  /// 의사 볼드 두께. Pretendard 는 **Bold(700)가 번들에 없어**(pubspec 이 Medium/
  /// Regular/SemiBold 만 선언 — Bold 추가는 APK +1.6MB) `FontWeight.w700` 을 줘도
  /// w600 으로 폴백한다. 자산을 늘리지 않고 굵기를 얻는 유일한 수단이 stroke 다.
  ///
  /// 값 근거(threshold 210 이진화 시뮬레이션, fs24 기준): 0.8 은 '블'/'없음'의
  /// counter 가 전부 살아 있고, **1.2 는 메워져 덩어리가 됐다.** 실제 감열 번짐은
  /// 시뮬레이션보다 획을 더 얇게 만들므로 안전한 0.8 보다 조금 위인 1.0 을 쓴다.
  /// **더 굵게 필요하면 이 값이 아니라 [subInfoFontSize] 를 올릴 것** — 자세한
  /// 이유는 [LabelDrawOps.drawText] 의 strokeWidth 주석 참조.
  static const double subInfoStrokeWidth = 1.0;

  static const double subInfoBarPadX = 8;

  static const double menuNameFontSize = 26;
  static const double menuNameLineHeight = 1.25;
  static const int menuNameMaxLines = 2;

  static const double optionFontSize = 20;
  static const double optionRowHeight = 28;
  static const double optionColGutter = 16;

  /// 이하면 1열(콘텐츠 폭 전체). 초과하면 2열.
  static const int optionSingleColumnMax = 3;
  static const int optionMaxRows = 4;
  static const int optionMaxShown = optionMaxRows * 2;

  static const double memoFontSize = 22;
  static const double memoLineHeight = 1.3;
  static const int memoMaxLines = 3;

  @override
  void paint(Canvas canvas, Size size) {
    paintAndMeasure(canvas, size);
  }

  /// 실제 렌더 + 콘텐츠 하단 Y 를 반환한다.
  ///
  /// **간격 규칙**: 각 섹션은 "그려졌을 때만" 자기 높이와 뒤따르는 간격을 더한다 —
  /// 빈 섹션은 흔적 없이 접힌다(연속 용지라 안 쓰는 세로는 그대로 종이 낭비다).
  /// 구분선만 예외로 항상 그린다(메모가 없어도 목업이 유지한다).
  double paintAndMeasure(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.white,
    );

    final double left = spec.sideMarginDots;
    final double contentWidth = spec.contentWidthDots;
    final double right = left + contentWidth;
    double y = topMargin;

    y = _drawHeader(canvas, left, contentWidth, y);
    y = _drawNumberAndQr(canvas, left, contentWidth, y);
    y = _drawSubInfoBar(canvas, left, contentWidth, y);
    y = _drawMenuName(canvas, left, contentWidth, y);
    y = _drawOptions(canvas, left, contentWidth, y);

    // ── 구분선 (항상) ────────────────────────────────────────────────────
    canvas.drawLine(
      Offset(left, y),
      Offset(right, y),
      Paint()
        ..color = Colors.black
        ..strokeWidth = 1,
    );
    y += 1 + gapUnit;

    y = _drawMemo(canvas, left, contentWidth, y);
    return y;
  }

  /// 날짜 2줄(좌) / 로고(중앙) / n·N(우) — 한 행.
  double _drawHeader(
      Canvas canvas, double left, double contentWidth, double y) {
    // 날짜는 로고와 겹치지 않도록 폭을 제한한다(로고는 콘텐츠 영역 중앙).
    final double sideSlot = (contentWidth - headerLogoSize) / 2 - 8;

    if (headerDateText != null && headerDateText!.isNotEmpty) {
      final probe = _probe(headerDateText!,
          fontSize: headerFontSize,
          maxWidth: sideSlot,
          maxLines: headerDateMaxLines);
      drawText(
        canvas,
        headerDateText!,
        Offset(left, y + (headerHeight - probe.height) / 2),
        fontSize: headerFontSize,
        maxWidth: sideSlot,
        maxLines: headerDateMaxLines,
      );
    }

    if (logoImage != null) {
      final double logoY = y + (headerHeight - headerLogoSize) / 2;
      final double logoX = left + (contentWidth - headerLogoSize) / 2;
      canvas.drawImageRect(
        logoImage!,
        Rect.fromLTWH(
            0, 0, logoImage!.width.toDouble(), logoImage!.height.toDouble()),
        Rect.fromLTWH(logoX, logoY, headerLogoSize, headerLogoSize),
        Paint()..filterQuality = FilterQuality.none,
      );
    }

    if (orderIndex != null && orderTotal != null) {
      drawText(
        canvas,
        '$orderIndex/$orderTotal',
        Offset(left + contentWidth, y + (headerHeight - headerFontSize) / 2),
        fontSize: headerFontSize,
        align: TextAlign.right,
      );
    }

    return y + headerHeight + gapUnit;
  }

  /// 표시번호(좌, 초대형) + QR(우) — 한 행. 목업대로 **상단 정렬**이다(번호를 QR
  /// 높이 중앙에 맞추지 않는다).
  double _drawNumberAndQr(
      Canvas canvas, double left, double contentWidth, double y) {
    final bool hasQr = qrData != null && qrData!.isNotEmpty;
    final bool hasNum = shopOrderNo != null && shopOrderNo!.isNotEmpty;
    if (!hasQr && !hasNum) return y;

    double rowHeight = 0;

    if (hasNum) {
      final double numWidth =
          hasQr ? contentWidth - qrSize - gapNumToQr : contentWidth;
      // ★ baseFontSize 를 높이로 쓰면 안 된다 — Pretendard 의 실제 line-height 는
      // fontSize 보다 커서(자동축소로 fs < base 여도 마찬가지) 예약 공간이 실제
      // 렌더 높이보다 작아진다. TextPainter 로 실측한다(40mm painter 와 동일 함정).
      final double fs = LabelDrawOps.fitFontSize(
        shopOrderNo!,
        maxWidth: numWidth,
        baseFontSize: displayNumFontSize,
        minFontSize: displayNumFontSizeMin,
        isBold: true,
      );
      final probe =
          _probe(shopOrderNo!, fontSize: fs, maxWidth: numWidth, isBold: true);
      drawText(
        canvas,
        shopOrderNo!,
        Offset(left, y),
        fontSize: fs,
        isBold: true,
        maxWidth: numWidth,
        maxLines: 1,
      );
      rowHeight = math.max(rowHeight, probe.height);
    }

    if (hasQr) {
      final double qrX = left + contentWidth - qrSize;
      // 네 방향 clamp 전부 필수 — quiet zone(모듈 4개 폭 흰 배경)은 QR 박스 밖으로
      // 30dot 넘게 확장되므로, 좌측 clamp 가 없으면 같은 행의 표시번호 끝을 흰색으로
      // 지운다(40mm 에서 세로로 겪었던 겹침 사고의 가로 버전).
      drawCrispQr(
        canvas,
        qrData!,
        Offset(qrX, y),
        qrSize: qrSize,
        qrErrorCorrectLevel: qrErrorCorrectLevel,
        clampQuietTopTo: y,
        clampQuietBottomTo: y + qrSize,
        clampQuietLeftTo: qrX,
        clampQuietRightTo: qrX + qrSize,
      );
      rowHeight = math.max(rowHeight, qrSize);
    }

    return y + rowHeight + gapUnit;
  }

  /// 서브정보 — 콘텐츠 폭 전체 검정 바 + 흰 굵은 글씨.
  ///
  /// [LabelDrawOps.drawText] 의 `backgroundColor` 는 **텍스트 폭에 맞춘 라운드
  /// 박스**라 목업(폭 전체·직각)과 다르다 — 여기서 직접 그린다.
  ///
  /// 조합 순서는 목업대로 **온도 / 사이즈 / 원두**. 40mm 은 원두/온도/사이즈 순이지만
  /// 별개 레이아웃이라 맞추지 않는다.
  double _drawSubInfoBar(
      Canvas canvas, double left, double contentWidth, double y) {
    final text = [temperature, sizeOption, beanType]
        .where((s) => s != null && s.isNotEmpty)
        .join(' / ');
    if (text.isEmpty) return y;

    canvas.drawRect(
      Rect.fromLTWH(left, y, contentWidth, subInfoBarHeight),
      Paint()..color = Colors.black,
    );

    final double textMaxWidth = contentWidth - subInfoBarPadX * 2;
    final probe = _probe(text,
        fontSize: subInfoFontSize, maxWidth: textMaxWidth, isBold: true);
    drawText(
      canvas,
      text,
      Offset(left + subInfoBarPadX, y + (subInfoBarHeight - probe.height) / 2),
      fontSize: subInfoFontSize,
      isBold: true,
      textColor: Colors.white,
      strokeWidth: subInfoStrokeWidth,
      maxWidth: textMaxWidth,
      maxLines: 1,
    );

    return y + subInfoBarHeight + gapUnit;
  }

  double _drawMenuName(
      Canvas canvas, double left, double contentWidth, double y) {
    if (menuName.isEmpty) return y;

    // 40mm 과 동일 — 축소 없이 ellipsis 로 대응한다(메뉴명은 크기가 곧 가독성이라
    // 줄이는 것보다 자르는 편이 낫다는 판단).
    final probe = _probe(
      menuName,
      fontSize: menuNameFontSize,
      maxWidth: contentWidth,
      isBold: true,
      maxLines: menuNameMaxLines,
      lineHeight: menuNameLineHeight,
    );
    drawText(
      canvas,
      menuName,
      Offset(left, y),
      fontSize: menuNameFontSize,
      isBold: true,
      maxWidth: contentWidth,
      maxLines: menuNameMaxLines,
      height: menuNameLineHeight,
    );
    return y + probe.height + gapUnit;
  }

  /// 옵션 2열(개수가 적으면 1열). 기하는 [LabelDrawOps.optionCells] 공유.
  double _drawOptions(
      Canvas canvas, double left, double contentWidth, double y) {
    if (options.isEmpty) return y;

    final cells =
        optionCellsFor(options.length, contentWidth: contentWidth, left: left);
    final bool overflowed = options.length > optionMaxShown;

    for (int i = 0; i < cells.length; i++) {
      final cell = cells[i];
      // 초과분은 마지막 셀을 '+N' 으로 대체 — 조용히 사라지지 않게 한다.
      final bool isMoreCell = overflowed && i == cells.length - 1;
      final String text =
          isMoreCell ? '+${options.length - (optionMaxShown - 1)}' : options[i];
      drawAutoFitText(
        canvas,
        text,
        Offset(cell.x, y + cell.y),
        baseFontSize: optionFontSize,
        minFontSize: optionFontSize - 3,
        maxWidth: cell.maxWidth,
      );
    }

    final double lastY = cells.last.y;
    return y + lastY + optionRowHeight + gapUnit;
  }

  double _drawMemo(Canvas canvas, double left, double contentWidth, double y) {
    if (memo == null || memo!.isEmpty) return y;

    final probe = _probe(
      memo!,
      fontSize: memoFontSize,
      maxWidth: contentWidth,
      maxLines: memoMaxLines,
      lineHeight: memoLineHeight,
    );
    drawText(
      canvas,
      memo!,
      Offset(left, y),
      fontSize: memoFontSize,
      maxWidth: contentWidth,
      maxLines: memoMaxLines,
      height: memoLineHeight,
    );
    return y + probe.height;
  }

  /// 이 레이아웃의 옵션 셀 기하 (렌더 없는 순수 함수 — 테스트 대상).
  @visibleForTesting
  static List<LabelOptionCell> optionCellsFor(
    int count, {
    required double contentWidth,
    double left = 0,
  }) =>
      LabelDrawOps.optionCells(
        count: count,
        left: left,
        contentWidth: contentWidth,
        rowHeight: optionRowHeight,
        gutter: optionColGutter,
        singleColumnMax: optionSingleColumnMax,
        maxShown: optionMaxShown,
      );

  TextPainter _probe(
    String text, {
    required double fontSize,
    required double maxWidth,
    bool isBold = false,
    int? maxLines,
    double? lineHeight,
  }) =>
      TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: isBold ? FontWeight.w600 : FontWeight.normal,
            fontFamily: 'Pretendard',
            height: lineHeight,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: maxLines,
        ellipsis: '...',
      )..layout(maxWidth: maxWidth);

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;

  /// 주문 시각을 헤더용 **2줄** 포맷(`'M/d\nHH:mm:ss'`)으로.
  ///
  /// [orderedAt] 이 없으면(예: `LabelPrintData.testSample`) 기존 2줄 포맷
  /// `orderTime`("MM/dd\nHH:mm:ss")을 **그대로** 쓴다 — 58mm 헤더도 2줄이라
  /// 40mm 처럼 개행을 공백으로 치환할 필요가 없다.
  static String? formatHeaderDate(
      DateTime? orderedAt, String? legacyOrderTime) {
    if (orderedAt != null) {
      return DateFormat('M/d\nHH:mm:ss').format(orderedAt);
    }
    return legacyOrderTime;
  }

  static Future<Uint8List> generateContinuous58LabelImage({
    required LabelMediaSpec spec,
    required String menuName,
    required List<String> options,
    String? shopOrderNo,
    DateTime? orderedAt,
    String? legacyOrderTime,
    String? beanType,
    String? temperature,
    String? sizeOption,
    String? memo,
    String? qrData,
    int? orderIndex,
    int? orderTotal,
    int qrErrorCorrectLevel = QrErrorCorrectLevel.M,
  }) async {
    assert(spec.variableHeight,
        'generateContinuous58LabelImage 는 가변 높이 spec 전용 — gap490x600 은 LabelPainter.generateLabelImage 를 쓸 것');

    final ui.Image? logo = await LabelDrawOps.resolveLogo(
        BrandAssets.labelLogoPath, BrandAssets.labelLogoFallbackPath);

    final painter = Continuous58LabelPainter(
      spec: spec,
      menuName: menuName,
      options: options,
      shopOrderNo: shopOrderNo,
      headerDateText: formatHeaderDate(orderedAt, legacyOrderTime),
      beanType: beanType,
      temperature: temperature,
      sizeOption: sizeOption,
      memo: memo,
      qrData: qrData,
      logoImage: logo,
      orderIndex: orderIndex,
      orderTotal: orderTotal,
      qrErrorCorrectLevel: qrErrorCorrectLevel,
    );

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final double bottom = painter.paintAndMeasure(
        canvas, Size(spec.widthDots, spec.maxHeightDots));
    final picture = recorder.endRecording();

    final int h = (bottom + bottomMarginDots)
        .clamp(spec.minHeightDots, spec.maxHeightDots)
        .ceil();
    // Picture.toImage(w, h) 는 원점 기준 영역만 래스터화 — cap 높이로 그린 뒤 실제
    // 필요한 높이만 잘라내면 되므로 2-pass 가 불필요하다.
    final img = await picture.toImage(spec.widthDots.toInt(), h);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);

    if (byteData == null) {
      throw Exception('Failed to generate continuous58 label image bytes');
    }
    return byteData.buffer.asUint8List();
  }
}
