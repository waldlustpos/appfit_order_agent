import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr/qr.dart';

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

  /// 라벨 레이아웃 버전 (0: V1 기존, 1: V2 QR 우측상단). 설정 KEY_LABEL_LAYOUT_VERSION 연동.
  final int layoutVersion;

  /// QR 오류 정정 레벨 (qr 패키지 `QrErrorCorrectLevel` 상수: L/M/Q/H).
  /// 운영 기본값은 M. 테스트 출력에서 레벨별 인식률 비교용으로 주입한다.
  final int qrErrorCorrectLevel;

  /// QR 박스 한 변 픽셀 크기. 기본 [qrSizeDefault](=120). 테스트 출력에서
  /// 크기별 인식률 비교용으로 주입한다(레이아웃 예약 높이도 이 값에 연동).
  final double qrSize;

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
    this.layoutVersion = 0,
    this.qrErrorCorrectLevel = QrErrorCorrectLevel.M,
    this.qrSize = qrSizeDefault,
  });

  // --- Logo Cache ---
  static ui.Image? _cachedLogo;
  static String? _cachedLogoPath;
  static bool _logoLoadAttempted = false;

  // --- Constants (Layout & Sizes) ---
  static const double width = 490;
  static const double height = 600;
  static const double defaultMargin = 75; // 좌우 여백 (60 → 75, 용지 쏠림 시 가장자리 잘림 방지)
  static const double offsetX = -0; // 우측 쏠림 보정 (음수: 좌측 이동)
  static const double offsetY =
      -60; // 콘텐츠 세로 위치(전체 상향). defaultMargin(=콘텐츠 시작 Y, 75)에 연동.
  //      현재값 기준 상단 ~15px / 하단 ~49px (메모 2줄에도 하단 잘림 없음).
  //      음수 크기를 키우면 콘텐츠가 위로(상단↓·하단↑), 줄이면 반대. 상하 균등은 -43.

  // Font Sizes
  static const double fsHeaderTime = 16;
  static const double fsSubInfo = 22;
  static const double fsMenuName = 28;
  static const double fsOrderNo = 85; //주문번호사이즈 (QR 없을 때)
  static const double fsOrderNoWithQr =
      57; //주문번호사이즈 (V1, QR 동반 시 — 겹침 방지용 조정 노브)
  static const double fsOrderNoWithQrV2 = 40; //주문번호사이즈 (V2, QR 동반 시)
  static const double fsSectionTitle = 22;
  static const double fsOptionItem = 21;
  static const double fsDetailContent = 22;

  // Dimensions & Spacings
  static const double logoWidthDefault = 50;
  static const double qrSizeDefault = 120; // QR 크기 (기본 90 → 120 확대)
  static const double spacingSectionSmall = 15;
  static const double spacingSectionLarge = 30;

  // ── 실주문 QR 정책(레이아웃 버전별) ─────────────────────────────────
  // V2 는 헤더 축소로 확보한 세로 공간에 QR 을 크게 키우고(+50%), 모듈 밀도를
  // 낮춰 인쇄 선명도/스캔율을 높이기 위해 오류정정 레벨을 L 로 둔다.
  // V1 은 종전 그대로(qrSizeDefault, M). 테스트 출력은 이 정책과 무관하게
  // 사용자가 고른 값을 직접 주입한다.
  static const double qrSizeScaleV2 = 1.5; // V2 QR 확대 배율 (+50%)

  /// 레이아웃 버전에 맞는 실주문 QR 박스 크기.
  static double qrSizeForLayout(int layoutVersion) =>
      layoutVersion == 1 ? qrSizeDefault * qrSizeScaleV2 : qrSizeDefault;

  /// 레이아웃 버전에 맞는 실주문 QR 오류정정 레벨.
  static int qrErrorCorrectLevelForLayout(int layoutVersion) =>
      layoutVersion == 1 ? QrErrorCorrectLevel.L : QrErrorCorrectLevel.M;
  // V2 Body 간격 노브 (실측 후 미세조정)
  static const double bodyV2SubInfoGap = 8; // QR 하단 ↔ subinfo
  static const double bodyV2MenuGap = 6; // subinfo ↔ 상품명

  static const double optionRowHeight = 28; // 옵션 한 줄 높이

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
    // 헤더는 V1·V2 동일 (로고 + 우측 순번 + 구분선).
    const double logoW = logoWidthDefault;

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
      logoHeight = logoW;
      final Rect dstRect =
          Rect.fromLTWH(size.width / 2 - logoW / 2, startY, logoW, logoHeight);

      canvas.drawImageRect(
        logoImage!,
        Rect.fromLTWH(
            0, 0, logoImage!.width.toDouble(), logoImage!.height.toDouble()),
        dstRect,
        Paint()..filterQuality = FilterQuality.none,
      );
    }

    // Order index (right side)
    if (orderIndex != null && orderTotal != null) {
      _drawText(
        canvas,
        '$orderIndex/$orderTotal',
        Offset(size.width - defaultMargin, startY + 5),
        fontSize: fsSubInfo,
        isBold: false,
        align: TextAlign.right,
      );
    }

    // Header Divider (로고 유무와 무관하게 동일 Y 로 레이아웃 안정화).
    // V2 는 라인이 인쇄 시 잘려 보여 라인만 제거(여백 위치는 유지). V1 은 종전대로 표시.
    final double dividerY = startY + logoW + 6;
    if (layoutVersion != 1) {
      canvas.drawLine(
        Offset(defaultMargin, dividerY),
        Offset(size.width - defaultMargin, dividerY),
        paint..strokeWidth = 1,
      );
    }
    return dividerY + spacingSectionSmall;
  }

  double _drawBody(Canvas canvas, Size size, double startY) =>
      layoutVersion == 1
          ? _drawBodyV2(canvas, size, startY)
          : _drawBodyV1(canvas, size, startY);

  double _drawBodyV1(Canvas canvas, Size size, double startY) {
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
    const double qrTopOffset = 70;
    _drawQrAndOrderNo(canvas, size, currentY + qrTopOffset);

    // QR 예약 높이를 qrSizeDefault 로 추적 → 옵션 구분선이 항상 QR 아래 + spacingSectionSmall.
    // (이전엔 고정값 96 이라 QR 확대 시 구분선을 침범했음)
    return currentY + qrTopOffset + qrSize + spacingSectionSmall;
  }

  /// V2: QR(우측 상단) + 주문번호(좌측, QR 세로중앙) → subinfo(QR 아래 우측) → 상품명(맨 아래 우측).
  double _drawBodyV2(Canvas canvas, Size size, double startY) {
    // 1. QR(우측 상단) + 주문번호(좌측, QR 세로중앙)
    _drawQrAndOrderNo(canvas, size, startY,
        qrOnLeft: false, centerOrderNoToQr: true);

    // 2. subinfo: QR 바로 아래, 우측정렬. 부재해도 fsSubInfo 만큼 자리를 예약해
    //    상품명 위치를 라벨 간 고정한다(위로 당기지 않음).
    final double subInfoY = startY + qrSize + bodyV2SubInfoGap;
    _drawSubInfo(canvas, size, subInfoY);

    // 3. 상품명: 맨 아래, 우측정렬. V1 메뉴명과 동일 패턴(Y만 하단으로 이동).
    final double menuY = subInfoY + fsSubInfo + bodyV2MenuGap;
    _drawText(
      canvas,
      menuName,
      Offset(size.width - defaultMargin, menuY),
      fontSize: fsMenuName,
      isBold: true,
      align: TextAlign.right,
      maxWidth: size.width - (defaultMargin * 2),
      maxLines: 1,
    );

    // 4. 다음 섹션(옵션 구분선) 시작 Y
    return menuY + fsMenuName + spacingSectionSmall;
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

  /// QR 을 모듈 = 정수 픽셀 + 안티앨리어싱 off + quiet zone 으로 직접 래스터화한다.
  ///
  /// 라벨 PNG(490x600)는 프린터 도트와 1:1 로 매핑되고 thresholding 이진화를
  /// 거친다. `QrPainter` 는 120px 박스에 비정수 모듈 크기(예: 120/21=5.71px)로
  /// 안티앨리어싱 렌더링을 해 모듈 경계에 회색이 생기고, 이를 thresholding 이
  /// 흑백으로 강제하면서 모듈이 뭉개졌다. 여기서는 모듈 크기를 정수 픽셀로
  /// 맞추고 AA 를 끄며 quiet zone(여백)을 둘러 생성 사이트 수준의 선명도를 낸다.
  void _drawCrispQr(Canvas canvas, String data, Offset origin) {
    final qrImage = QrImage(QrCode.fromData(
      data: data,
      errorCorrectLevel: qrErrorCorrectLevel, // 운영 기본 M (인쇄 번짐/긁힘 대비)
    ));
    final int moduleCount = qrImage.moduleCount;

    const int quietModules = 4; // 표준 quiet zone (상하좌우 각 4모듈)

    // 모듈당 정수 픽셀 — 핵심. round 로 데이터 모듈 영역이 박스(120)를 꽉 채우게
    // 한다(레거시 QrPainter 와 동일한 시각 크기). 정수라서 모듈 경계가 칼같이 선명.
    final int modulePx = (qrSize / moduleCount).round().clamp(1, 999);
    final double dataPx = (modulePx * moduleCount).toDouble(); // ≈ qrSize
    final double quietPx = (modulePx * quietModules).toDouble();

    // 데이터 모듈 영역을 박스 중앙에 정렬(정수 픽셀 스냅). quiet zone 은 박스
    // 바깥(주변 흰 여백)으로 확장되므로 레거시와 동일한 모듈 크기를 유지한다.
    final double originX = (origin.dx + (qrSize - dataPx) / 2).roundToDouble();
    final double originY = (origin.dy + (qrSize - dataPx) / 2).roundToDouble();

    final whitePaint = Paint()
      ..color = Colors.white
      ..isAntiAlias = false;
    final blackPaint = Paint()
      ..color = Colors.black
      ..isAntiAlias = false
      ..style = PaintingStyle.fill;

    canvas.save();
    canvas.translate(originX, originY);
    // quiet zone 포함 흰 배경(데이터 영역 + 사방 4모듈). 라벨 배경이 흰색이라도
    // 명시적으로 깔아 스캐너 여백을 보장한다.
    canvas.drawRect(
      Rect.fromLTWH(
          -quietPx, -quietPx, dataPx + quietPx * 2, dataPx + quietPx * 2),
      whitePaint,
    );
    for (int r = 0; r < moduleCount; r++) {
      for (int c = 0; c < moduleCount; c++) {
        if (qrImage.isDark(r, c)) {
          canvas.drawRect(
            Rect.fromLTWH(
              (c * modulePx).toDouble(),
              (r * modulePx).toDouble(),
              modulePx.toDouble(),
              modulePx.toDouble(),
            ),
            blackPaint,
          );
        }
      }
    }
    canvas.restore();
  }

  void _drawQrAndOrderNo(Canvas canvas, Size size, double y,
      {bool qrOnLeft = true, bool centerOrderNoToQr = true}) {
    // qrOnLeft=true → QR 좌측(V1), false → QR 우측(V2). 좌우 여백 대칭 유지.
    final double qrX =
        qrOnLeft ? defaultMargin : (size.width - defaultMargin - qrSize);
    if (qrData != null) {
      _drawCrispQr(canvas, qrData!, Offset(qrX, y));
    }

    if (shopOrderNo != null) {
      // QR 동반 시: 폰트를 줄여 QR 과 겹치지 않게 한다. V2 는 더 작게(40), V1 은 57.
      final bool hasQr = qrData != null;
      final double orderNoFont = hasQr
          ? (layoutVersion == 1 ? fsOrderNoWithQrV2 : fsOrderNoWithQr)
          : fsOrderNo;

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

      // qrOnLeft=true → 주문번호 우측정렬(QR 이 좌측), false → 좌측정렬(QR 이 우측).
      final double drawX = qrOnLeft
          ? (size.width - defaultMargin - textPainter.width)
          : defaultMargin;

      // _drawText 는 top 기준이라, 폰트를 줄이면 QR 상단에 붙어 보인다.
      // QR 동반 + centerOrderNoToQr 시 텍스트 높이를 측정해 QR 세로 중앙에 맞춘다.
      double drawY = y;
      if (hasQr && centerOrderNoToQr) {
        drawY = y + (qrSize - textPainter.height) / 2;
      }

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

    // 'option' 타이틀 — V1 만 표시, V2 는 제거 후 리스트를 위로 당김.
    final double optionStartY;
    if (layoutVersion == 1) {
      optionStartY = startY + spacingSectionSmall;
    } else {
      _drawText(canvas, optionTitleOverride ?? t.receipt.section_option,
          Offset(size.width / 2, startY + spacingSectionSmall),
          fontSize: fsSectionTitle, isBold: false, align: TextAlign.center);
      optionStartY =
          startY + spacingSectionSmall + fsSectionTitle + spacingSectionSmall;
    }
    double colWidth = (size.width - (defaultMargin * 2)) / 2;

    const int maxOptionsShown = 4; // 옵션은 최대 4개까지만 표시
    final int shown =
        options.length > maxOptionsShown ? maxOptionsShown : options.length;
    for (int i = 0; i < shown; i++) {
      int row = i ~/ 2;
      int col = i % 2;
      double x = defaultMargin + (col * colWidth) + (col == 1 ? 10 : 0);
      double y = optionStartY + (row * optionRowHeight);

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

    // 'detail' 타이틀 — V1 만 표시, V2 는 제거 후 메모를 위로 당김.
    final double contentY;
    if (layoutVersion == 1) {
      contentY = startY + spacingSectionSmall;
    } else {
      _drawText(
        canvas,
        detailTitleOverride ?? t.receipt.section_detail,
        Offset(size.width / 2, startY + spacingSectionSmall),
        fontSize: fsSectionTitle,
        isBold: false,
        align: TextAlign.center,
      );
      contentY =
          startY + spacingSectionSmall + fsSectionTitle + spacingSectionSmall;
    }
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
    int layoutVersion = 0,
    int qrErrorCorrectLevel = QrErrorCorrectLevel.M,
    double qrSize = qrSizeDefault,
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
      layoutVersion: layoutVersion,
      qrErrorCorrectLevel: qrErrorCorrectLevel,
      qrSize: qrSize,
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
