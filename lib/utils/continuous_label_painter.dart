import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:qr/qr.dart';

import 'package:appfit_order_agent/services/label_printer/label_media_spec.dart';
import 'package:appfit_order_agent/utils/brand_assets.dart';
import 'package:appfit_order_agent/utils/label_draw_ops.dart';

/// BIXOLON G30 연속 용지(40mm, 세로 가변) 전용 painter.
///
/// [LabelPainter](갭 라벨 490×600 고정)와는 별개 레이아웃이다 — 요소 구성은
/// 첨부 목업을 따르고, 저수준 draw 프리미티브(`drawText`/`drawAutoFitText`/
/// `drawCrispQr`/로고 캐시)만 [LabelDrawOps] 로 공유한다.
///
/// **세로 가변**: `paint()`(CustomPainter 계약)는 [LabelMediaSpec.maxHeightDots]
/// 크기로 그린다. 실제 사용은 [paintAndMeasure] 로 콘텐츠 하단 Y 를 받아
/// [generateContinuousLabelImage] 가 `Picture.toImage(w, h)` 로 그 높이만
/// 래스터화한다(2-pass 불필요 — 원점 기준 영역만 잘라내면 되므로).
class ContinuousLabelPainter extends CustomPainter with LabelDrawOps {
  final LabelMediaSpec spec;
  final String menuName;
  final List<String> options;
  final String? shopOrderNo;

  /// 헤더 중앙에 찍는 날짜 텍스트. `'M/d HH:mm:ss'` 1줄 포맷 — 목업 기준.
  final String? headerDateText;

  /// 서브정보 문자열들 — **목록 순서 그대로** 좌측 정렬 1줄로 이어 붙인다.
  final List<String> subInfo;
  final String? memo;
  final String? qrData;
  final ui.Image? logoImage;
  final int? orderIndex;
  final int? orderTotal;
  final int qrErrorCorrectLevel;

  const ContinuousLabelPainter({
    required this.spec,
    required this.menuName,
    required this.options,
    this.shopOrderNo,
    this.headerDateText,
    this.subInfo = const [],
    this.memo,
    this.qrData,
    this.logoImage,
    this.orderIndex,
    this.orderTotal,
    this.qrErrorCorrectLevel = QrErrorCorrectLevel.M,
  });

  // ── 레이아웃 상수 (2026-08 3차 실물 출력 피드백 반영: subInfo/menuName/
  // option 폰트 확대 + QR 바로 아래 간격 확대(subInfo 유무와 무관하게 QR
  // 다음 요소까지 항상 동일 간격, 아래 paintAndMeasure 의 조건부 gap 참조) +
  // subInfo-menuName 간격 축소. 유효 인쇄폭·좌우 여백은 실기기 눈금자 실측으로
  // 확정된 값([LabelMediaSpec.continuous40] 참조 — 캔버스 자체를 유효
  // 인쇄폭으로 좁혔다). 이 상수들은 spec.contentWidthDots 를 참조하므로 폭
  // 변경에 자동 반응한다) ──
  static const double topMargin = 4;

  /// 하단 여백(세로 clamp 용) — 가로 마진과 별개로 관리한다.
  static const double bottomMarginDots = 12;

  /// 헤더~메모까지 대부분의 섹션 사이에 쓰는 공통 간격. QR 바로 다음(
  /// [gapQrToSubInfo])과 subInfo-메뉴명([gapSubInfoToMenuName])만 실물
  /// 피드백으로 별도 값을 쓴다 — 아래 참조.
  static const double gapUnit = 16;

  static const double headerHeight = 44;
  static const double headerLogoSize = 38;
  static const double headerFontSize = 18;

  static const double displayNumFontSize = 80;
  static const double displayNumFontSizeMin = 48;
  static const double gapHeaderToDisplayNum = gapUnit;

  static const double qrSize = 160;
  static const double gapDisplayNumToQr = gapUnit;

  static const double subInfoFontSize = 18;

  /// QR 바로 다음 요소(subInfo 가 있으면 subInfo, 없으면 메뉴명)까지의 간격.
  /// subInfo 유무와 무관하게 **항상 이 값 하나**만 적용된다(아래
  /// paintAndMeasure 참조) — subInfo 가 있을 때만 유독 좁아 보인다는 피드백
  /// 으로 subInfo 유무 상관없이 통일했다.
  static const double gapQrToSubInfo = gapUnit * 2;

  static const double menuNameFontSize = 26;
  static const double menuNameLineHeight = 1.25;
  static const int menuNameMaxLines = 2;

  /// subInfo → 메뉴명 간격. subInfo 가 있을 때만 적용(없으면 애초에 subInfo
  /// 자체가 안 그려지므로 이 gap 도 스킵 — [gapQrToSubInfo] 가 대신 메뉴명
  /// 앞 간격을 담당한다). 실물 피드백: 기존 gapUnit(16)이 "너무 넓다"고 해서
  /// 축소.
  static const double gapSubInfoToMenuName = 8;

  static const double optionFontSize = 20;
  static const double optionRowHeight = 26;
  static const int optionMaxRows = 5;
  static const double gapMenuNameToOptions = gapUnit;

