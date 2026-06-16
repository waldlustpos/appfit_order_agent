import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:appfit_order_agent/i18n/strings.g.dart';
import 'package:appfit_order_agent/utils/brand_assets.dart';
import 'package:appfit_order_agent/utils/logger.dart';

class LabelPainter extends CustomPainter {
  final String menuName;
  final List<String> options;
  final String? shopOrderNo;
  final String? orderTime;
  final String? beanType; // 원두 타입 (예: Standard)
  final String? temperature; // 온도 정보 (예: HOT)
  final String? sizeOption; // 사이즈 정보 (예: Regular)
  final String? qrData; // QR 데이터 (Body 영역 좌측에 그려짐)
  final String? memo; // 주문 메모 (note)
  final ui.Image? logoImage; // 로고 이미지
  final int? orderIndex; // 현재 라벨 번호 (예: 1)
  final int? orderTotal; // 전체 라벨 수 (예: 10)

  /// 섹션 타이틀 강제 지정 (null 이면 i18n `t.receipt.section_*` 사용).
  /// 테스트 출력처럼 로캘과 무관하게 영문 'OPTION'/'DETAIL' 을 찍을 때만 사용.
  final String? optionTitleOverride;
  final String? detailTitleOverride;

  LabelPainter({
    required this.menuName,
    required this.options,
    this.shopOrderNo,
    this.orderTime,
    this.beanType,
    this.temperature,
    this.sizeOption,
    this.qrData,
    this.memo,
    this.logoImage,
    this.orderIndex,
    this.orderTotal,
    this.optionTitleOverride,
    this.detailTitleOverride,
  });

  // --- Logo Cache ---
  static ui.Image? _cachedLogo;
  static String? _cachedLogoPath;
  static bool _logoLoadAttempted = false;

  // --- Constants (Layout & Sizes) ---
  static const double width = 490;
  static const double height = 600;
  static const double defaultMargin = 60;
  static const double offsetX = -0; // 우측 쏠림 보정 (음수: 좌측 이동)
  static const double offsetY = -60; // 콘텐츠 전체 상향 (QR 확대로 밀린 하단 디테일 잘림 보정)

  // Font Sizes
  static const double fsHeaderTime = 16;
  static const double fsSubInfo = 22;
  static const double fsMenuName = 28;
  static const double fsOrderNo = 85; //주문번호사이즈 (QR 없을 때)
  static const double fsOrderNoWithQr =
      65; //주문번호사이즈 (QR 동반 시 — 겹침 방지용 조정 노브, QR 확대로 좁아진 가로폭만 보정)
  static const double fsSectionTitle = 22;
  static const double fsOptionItem = 21;
  static const double fsDetailContent = 22;

  // Dimensions & Spacings
  static const double logoWidthDefault = 50;
  static const double qrSizeDefault = 120; // QR 크기 (기본 90 → 120 확대)
  static const double spacingSectionSmall = 15;
  static const double spacingSectionLarge = 30;

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Background
    _drawBackground(canvas, size);

    // 2. Content Translation (Offset)
    canvas.save();
    canvas.translate(offsetX, offsetY);

    // 3. Draw Sections Sequentialy
    double currentY = defaultMargin;

    currentY = _drawHeader(canvas, size, currentY);
    currentY = _drawBody(canvas, size, currentY);
    currentY = _drawOptions(canvas, size, currentY);
    _drawDetail(canvas, size, currentY);

