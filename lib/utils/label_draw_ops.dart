import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr/qr.dart';

import 'package:appfit_order_agent/utils/logger.dart';

/// 라벨 painter 공용 저수준 draw 프리미티브.
///
/// [LabelPainter](490x600 갭 라벨)와 G30 연속용지 painter 가 공유한다. 여기 담긴
/// 메서드들은 레이아웃(요소 배치·간격)에 대해 아무것도 모른다 — 텍스트/QR/로고를
/// "어디에 얼마나 크게" 그릴지는 항상 호출부가 좌표·크기를 넘긴다.
///
/// Dart 는 프라이버시가 클래스가 아니라 **라이브러리(파일) 단위**라, `LabelPainter`
/// 에 있던 `_drawText` 등 언더스코어 메서드를 이 파일로 옮기면 원래 이름 그대로는
/// 다른 파일에서 호출할 수 없다 — 그래서 언더스코어를 떼어 공개 멤버로 옮겼다.
/// 로직은 그대로다(순수 이동 + 리네임).
mixin LabelDrawOps {
  /// 자동 축소 시 원래 폰트 슬롯의 세로 중앙으로 내리는 계수 (line-height 1.2 / 2).
  static const double fitVerticalCenterFactor = 0.6;

  void drawText(
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

  /// [maxWidth] × [maxLines] 안에 들어가는 최대 폰트 크기를 찾는다.
  ///
  /// **기본 크기를 먼저 쓰고, 줄 수를 다 소진한 뒤에야 축소한다.**
  ///
  /// base 에서 1px 씩 내리는 단순 하향 스캔이다. 탐색 범위가 좁아(보통
  /// baseFontSize - minFontSize 가 한 자릿수) 최악의 경우도 layout 수 회 수준이며,
  /// 같은 라벨의 QR 래스터화·PNG 인코딩(수십 ms)에 비하면 무시할 수준이다.
  /// 비례 추정을 쓰지 않는 이유는 [maxLines] > 1 일 때 줄바꿈 낭비 때문에
  /// 추정이 빗나가기 때문 — 정확성을 택했다.
  ///
  /// flutter test 에서는 Pretendard 가 로드되지 않아 반환값의 절대치가 폰트에
  /// 의존한다. 테스트는 `[minFontSize, baseFontSize]` 범위·단조성만 검증할 것.
  static double fitFontSize(
    String text, {
    required double maxWidth,
    required double baseFontSize,
    required double minFontSize,
    bool isBold = false,
    int maxLines = 1,
    double? lineHeight,
  }) {
    if (text.isEmpty || maxWidth <= 0) return baseFontSize;

    bool fits(double fs) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontSize: fs,
            fontWeight: isBold ? FontWeight.w600 : FontWeight.normal,
            fontFamily: 'Pretendard',
            height: lineHeight,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: maxLines,
      )..layout(maxWidth: maxWidth);
      // ellipsis 를 주지 않았으므로 초과 시 didExceedMaxLines 가 선다.
      return !tp.didExceedMaxLines;
    }

    for (double fs = baseFontSize; fs > minFontSize; fs -= 1) {
      if (fits(fs)) return fs;
    }
    return minFontSize;
  }

  /// 폰트 자동 축소 후 그린다. 오버플로 wrap 이 구조적으로 불가능하도록
  /// [maxLines] 를 항상 전달한다(하한까지 줄여도 넘치면 ellipsis).
  ///
  /// [slotHeight] 를 주면 **슬롯 하단 정렬**(2줄 슬롯에 1줄짜리가 오면 남는 한 줄이
  /// 위쪽으로 몰린다). 주지 않으면 축소분의 절반만큼 내려 원래 폰트 슬롯의 세로
  /// 중앙에 맞춘다([drawText] 가 dy 를 텍스트 박스 top 으로 쓰기 때문에 필요한 보정).
  ///
  /// 실제로 텍스트를 그린 상단 Y 를 반환한다 — 호출부가 그 위에 다른 요소를
  /// 붙일 수 있도록.
  double drawAutoFitText(
    Canvas canvas,
    String text,
    Offset offset, {
    required double baseFontSize,
    required double minFontSize,
    required double maxWidth,
    bool isBold = false,
    TextAlign align = TextAlign.left,
    int maxLines = 1,
    double? lineHeight,
    double? slotHeight,
  }) {
    final double fs = fitFontSize(
      text,
      maxWidth: maxWidth,
      baseFontSize: baseFontSize,
      minFontSize: minFontSize,
      isBold: isBold,
      maxLines: maxLines,
      lineHeight: lineHeight,
    );

    final double dy;
    if (slotHeight != null) {
      // 실제 렌더 높이를 재서 슬롯 중앙에 놓는다. lineHeight 를 명시한 경우
      // 높이가 fontSize × lineHeight × 줄수로 결정돼 폰트 메트릭에 흔들리지 않는다.
      final probe = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontSize: fs,
            fontWeight: isBold ? FontWeight.w600 : FontWeight.normal,
            fontFamily: 'Pretendard',
            height: lineHeight,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: align,
        maxLines: maxLines,
        ellipsis: '...',
      )..layout(maxWidth: maxWidth);
      dy = offset.dy + (slotHeight - probe.height);
    } else {
      dy = offset.dy + (baseFontSize - fs) * fitVerticalCenterFactor;
    }

    drawText(
      canvas,
      text,
      Offset(offset.dx, dy),
      fontSize: fs,
      isBold: isBold,
      align: align,
      maxWidth: maxWidth,
      maxLines: maxLines,
      height: lineHeight,
    );
    return dy;
  }

  /// QR 을 모듈 = 정수 픽셀 + 안티앨리어싱 off + quiet zone 으로 직접 래스터화한다.
  ///
  /// 라벨 PNG 는 프린터 도트와 1:1 로 매핑되고 thresholding 이진화를 거친다.
  /// `QrPainter` 는 비정수 모듈 크기로 안티앨리어싱 렌더링을 해 모듈 경계에
  /// 회색이 생기고, 이를 thresholding 이 흑백으로 강제하면서 모듈이 뭉개졌다.
  /// 여기서는 모듈 크기를 정수 픽셀로 맞추고 AA 를 끄며 quiet zone(여백)을 둘러
  /// 생성 사이트 수준의 선명도를 낸다.
  ///
  /// [clampQuietTopTo] 를 주면 quiet zone 상단이 그 Y 아래로만 확장된다 — 바로
  /// 위에 이미 그려진 요소(헤더 등)를 흰 배경으로 덮어쓰지 않기 위함. 생략하면
  /// clamp 없이 [origin.dy] - quietPx 까지 그대로 확장한다.
  ///
  /// [clampQuietBottomTo] 는 대칭으로 하단을 clamp한다 — quiet zone 이 기본
  /// 동작대로 [origin.dy] + [qrSize] 아래로 확장되면, 호출부가 잡아둔 다음
  /// 요소와의 간격(gap)보다 넓을 때 바로 아래 요소의 상단을 흰 배경으로
  /// 덮어써 버린다(표시번호/QR 겹침과 같은 유형의 버그).
  void drawCrispQr(
    Canvas canvas,
    String data,
    Offset origin, {
    required double qrSize,
    required int qrErrorCorrectLevel,
    double? clampQuietTopTo,
    double? clampQuietBottomTo,
  }) {
    final qrImage = QrImage(QrCode.fromData(
      data: data,
      errorCorrectLevel: qrErrorCorrectLevel, // 운영 기본 M (인쇄 번짐/긁힘 대비)
    ));
    final int moduleCount = qrImage.moduleCount;

    const int quietModules = 4; // 표준 quiet zone (상하좌우 각 4모듈)

    // 모듈당 정수 픽셀 — 핵심. round 로 데이터 모듈 영역이 박스를 꽉 채우게 한다.
    // 정수라서 모듈 경계가 칼같이 선명.
    final int modulePx = (qrSize / moduleCount).round().clamp(1, 999);
    final double dataPx = (modulePx * moduleCount).toDouble(); // ≈ qrSize
    final double quietPx = (modulePx * quietModules).toDouble();

    // 데이터 모듈 영역을 박스 중앙에 정렬(정수 픽셀 스냅).
    final double originX = (origin.dx + (qrSize - dataPx) / 2).roundToDouble();
    final double originY = (origin.dy + (qrSize - dataPx) / 2).roundToDouble();

    final whitePaint = Paint()
      ..color = Colors.white
      ..isAntiAlias = false;
    final blackPaint = Paint()
      ..color = Colors.black
      ..isAntiAlias = false
      ..style = PaintingStyle.fill;

    // quiet zone 포함 흰 배경(데이터 영역 + 사방 4모듈).
    final double quietTop = originY - quietPx;
    final double top = clampQuietTopTo != null
        ? (quietTop < clampQuietTopTo ? clampQuietTopTo : quietTop)
        : quietTop;
    final double quietBottom = originY + dataPx + quietPx;
    final double bottom = clampQuietBottomTo != null
        ? (quietBottom > clampQuietBottomTo ? clampQuietBottomTo : quietBottom)
        : quietBottom;
    canvas.drawRect(
      Rect.fromLTRB(
        originX - quietPx,
        top,
        originX + dataPx + quietPx,
        bottom,
      ),
      whitePaint,
    );

    canvas.save();
    canvas.translate(originX, originY);
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

  // --- Logo Cache (mixin 전역 — LabelPainter/ContinuousLabelPainter 공유) ---
  static ui.Image? _cachedLogo;
  static String? _cachedLogoPath;
  static bool _logoLoadAttempted = false;

  /// 브랜드 전환 감지 + 캐시 + 폴백까지 포함한 로고 해석.
  ///
  /// [targetPath] 가 null 이면(hasLabelLogo=false 브랜드) 캐시를 정리하고 null 을
  /// 반환한다. 두 painter 가 같은 브랜드 자산을 쓰므로 캐시를 공유해 중복 디코드를
  /// 피한다.
  static Future<ui.Image?> resolveLogo(
      String? targetPath, String fallbackPath) async {
    if (_cachedLogoPath != targetPath) {
      // 브랜드 전환(또는 첫 로드) — 캐시 무효화 후 재시도.
      _cachedLogo = null;
      _logoLoadAttempted = false;
      _cachedLogoPath = null;
    }
    if (targetPath == null) {
      _logoLoadAttempted = false;
      _cachedLogoPath = null;
      return null;
    }
    if (!_logoLoadAttempted) {
      _logoLoadAttempted = true;
      _cachedLogo = await _loadLogoImage(targetPath);
      if (_cachedLogo == null && targetPath != fallbackPath) {
        logger.w(
            '[LabelDrawOps] primary logo load failed ($targetPath), falling back');
        _cachedLogo = await _loadLogoImage(fallbackPath);
      }
      _cachedLogoPath = targetPath;
    }
    return _cachedLogo;
  }

  static Future<ui.Image?> _loadLogoImage(String assetPath) async {
    try {
      final ByteData data = await rootBundle.load(assetPath);
      final Uint8List bytes = data.buffer.asUint8List();
      final Completer<ui.Image> completer = Completer();
      ui.decodeImageFromList(bytes, (img) => completer.complete(img));
      return await completer.future;
    } catch (e) {
      logger.w('[LabelDrawOps] failed to load logo asset ($assetPath): $e');
      return null;
    }
  }
}