  static const double gapOptionsToDivider = gapUnit;
  static const double gapDividerToMemo = gapUnit;

  static const double memoFontSize = menuNameFontSize;
  static const double memoLineHeight = 1.3;
  static const int memoMaxLines = 3;

  @override
  void paint(Canvas canvas, Size size) {
    paintAndMeasure(canvas, size);
  }

  /// 실제 렌더 + 콘텐츠 하단 Y 를 반환한다. [size] 는 보통
  /// `Size(spec.widthDots, spec.maxHeightDots)` — cap 높이로 그리고, 호출부가
  /// 반환값으로 실제 필요한 높이만 잘라 래스터화한다.
  double paintAndMeasure(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);

    final double left = spec.sideMarginDots;
    final double contentWidth = spec.contentWidthDots;
    double y = topMargin;

    // ── 헤더: 로고(좌) / 날짜(중) / n/N(우) ──────────────────────────────
    if (logoImage != null) {
      final double logoY = y + (headerHeight - headerLogoSize) / 2;
      canvas.drawImageRect(
        logoImage!,
        Rect.fromLTWH(
            0, 0, logoImage!.width.toDouble(), logoImage!.height.toDouble()),
        Rect.fromLTWH(left, logoY, headerLogoSize, headerLogoSize),
        Paint()..filterQuality = FilterQuality.none,
      );
    }
    if (headerDateText != null) {
      drawText(
        canvas,
        headerDateText!,
        Offset(size.width / 2, y + (headerHeight - headerFontSize) / 2),
        fontSize: headerFontSize,
        align: TextAlign.center,
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
    y += headerHeight + gapHeaderToDisplayNum;

    // ── 표시번호 (초대형, 중앙) ───────────────────────────────────────────
    if (shopOrderNo != null && shopOrderNo!.isNotEmpty) {
      // ★ baseFontSize 를 그대로 높이로 쓰면 안 된다 — Pretendard 의 실제
      // line-height 는 fontSize 보다 커서(자동축소로 fs < base 여도 마찬가지)
      // 예약 공간이 실제 렌더 높이보다 작아져 바로 아래 QR 을 침범한다(실기기
      // 확인). menuName/memo 와 동일하게 TextPainter 로 실측한다.
      final displayFs = LabelDrawOps.fitFontSize(
        shopOrderNo!,
        maxWidth: contentWidth,
        baseFontSize: displayNumFontSize,
        minFontSize: displayNumFontSizeMin,
        isBold: true,
      );
      final probe = TextPainter(
        text: TextSpan(
          text: shopOrderNo!,
          style: TextStyle(
            fontSize: displayFs,
            fontWeight: FontWeight.w600,
            fontFamily: 'Pretendard',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: contentWidth);
      drawText(
        canvas,
        shopOrderNo!,
        Offset(size.width / 2, y),
        fontSize: displayFs,
        isBold: true,
        align: TextAlign.center,
        maxWidth: contentWidth,
      );
      y += probe.height;
    }
    y += gapDisplayNumToQr;

    // ── QR (중앙) ────────────────────────────────────────────────────────
    if (qrData != null) {
      // clampQuietTopTo/BottomTo 필수 — QR 의 quiet zone(모듈 4개 폭 흰 배경)이
      // 기본 동작대로 origin.dy 위/아래로 그냥 확장되면, 위아래 간격(gap)보다
      // quiet zone 이 더 넓을 때 인접 요소를 흰색으로 덮어써 버린다(표시번호/QR
      // "겹침" 실물 보고의 원인이었다 — QR 박스([y, y+qrSize]) 안으로 clamp해
      // gap 크기와 무관하게 항상 안전하도록 만든다).
      drawCrispQr(
        canvas,
        qrData!,
        Offset((size.width - qrSize) / 2, y),
        qrSize: qrSize,
        qrErrorCorrectLevel: qrErrorCorrectLevel,
        clampQuietTopTo: y,
        clampQuietBottomTo: y + qrSize,
      );
      y += qrSize;
    }
    y += gapQrToSubInfo;

    // ── 서브정보 (좌측, 1줄) ─────────────────────────────────────────────
    final subInfoText = subInfo.where((s) => s.isNotEmpty).join(' / ');
    if (subInfoText.isNotEmpty) {
      final probe = TextPainter(
        text: TextSpan(
          text: subInfoText,
          style: const TextStyle(fontSize: subInfoFontSize, fontFamily: 'Pretendard'),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      drawText(
        canvas,
        subInfoText,
        Offset(left, y),
        fontSize: subInfoFontSize,
      );
      y += probe.height;
      // subInfo 가 실제로 그려졌을 때만 추가 — 없으면 gapQrToSubInfo 하나가
      // 이미 QR→메뉴명 간격을 담당하므로 여기서 또 더하면 subInfo 유무에
      // 따라 간격이 달라져 버린다(요청: 두 경우 QR 다음 요소까지 간격 동일).
      y += gapSubInfoToMenuName;
    }

    // ── 메뉴명 (좌측, 굵게, 최대 2줄) ────────────────────────────────────
    if (menuName.isNotEmpty) {
      final menuFs = LabelDrawOps.fitFontSize(
        menuName,
        maxWidth: contentWidth,
        baseFontSize: menuNameFontSize,
        minFontSize: menuNameFontSize, // G30 은 축소 없이 ellipsis 로 대응
        isBold: true,
        maxLines: menuNameMaxLines,
        lineHeight: menuNameLineHeight,
      );
      final probe = TextPainter(
        text: TextSpan(
          text: menuName,
          style: TextStyle(
            fontSize: menuFs,
            fontWeight: FontWeight.w600,
            fontFamily: 'Pretendard',
            height: menuNameLineHeight,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: menuNameMaxLines,
        ellipsis: '...',
      )..layout(maxWidth: contentWidth);
      drawText(
        canvas,
        menuName,
        Offset(left, y),
        fontSize: menuFs,
        isBold: true,
        maxWidth: contentWidth,
        maxLines: menuNameMaxLines,
        height: menuNameLineHeight,
      );
      y += probe.height;
    }
    y += gapMenuNameToOptions;

    // ── 옵션 (좌측 1열, 최대 optionMaxRows 행 + 초과 시 +N) ──────────────
    if (options.isNotEmpty) {
      final int shown =
          options.length > optionMaxRows ? optionMaxRows : options.length;
      final bool overflowed = options.length > optionMaxRows;
      for (int i = 0; i < shown; i++) {
        final bool isMoreCell = overflowed && i == shown - 1;
        final String text = isMoreCell
            ? '+${options.length - (optionMaxRows - 1)}'
            : options[i];
        drawAutoFitText(
          canvas,
          text,
          Offset(left, y + i * optionRowHeight),
          baseFontSize: optionFontSize,
          minFontSize: optionFontSize - 3,
          maxWidth: contentWidth,
        );
      }
      y += shown * optionRowHeight;
    }
    y += gapOptionsToDivider;

    // ── 구분선 ───────────────────────────────────────────────────────────
    canvas.drawLine(
      Offset(left, y),
      Offset(left + contentWidth, y),
      Paint()
        ..color = Colors.black
        ..strokeWidth = 1,
    );
    y += gapDividerToMemo;

    // ── 메모 (좌측, 최대 3줄) ────────────────────────────────────────────
    if (memo != null && memo!.isNotEmpty) {
      final probe = TextPainter(
        text: TextSpan(
          text: memo,
          style: TextStyle(
            fontSize: memoFontSize,
            fontFamily: 'Pretendard',
            height: memoLineHeight,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: memoMaxLines,
        ellipsis: '...',
      )..layout(maxWidth: contentWidth);
      drawText(
        canvas,
        memo!,
        Offset(left, y),
        fontSize: memoFontSize,
        maxWidth: contentWidth,
        maxLines: memoMaxLines,
        height: memoLineHeight,
      );
      y += probe.height;
    }

    return y;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;

  /// 주문 시각을 헤더용 1줄 포맷(`'M/d HH:mm:ss'`)으로. [orderedAt] 이 없으면
  /// (예: [LabelPrintData.testSample], `orderInfo` 미포함) 기존 2줄 포맷
  /// `orderTime`("MM/dd\nHH:mm:ss")의 개행을 공백으로 치환해 대체한다 —
  /// DTO 는 건드리지 않는다.
  static String? formatHeaderDate(DateTime? orderedAt, String? legacyOrderTime) {
    if (orderedAt != null) {
      return DateFormat('M/d HH:mm:ss').format(orderedAt);
    }
    if (legacyOrderTime != null) {
      return legacyOrderTime.replaceAll('\n', ' ');
    }
    return null;
  }

  static Future<Uint8List> generateContinuousLabelImage({
    required LabelMediaSpec spec,
    required String menuName,
    required List<String> options,
    String? shopOrderNo,
    DateTime? orderedAt,
    String? legacyOrderTime,
    List<String> subInfo = const [],
    String? memo,
    String? qrData,
    int? orderIndex,
    int? orderTotal,
    int qrErrorCorrectLevel = QrErrorCorrectLevel.M,
  }) async {
    assert(spec.variableHeight,
        'generateContinuousLabelImage 는 가변 높이 spec 전용 — gap490x600 은 LabelPainter.generateLabelImage 를 쓸 것');

    final ui.Image? logo = await LabelDrawOps.resolveLogo(
        BrandAssets.labelLogoPath, BrandAssets.labelLogoFallbackPath);

    final painter = ContinuousLabelPainter(
      spec: spec,
      menuName: menuName,
      options: options,
      shopOrderNo: shopOrderNo,
      headerDateText: formatHeaderDate(orderedAt, legacyOrderTime),
      subInfo: subInfo,
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
    // Picture.toImage(w, h) 는 원점 기준 영역만 래스터화 — cap 높이로 그린 뒤
    // 실제 필요한 높이만 잘라내면 되므로 2-pass(재측정 후 재그리기)가 불필요.
    final img = await picture.toImage(spec.widthDots.toInt(), h);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);

    if (byteData == null) {
      throw Exception('Failed to generate continuous label image bytes');
    }
    return byteData.buffer.asUint8List();
  }
}
