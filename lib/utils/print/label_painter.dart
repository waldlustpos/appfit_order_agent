import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

class LabelPainter extends CustomPainter {
  final String menuName;
  final List<String> options;
  final String? shopOrderNo;
  final String? orderTime;
  final String? beanType; // 원두 타입 (예: Standard)
  final String? temperature; // 온도 정보 (예: HOT)
  final String? sizeOption; // 사이즈 정보 (예: Regular)
  final String? qrData; // QR 데이터
  final String? memo; // 주문 메모 (note)
  final ui.Image? logoImage; // 로고 이미지
  final int? orderIndex; // 현재 라벨 번호 (예: 1)
  final int? orderTotal; // 전체 라벨 수 (예: 10)

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
  });

  // --- Logo Cache ---
  static ui.Image? _cachedLogo;
  static bool _logoLoadAttempted = false;

  // --- Constants (Layout & Sizes) ---
  static const double width = 480;
  static const double height = 600;
  static const double defaultMargin = 55;
  static const double offsetX = 0; // 우측 쏠림 보정 (음수: 좌측 이동) - 기존 -45에서 조정
  static const double offsetY = -30;

  // Font Sizes
  static const double fsHeaderTime = 16;
  static const double fsSubInfo = 22;
  static const double fsMenuName = 28;
  static const double fsOrderNo = 85;
  static const double fsSectionTitle = 22;
  static const double fsOptionItem = 21;
  static const double fsDetailContent = 22;

  // Dimensions & Spacings
  static const double logoWidthDefault = 50;
  static const double qrSizeDefault = 90;
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
      final Rect dstRect = Rect.fromLTWH(
          size.width / 2 - logoWidthDefault / 2,
          startY,
          logoWidthDefault,
          logoHeight);

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
    double currentY = startY + (spacingSectionLarge - spacingSectionSmall);

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
    _drawQrAndOrderNo(canvas, size, currentY + 65);

    return currentY + 65 + 96 + spacingSectionSmall;
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
      _drawText(
        canvas,
        "#$shopOrderNo",
        Offset(size.width - defaultMargin, y),
        fontSize: fsOrderNo,
        isBold: true,
        align: TextAlign.right,
      );
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
    _drawText(
        canvas, "option", Offset(size.width / 2, startY + spacingSectionSmall),
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
        "+ ${options[i]}",
        Offset(x, y),
        fontSize: fsOptionItem,
        maxWidth: colWidth - 5,
      );
    }

    return optionStartY + 84 + spacingSectionSmall;
  }

  void _drawDetail(Canvas canvas, Size size, double startY) {
    final paint = Paint()..color = Colors.black;

    // Divider
    canvas.drawLine(
      Offset(defaultMargin, startY),
      Offset(size.width - defaultMargin, startY),
      paint..strokeWidth = 1,
    );

    // Title (구분선 아래 정렬 보정)
    _drawText(
        canvas, "detail", Offset(size.width / 2, startY + spacingSectionSmall),
        fontSize: fsSectionTitle, isBold: true, align: TextAlign.center);

    String detailText = memo ?? "";
    _drawText(
      canvas,
      detailText,
      Offset(defaultMargin,
          startY + spacingSectionSmall + fsSectionTitle + spacingSectionSmall),
      fontSize: fsDetailContent,
      maxWidth: size.width - (defaultMargin * 2),
      maxLines: 2,
      height: 1.3,
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
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    if (!_logoLoadAttempted) {
      _logoLoadAttempted = true;
      try {
        const String assetPath = 'assets/images/label_logo.bmp';
        final ByteData data = await rootBundle.load(assetPath);
        final Uint8List bytes = data.buffer.asUint8List();
        final Completer<ui.Image> completer = Completer();
        ui.decodeImageFromList(bytes, (img) => completer.complete(img));
        _cachedLogo = await completer.future;
      } catch (e) {
        debugPrint('Failed to load logo image: $e');
      }
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
      qrData: qrData,
      memo: memo,
      logoImage: logo,
      orderIndex: orderIndex,
      orderTotal: orderTotal,
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