    canvas.restore();
  }

  void _drawBackground(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  double _drawHeader(Canvas canvas, Size size, double startY) {
    final paint = Paint()..color = Colors.black;

    // Order Time
    if (orderTime != null) {
      _drawText(
        canvas,
        orderTime!,
        Offset(defaultMargin, startY + 5),
        fontSize: fsHeaderTime,
        maxLines: 2,
        height: 1.2,
        maxWidth: 120,
      );
    }

    double logoHeight = 0;
    if (logoImage != null) {
      // Logo (centered)
      logoHeight = logoWidthDefault;
      final Rect dstRect = Rect.fromLTWH(size.width / 2 - logoWidthDefault / 2,
          startY, logoWidthDefault, logoHeight);

      canvas.drawImageRect(
        logoImage!,
        Rect.fromLTWH(
            0, 0, logoImage!.width.toDouble(), logoImage!.height.toDouble()),
        dstRect,
        Paint()..filterQuality = FilterQuality.none,
      );

      // Order index (right side)
      if (orderIndex != null && orderTotal != null) {
        _drawText(
          canvas,
          '$orderIndex/$orderTotal',
          Offset(size.width - defaultMargin, startY + 5),
          fontSize: fsSubInfo,
          isBold: true,
          align: TextAlign.right,
        );
      }

      // Header Divider
      double dividerY = startY + logoHeight + 10;
      canvas.drawLine(
        Offset(defaultMargin, dividerY),
        Offset(size.width - defaultMargin, dividerY),
        paint..strokeWidth = 1,
      );
      return dividerY + spacingSectionSmall;
    } else {
      // Default Divider if no logo — same Y as logo branch to keep layout stable
      if (orderIndex != null && orderTotal != null) {
        _drawText(
          canvas,
          '$orderIndex/$orderTotal',
          Offset(size.width - defaultMargin, startY + 5),
          fontSize: fsSubInfo,
          isBold: true,
          align: TextAlign.right,
        );
      }
      double dividerY = startY + logoWidthDefault + 10;
      canvas.drawLine(
        Offset(defaultMargin, dividerY),
        Offset(size.width - defaultMargin, dividerY),
        paint..strokeWidth = 1,
      );
      return dividerY + spacingSectionSmall;
    }
  }

  double _drawBody(Canvas canvas, Size size, double startY) {
    // 헤더 구분선 바로 아래 시작 (간격 = 헤더 return 의 spacingSectionSmall 만).
    // QR 확대(120)로 콘텐츠 높이가 늘어, 위쪽 여백을 줄여 옵션 구분선 침범을 흡수한다.
    double currentY = startY;

    // 1. Sub Info (with Reverse effect)
    _drawSubInfo(canvas, size, currentY);

    // 2. Menu Name
    _drawText(
      canvas,
      menuName,
      Offset(size.width - defaultMargin, currentY + 30),
      fontSize: fsMenuName,
      isBold: true,
      align: TextAlign.right,
      maxWidth: size.width - (defaultMargin * 2),
      maxLines: 1,
    );

    // 3. QR Code & Order Number
    // 메뉴명(currentY+30, fsMenuName) 하단과 QR 상단 사이 여백 확보용 오프셋.
    // 그리기와 아래 return 예약에 동일 값이 쓰여야 어긋나지 않으므로 상수로 묶는다.
    const double qrTopOffset = 75;
    _drawQrAndOrderNo(canvas, size, currentY + qrTopOffset);

    // QR 예약 높이를 qrSizeDefault 로 추적 → 옵션 구분선이 항상 QR 아래 + spacingSectionSmall.
    // (이전엔 고정값 96 이라 QR 확대 시 구분선을 침범했음)
    return currentY + qrTopOffset + qrSizeDefault + spacingSectionSmall;
  }

  void _drawSubInfo(Canvas canvas, Size size, double y) {
    double currentRightX = size.width - defaultMargin;

    final items = <_SubInfoItem>[];
    if (sizeOption != null && sizeOption!.isNotEmpty) {
      items.add(_SubInfoItem(text: sizeOption!, isHighlighted: false));
    }
    if (temperature != null && temperature!.isNotEmpty) {
      items.add(_SubInfoItem(text: temperature!, isHighlighted: false));
    }
    if (beanType != null && beanType!.isNotEmpty) {
      items.add(_SubInfoItem(text: beanType!, isHighlighted: false));
    }

    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      currentRightX = _drawSubInfoPart(
          canvas, item.text, currentRightX, y, item.isHighlighted);

      if (i < items.length - 1) {
        currentRightX = _drawSubInfoSeparator(canvas, currentRightX, y);
      }
    }
  }

  double _drawSubInfoSeparator(Canvas canvas, double rightX, double y) {
    const style = TextStyle(
      color: Colors.black26,
      fontSize: fsSubInfo,
      fontWeight: FontWeight.w400,
      fontFamily: 'Pretendard',
    );
    final painter = TextPainter(
      text: const TextSpan(text: " / ", style: style),
      textDirection: TextDirection.ltr,
    )..layout();

    double drawX = rightX - painter.width;
    painter.paint(canvas, Offset(drawX, y));
    return drawX;
  }

  double _drawSubInfoPart(
      Canvas canvas, String text, double rightX, double y, bool isHighlighted) {
    final style = TextStyle(
      color: isHighlighted ? Colors.white : Colors.black,
      fontSize: fsSubInfo,
      fontWeight: isHighlighted ? FontWeight.w800 : FontWeight.w400,
      fontFamily: 'Pretendard',
    );
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();

    double drawX = rightX - painter.width;

    if (isHighlighted) {
      final rect = Rect.fromLTWH(
          drawX - 6, y - 3, painter.width + 12, painter.height + 6);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4)),
          Paint()..color = Colors.black);
    }

    painter.paint(canvas, Offset(drawX, y));
    return drawX;
  }

  void _drawQrAndOrderNo(Canvas canvas, Size size, double y) {
    if (qrData != null) {
      final qrPainter = QrPainter(
        data: qrData!,
        version: QrVersions.auto,
        errorCorrectionLevel: QrErrorCorrectLevel.L,
      );
      canvas.save();
      canvas.translate(defaultMargin, y);
      qrPainter.paint(canvas, const Size(qrSizeDefault, qrSizeDefault));
      canvas.restore();
    }

    if (shopOrderNo != null) {
      // QR 동반 시: 폰트를 줄여 QR(좌측 90×90)과 겹치지 않게 한다.
      final bool hasQr = qrData != null;
      final double orderNoFont = hasQr ? fsOrderNoWithQr : fsOrderNo;

      final String text = shopOrderNo!;
      final int dashIndex = text.indexOf('-');

      InlineSpan textSpan;
      if (dashIndex != -1) {
        final String mainPart = text.substring(0, dashIndex);
        final String suffixPart = text.substring(dashIndex); // '-' 포함

        textSpan = TextSpan(
          children: [
            TextSpan(
              text: mainPart,
              style: TextStyle(
                fontSize: orderNoFont,
                fontWeight: FontWeight.w600,
                fontFamily: 'Pretendard',
                color: Colors.black,
              ),
            ),
            TextSpan(
              text: suffixPart,
              style: TextStyle(
                fontSize: orderNoFont * 0.85, // 15% 축소
                fontWeight: FontWeight.w600,
                fontFamily: 'Pretendard',
                color: Colors.black,
              ),
            ),
          ],
        );
      } else {
        textSpan = TextSpan(
          text: text,
          style: TextStyle(
            fontSize: orderNoFont,
            fontWeight: FontWeight.w600,
            fontFamily: 'Pretendard',
            color: Colors.black,
          ),
        );
      }

      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.right,
        maxLines: 1,
      );

      textPainter.layout();

      // _drawText 는 top 기준이라, 폰트를 줄이면 QR(90px) 상단에 붙어 보인다.
      // QR 동반 시 텍스트 실제 높이를 측정해 QR 높이 세로 중앙에 맞춘다.
      double drawY = y;
      if (hasQr) {
        drawY = y + (qrSizeDefault - textPainter.height) / 2;
      }

      final double drawX = size.width - defaultMargin - textPainter.width;
      textPainter.paint(canvas, Offset(drawX, drawY));
    }
  }

  double _drawOptions(Canvas canvas, Size size, double startY) {
    final paint = Paint()..color = Colors.black;

    // Divider
    canvas.drawLine(
      Offset(defaultMargin, startY),
      Offset(size.width - defaultMargin, startY),
      paint..strokeWidth = 1,
    );

    // Title (구분선 아래 정렬 보정)
    _drawText(canvas, optionTitleOverride ?? t.receipt.section_option,
        Offset(size.width / 2, startY + spacingSectionSmall),
        fontSize: fsSectionTitle, isBold: true, align: TextAlign.center);

    // List
    double optionStartY =
        startY + spacingSectionSmall + fsSectionTitle + spacingSectionSmall;
    double colWidth = (size.width - (defaultMargin * 2)) / 2;

    for (int i = 0; i < options.length; i++) {
      if (i >= 6) break;
      int row = i ~/ 2;
      int col = i % 2;
      double x = defaultMargin + (col * colWidth) + (col == 1 ? 10 : 0);
      double y = optionStartY + (row * 28);

      _drawText(
        canvas,
        options[i],
        Offset(x, y),
        fontSize: fsOptionItem,
        maxWidth: colWidth - 5,
      );
    }

    return optionStartY + 84 + spacingSectionSmall;
  }

  void _drawDetail(Canvas canvas, Size size, double startY) {
    final paint = Paint()..color = Colors.black;

    // 상단 수평 구분선
    canvas.drawLine(
      Offset(defaultMargin, startY),
      Offset(size.width - defaultMargin, startY),
      paint..strokeWidth = 1,
    );

    // "detail" 타이틀 (가운데 정렬)
    _drawText(
      canvas,
      detailTitleOverride ?? t.receipt.section_detail,
      Offset(size.width / 2, startY + spacingSectionSmall),
      fontSize: fsSectionTitle,
      isBold: true,
      align: TextAlign.center,
    );

    // 메모 텍스트 (전체 폭)
    final double contentY =
        startY + spacingSectionSmall + fsSectionTitle + spacingSectionSmall;
    _drawText(
      canvas,
      memo ?? "",
      Offset(size.width / 2, contentY),
      fontSize: fsDetailContent,
      maxWidth: size.width - (defaultMargin * 2),
      maxLines: 2,
      height: 1.3,
      align: TextAlign.center,
    );
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset offset, {
    double fontSize = 20,
    bool isBold = false,
    bool underline = false,
    double? maxWidth,
    int? maxLines,
    TextAlign align = TextAlign.left,
    double? height,
    Color textColor = Colors.black,
    Color? backgroundColor,
  }) {
    final textStyle = TextStyle(
      color: textColor,
      fontSize: fontSize,
      fontWeight: isBold ? FontWeight.w600 : FontWeight.normal,
      decoration: underline ? TextDecoration.underline : TextDecoration.none,
      fontFamily: 'Pretendard',
      height: height,
    );

    final textSpan = TextSpan(text: text, style: textStyle);
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
      textAlign: align,
      maxLines: maxLines,
      ellipsis: '...',
    );

    textPainter.layout(minWidth: 0, maxWidth: maxWidth ?? double.infinity);

    Offset drawOffset = offset;
    if (align == TextAlign.center) {
      drawOffset = Offset(offset.dx - textPainter.width / 2, offset.dy);
    } else if (align == TextAlign.right) {
      drawOffset = Offset(offset.dx - textPainter.width, offset.dy);
    }

    if (backgroundColor != null) {
      final rect = Rect.fromLTWH(
        drawOffset.dx - 4,
        drawOffset.dy - 2,
        textPainter.width + 8,
        textPainter.height + 4,
      );
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4)),
          Paint()..color = backgroundColor);
    }

    textPainter.paint(canvas, drawOffset);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;

  static Future<ui.Image?> _loadLogoImage(String assetPath) async {
    try {
      final ByteData data = await rootBundle.load(assetPath);
      final Uint8List bytes = data.buffer.asUint8List();
      final Completer<ui.Image> completer = Completer();
      ui.decodeImageFromList(bytes, (img) => completer.complete(img));
      return await completer.future;
    } catch (e) {
      logger.w('[LabelPainter] failed to load logo asset ($assetPath): $e');
      return null;
    }
  }

  static Future<Uint8List> generateLabelImage({
    required String menuName,
    required List<String> options,
    String? shopOrderNo,
    String? orderTime,
    String? beanType,
    String? temperature,
    String? sizeOption,
    String? qrData,
    String? memo,
    int? orderIndex,
    int? orderTotal,
    String? optionTitleOverride,
    String? detailTitleOverride,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final String targetPath = BrandAssets.labelLogoPath;
    if (_cachedLogoPath != targetPath) {
      // 브랜드 전환(또는 첫 로드) — 캐시 무효화 후 재시도.
      _cachedLogo = null;
      _logoLoadAttempted = false;
      _cachedLogoPath = null;
    }
    if (!_logoLoadAttempted) {
      _logoLoadAttempted = true;
      _cachedLogo = await _loadLogoImage(targetPath);
      if (_cachedLogo == null &&
          targetPath != BrandAssets.labelLogoFallbackPath) {
        logger.w(
            '[LabelPainter] primary logo load failed ($targetPath), falling back to tokyoplatz');
        _cachedLogo = await _loadLogoImage(BrandAssets.labelLogoFallbackPath);
      }
      _cachedLogoPath = targetPath;
    }
    final ui.Image? logo = _cachedLogo;

    final painter = LabelPainter(
      menuName: menuName,
      options: options,
      shopOrderNo: shopOrderNo,
      orderTime: orderTime,
      beanType: beanType,
      temperature: temperature,
      sizeOption: sizeOption,
      qrData: qrData, // QR 인쇄는 일단 보류
      memo: memo,
      logoImage: logo,
      orderIndex: orderIndex,
      orderTotal: orderTotal,
      optionTitleOverride: optionTitleOverride,
      detailTitleOverride: detailTitleOverride,
    );

    painter.paint(canvas, const Size(width, height));
    final picture = recorder.endRecording();
    final img = await picture.toImage(width.toInt(), height.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);

    if (byteData == null) {
      throw Exception('Failed to generate image bytes');
    }

    return byteData.buffer.asUint8List();
  }
}

class _SubInfoItem {
  final String text;
  final bool isHighlighted;

  _SubInfoItem({required this.text, required this.isHighlighted});
}
