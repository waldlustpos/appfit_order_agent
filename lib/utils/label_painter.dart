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

  /// 라벨 레이아웃 버전 (0: V1 기존, 1: V2 QR 우측상단). 선택 설정은 폐지되어
  /// 호출부에서 항상 V2(1)를 전달한다(V1 분기 코드는 하위호환용으로 잔존).
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

  /// 빠른 제조 메뉴 마커 표시 여부. true 면 sub-info 행 맨 앞(=가장 우측)에
  /// 반전 칩(흰 글씨 + 검정 배경)이 붙는다. 호출부에서 "지정된 메뉴 && 표시 설정 ON"
  /// 을 이미 판정해 넘긴다.
  final bool isFastMenu;

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
    this.isFastMenu = false,
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

  /// 메뉴명 자동 축소 하한.
  ///
  /// 기본 크기(28)로 [menuNameMaxLines] 줄까지 먼저 쓰고, 그래도 넘칠 때만
  /// 여기까지 축소한다. 더 내리면 subInfo(22)/옵션(21)보다 작아져 시각 위계가
  /// 역전되고, 490dot ≈ 61mm(≈8.0 dot/mm) 기준 20dot ≈ 2.5mm 로 감열 번짐
  /// 한계에 근접한다. 하한 도달 후 초과분은 `_drawText` 의 ellipsis 가 처리한다.
  static const double fsMenuNameMin = 20;

  /// 메뉴명 최대 줄 수. 수용력(Pretendard 한글 advance ≈ 1.0em, maxWidth 340):
  /// 28px 1줄 12자 → 2줄 24자, 하한 20px 2줄이면 34자.
  static const int menuNameMaxLines = 2;

  /// 메뉴명 줄 높이. **예약 슬롯을 폰트 메트릭에 의존하지 않고 정확히 계산하려면
  /// 반드시 명시해야 한다** — 미지정이면 실제 높이가 예약과 어긋나 2줄째가
  /// 옵션 구분선을 침범한다.
  static const double menuNameLineHeight = 1.2;

  /// 메뉴명 슬롯 높이. 실제 줄 수와 무관하게 항상 [menuNameMaxLines] 줄분을
  /// 예약해 하단 섹션 Y 를 라벨 간 고정한다(1줄짜리 메뉴는 슬롯 하단에 붙인다).
  static const double menuSlotHeight =
      fsMenuName * menuNameLineHeight * menuNameMaxLines; // 67.2
  static const double fsOrderNo = 85; //주문번호사이즈 (QR 없을 때)
  static const double fsOrderNoWithQr =
      57; //주문번호사이즈 (V1, QR 동반 시 — 겹침 방지용 조정 노브)
  static const double fsOrderNoWithQrV2 = 40; //주문번호사이즈 (V2, QR 동반 시)
  static const double fsSectionTitle = 22;
  static const double fsOptionItem = 21;

  /// 옵션 셀 자동 축소 하한. 메뉴명 하한(20)보다 낮게 잡는다 — 옵션은 보조
  /// 정보라 위계상 아래가 맞고, 좁은 셀에서 축소 이득이 상대적으로 크다.
  /// 수용력: 1열(340) 21→16자 / 18→19자, 2열(164) 21→7.8자 / 18→9자.
  /// 16 까지 내리면 일본어 한자 획이 뭉치므로 실출력 검증 없이 내리지 말 것.
  static const double fsOptionItemMin = 18;
  static const double fsDetailContent = 22;

  // Dimensions & Spacings
  static const double logoWidthDefault = 50;
  static const double qrSizeDefault = 120; // QR 크기 (기본 90 → 120 확대)
  static const double spacingSectionSmall = 15;
  static const double spacingSectionLarge = 30;

  /// 구분선 주변 여백 (V2 하단 섹션 전용).
  ///
  /// 옵션 3행(84)을 넣으려면 28px 이 필요한데, 검증받은 간격 — 헤더↔QR(21),
  /// QR↔subinfo(16), subinfo↔상품명(6) — 은 건드릴 수 없다. 대신 이 값이 쓰이는
  /// 4곳(상품명↔옵션구분선, 옵션구분선↔첫 행, 마지막 행↔DETAIL 구분선,
  /// DETAIL 구분선↔메모)을 15 → 8 로 줄여 **정확히 28px** 을 만든다.
  ///
  /// 8dot ≈ 1mm(203dpi). 1px 두께 구분선 주변이라 QR 같은 검은 덩어리 옆과 달리
  /// 이 정도로도 섹션 구분이 읽힌다.
  static const double sectionGapTight = 8;

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
  //
  // ⚠ 이 값들은 TPCP 실출력 검증으로 확정됐다. **여기서 깎지 말 것** —
  // 메뉴명 2줄 슬롯의 재원은 헤더 로고 예약 정상화(PAIK)와 옵션 행 수(3→2)에서
  // 확보한다.
  //
  // **subinfo 자리(fsSubInfo=22)는 값이 없어도 그대로 예약한다** — 현재는 TPCP
  // 전용이지만 PAIK 등에서 추후 활용할 여지가 있어 공간을 비워 둔다.

  /// QR 하단 ↔ subinfo **최소** 간격.
  ///
  /// subinfo 는 QR 에 고정되지 않고 상품명 바로 위에 붙어 다닌다(아래
  /// [bodyV2MenuGap] 참고). 따라서 이 값은 상품명이 슬롯을 꽉 채운 2줄일 때만
  /// 실제로 나타나고, 1줄이면 남는 한 줄(33.6)만큼 더 벌어진다.
  ///
  /// QR 은 검은 덩어리라 바로 아래 텍스트가 붙어 보이기 쉽다. 8 일 때
  /// "너무 가깝다" 피드백을 받아 16 으로 올렸다.
  static const double bodyV2SubInfoGap = 16;

  /// subinfo ↔ 상품명. 둘은 같은 상품을 설명하는 한 덩어리라 **붙여 둔다**.
  /// 슬롯에 남는 공간은 이 사이가 아니라 QR 쪽(위)으로 몰아준다.
  static const double bodyV2MenuGap = 6;

  /// 메뉴명 슬롯 하단 ↔ 옵션 구분선.
  static const double bodyV2MenuBottomGap = sectionGapTight;

  // ── 헤더 높이 ─────────────────────────────────────────────────────────
  // 종전엔 로고를 그리든 말든 무조건 labelLogoWidth 만큼 예약했다. PAIK 는
  // hasLabelLogo=false(로고 미표시)인데 labelLogoWidth=70 이라 **그리지도 않는
  // 로고 자리를 70px 잡아먹고** 있었다. 이제 실제 콘텐츠 높이로 예약한다.

  /// 헤더 좌측 텍스트 블록(주문시각 2줄)이 차지하는 높이 + 상단 오프셋 5.
  /// 우측 순번(fsSubInfo 1줄 ≈ 29)보다 크므로 텍스트 블록의 대표값이 된다.
  static const double headerTextBlockHeight =
      5 + fsHeaderTime * 1.2 * 2; // 43.4

  /// V2 헤더 아래 여백 (= 종전 구분선 클리어런스 6 + spacingSectionSmall 15).
  ///
  /// ⚠ 한때 "V2 는 구분선을 안 그리니 6 은 불필요" 라고 8 까지 줄였다가 TPCP
  /// 실출력에서 "로고와 QR 이 너무 가깝다" 피드백을 받고 원복했다. 구분선이
  /// 없어도 로고 하단과 QR 상단 사이에는 이만큼의 시각적 분리가 필요하다.
  static const double headerV2BottomGap = 6 + spacingSectionSmall;

  /// 헤더가 실제로 차지하는 높이. 로고를 그릴 때만 로고 폭을 예약에 반영한다.
  @visibleForTesting
  static double headerContentHeight({
    required bool hasLogo,
    required double logoWidth,
  }) {
    if (!hasLogo) return headerTextBlockHeight;
    return logoWidth > headerTextBlockHeight
        ? logoWidth
        : headerTextBlockHeight;
  }

  static const double optionRowHeight = 28; // 옵션 한 줄 높이

  // ── 옵션 영역 배치 ─────────────────────────────────────────────────────
  // 세로 예약은 옵션 개수와 무관하게 고정한다. 이 값을 넘기면 DETAIL 구분선/
  // 메모가 아래로 밀려 하단 여백이 잘린다.
  //
  // 3행 = 1열 모드에서 긴 옵션명 3개를 폭 340 으로 온전히(ellipsis 없이) 싣거나,
  // 2열 모드에서 6개까지 담기 위한 값. 이 28px 은 [sectionGapTight] 로 확보했다.
  static const int optionMaxRows = 3;
  static const double optionReservedHeight = optionRowHeight * optionMaxRows;

  /// 2열 모드의 열 사이 간격. 이 값을 빼서 셀 폭을 정해야 col1 우측 끝이
  /// 구분선 끝(width - defaultMargin)과 정확히 일치한다(종전 5px 침범 버그).
  static const double optionColGutter = 12;

  /// 1열 전환 임계. 이하면 full-width 1열(폭 340), 초과면 2열(폭 164).
  ///
  /// 사이즈/온도/원두는 `LabelFilterStrategy.classifyOptions` 가 sub-info 로
  /// 빼가므로(TPCP 한정) 여기 남는 옵션은 실무상 0~2개가 압도적이다. 그 구간을
  /// 1열로 처리하면 셀 폭이 2배가 되어 7.8자 → 16자로 늘어난다.
  static const int optionSingleColumnMax = optionMaxRows;

  /// 2열 모드 최대 표시 개수. 초과분은 마지막 셀을 `+N` 으로 대체한다.
  static const int optionMaxShown = optionMaxRows * 2;

  /// 자동 축소 시 원래 폰트 슬롯의 세로 중앙으로 내리는 계수 (line-height 1.2 / 2).
  static const double _fitVerticalCenterFactor = 0.6;

  /// V2 콘텐츠 하단과 캔버스 하단 사이 여백 (offsetY 적용 후).
  ///
  /// 라벨은 CI 에서 눈으로 비교할 수 없어 "브랜드 X 에서 메모가 잘렸다" 를
  /// 인쇄한 뒤에야 알게 된다. 그래서 세로 체인을 여기서 한 번 더 계산해
  /// 테스트로 하한을 고정한다.
  ///
  /// **`_drawHeader`/`_drawBodyV2`/`_drawOptions`/`_drawDetail` 의 Y 계산을
  /// 바꾸면 이 함수도 같이 고쳐야 한다.** 체인이 전부 상수 기반이라(메모는
  /// `height: 1.3`, 메뉴명은 [menuNameLineHeight] 를 명시) 폰트 메트릭에
  /// 흔들리지 않고 결정적으로 재현된다.
  @visibleForTesting
  static double v2BottomMargin({
    required bool hasLogo,
    required double logoWidth,
    double canvasHeight = height,
  }) {
    final double bodyTop = defaultMargin +
        headerContentHeight(hasLogo: hasLogo, logoWidth: logoWidth) +
        headerV2BottomGap;
    // 슬롯 상단 = subinfo 자리(값이 없어도 예약). subinfo 실제 Y 는 상품명 줄
    // 수에 따라 이보다 아래로 내려가지만, 슬롯 하단은 고정이라 여기 영향 없다.
    final double slotTop = bodyTop + qrSizeForLayout(1) + bodyV2SubInfoGap;
    final double menuSlotTop = slotTop + fsSubInfo + bodyV2MenuGap;
    final double optionDividerY =
        menuSlotTop + menuSlotHeight + bodyV2MenuBottomGap;
    final double optionStartY = optionDividerY + sectionGapTight;
    final double detailDividerY =
        optionStartY + optionReservedHeight + sectionGapTight;
    // V2 는 DETAIL 타이틀을 그리지 않아 메모가 바로 온다 (최악 = 2줄).
    final double memoBottom =
        detailDividerY + sectionGapTight + fsDetailContent * 1.3 * 2;
    return canvasHeight - (memoBottom + offsetY);
  }

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
    // 로고 표시 폭은 브랜드별 지정 가능(BrandMeta.labelLogoWidth, 기본 50).
    final double logoW = BrandAssets.labelLogoWidth;

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

    if (logoImage != null) {
      // Logo (centered) — 정사각 배치라 높이 = 폭.
      final Rect dstRect =
          Rect.fromLTWH(size.width / 2 - logoW / 2, startY, logoW, logoW);

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

    // 헤더 높이는 실제 콘텐츠 기준 — 로고를 그리지 않는 브랜드(PAIK)는 로고 폭을
    // 예약하지 않는다. 브랜드가 달라도 콘텐츠가 같으면 같은 Y 라 레이아웃은 안정적.
    final double contentHeight = headerContentHeight(
      hasLogo: logoImage != null,
      logoWidth: logoW,
    );

    // V2 는 구분선을 그리지 않으므로(인쇄 시 잘려 보임) 여백만 두고 본문을 올린다.
    // 여기서 아낀 세로 공간이 메뉴명 2줄 슬롯으로 간다.
    if (layoutVersion == 1) return startY + contentHeight + headerV2BottomGap;

    final double dividerY = startY + contentHeight + 6;
    canvas.drawLine(
      Offset(defaultMargin, dividerY),
      Offset(size.width - defaultMargin, dividerY),
      paint..strokeWidth = 1,
    );
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

    // 2. Menu Name — V1 은 **1줄 고정**. 아래 qrTopOffset(70) 지점에서 QR 이
    //    시작하는데 28px 2줄은 67.2 라 currentY+30 에서 그리면 QR 을 침범한다.
    //    2줄 슬롯은 헤더를 압축해 공간을 만든 V2 에서만 쓴다.
    _drawAutoFitText(
      canvas,
      menuName,
      Offset(size.width - defaultMargin, currentY + 30),
      baseFontSize: fsMenuName,
      minFontSize: fsMenuNameMin,
      isBold: true,
      align: TextAlign.right,
      maxWidth: size.width - (defaultMargin * 2),
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

  /// V2: QR(우측 상단) + 주문번호(좌측, QR 세로중앙) → [subinfo + 상품명] 덩어리
  /// (슬롯 하단 정렬, 우측).
  ///
  /// subinfo 와 상품명은 같은 상품을 설명하므로 **붙여서 한 덩어리로** 다루고,
  /// 상품명이 1줄이라 슬롯에 남는 공간은 둘 사이가 아니라 **QR 쪽(위)** 으로
  /// 몰아준다. 종전처럼 subinfo 를 QR 바로 아래에 고정하면 1줄 상품명일 때
  /// subinfo 가 상품명에서 떨어져 나와 QR 에 붙어 보였다.
  double _drawBodyV2(Canvas canvas, Size size, double startY) {
    // 1. QR(우측 상단) + 주문번호(좌측, QR 세로중앙)
    _drawQrAndOrderNo(canvas, size, startY,
        qrOnLeft: false, centerOrderNoToQr: true);

    // 2. [subinfo + 상품명] 슬롯. 높이는 실제 줄 수·폰트 크기와 무관하게 상수로
    //    예약해 하단 섹션 Y 를 라벨 간 고정한다 — 레이아웃 회귀를 0 으로 만드는
    //    핵심. subinfo 는 값이 없어도 fsSubInfo 만큼 자리를 남긴다.
    final double slotTop = startY + qrSize + bodyV2SubInfoGap;
    final double menuSlotTop = slotTop + fsSubInfo + bodyV2MenuGap;

    // 3. 상품명: 기본 크기(28)로 menuNameMaxLines 줄까지 쓰고, 그래도 넘칠 때만
    //    fsMenuNameMin 까지 축소. 슬롯 하단 정렬이라 실제 상단 Y 는 줄 수에 따라
    //    달라진다 — 그 값을 받아 subinfo 를 바로 위에 붙인다.
    final double menuTop = _drawAutoFitText(
      canvas,
      menuName,
      Offset(size.width - defaultMargin, menuSlotTop),
      baseFontSize: fsMenuName,
      minFontSize: fsMenuNameMin,
      isBold: true,
      align: TextAlign.right,
      maxWidth: size.width - (defaultMargin * 2),
      maxLines: menuNameMaxLines,
      lineHeight: menuNameLineHeight,
      slotHeight: menuSlotHeight,
    );

    // 4. subinfo: 상품명 바로 위. QR 에 고정하지 않는다.
    _drawSubInfo(canvas, size, menuTop - bodyV2MenuGap - fsSubInfo);

    // 5. 다음 섹션(옵션 구분선) 시작 Y — 슬롯 하단 고정.
    return menuSlotTop + menuSlotHeight + bodyV2MenuBottomGap;
  }

  void _drawSubInfo(Canvas canvas, Size size, double y) {
    double currentRightX = size.width - defaultMargin;

    final items = <_SubInfoItem>[];
    // sub-info 는 우측 정렬로 그려지므로(currentRightX 가 오른쪽에서 왼쪽으로
    // 이동) 리스트 첫 항목이 가장 오른쪽에 온다. 마커를 맨 앞에 넣어 라벨
    // 우측 상단, 즉 시선이 먼저 닿는 자리에 오게 한다.
    if (isFastMenu) {
      items.add(_SubInfoItem(text: t.common.fast_menu, isHighlighted: true));
    }
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

    // quiet zone 포함 흰 배경(데이터 영역 + 사방 4모듈). 라벨 배경이 흰색이라도
    // 명시적으로 깔아 스캐너 여백을 보장한다.
    //
    // 단, 흰 배경 상단은 예약 박스 상단(origin.dy)까지만 확장하도록 clamp 한다.
    // QR 은 헤더 다음에 그려지므로(paint(): _drawHeader → _drawBody), quiet zone 을
    // 위로 무한정 펼치면 바로 위에 이미 그려진 헤더(로고/시각/순번)를 흰색으로 덮어
    // "헤더 잘림"이 난다. 모듈 수가 적을수록(짧은 QR payload) quietPx(=modulePx*4)가
    // 커져 침범 폭이 커진다. 박스 상단 위쪽은 어차피 라벨 흰 배경이라 스캐너 여백은
    // 그대로 보장되므로 clamp 해도 인식률 손해는 없다.
    final double quietTop = originY - quietPx;
    final double clampedTop = quietTop < origin.dy ? origin.dy : quietTop;
    canvas.drawRect(
      Rect.fromLTRB(
        originX - quietPx,
        clampedTop,
        originX + dataPx + quietPx,
        originY + dataPx + quietPx,
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
      optionStartY = startY + sectionGapTight;
    } else {
      _drawText(canvas, optionTitleOverride ?? t.receipt.section_option,
          Offset(size.width / 2, startY + spacingSectionSmall),
          fontSize: fsSectionTitle, isBold: false, align: TextAlign.center);
      optionStartY =
          startY + spacingSectionSmall + fsSectionTitle + spacingSectionSmall;
    }
    final cells = optionCells(options.length, canvasWidth: size.width);
    final bool overflowed = options.length > optionMaxShown;

    for (int i = 0; i < cells.length; i++) {
      final cell = cells[i];
      // 초과 시 마지막 셀을 `+N` 으로 대체 — 종전엔 5번째부터 조용히 사라졌다.
      // 로캘 무관 기호라 i18n 키를 만들지 않는다(문자 표기는 164px 셀에서 다시 잘림).
      final bool isMoreCell = overflowed && i == cells.length - 1;
      final String text =
          isMoreCell ? '+${options.length - (optionMaxShown - 1)}' : options[i];

      _drawAutoFitText(
        canvas,
        text,
        Offset(cell.x, optionStartY + cell.y),
        baseFontSize: fsOptionItem,
        minFontSize: fsOptionItemMin,
        maxWidth: cell.maxWidth,
      );
    }

    // 예약 높이는 옵션 개수와 무관하게 고정 — 하단 섹션 Y 를 라벨 간 불변으로
    // 유지해야 브랜드별 하단 여백이 보장된다.
    return optionStartY + optionReservedHeight + sectionGapTight;
  }

  /// 옵션 개수에 따른 셀 배치를 계산한다 (렌더 없는 순수 함수).
  ///
  /// - `count <= optionSingleColumnMax`: **1열 n행**, 셀 폭 = 콘텐츠 폭(340).
  ///   사이즈/온도/원두가 sub-info 로 빠져 실무상 옵션은 0~2개라 이 경로가
  ///   대부분이다. 폭이 2배가 되어 수용력이 7.8자 → 16자로 늘어난다.
  /// - 그 외: **2열 3행**, 셀 폭 164. col1 우측 끝이 구분선 끝과 정확히 일치한다.
  ///
  /// 반환 y 는 `optionStartY` 기준 상대값이며, `max(y) + optionRowHeight` 는
  /// 항상 [optionReservedHeight] 이하다(하단 섹션 침범 불가).
  @visibleForTesting
  static List<LabelOptionCell> optionCells(
    int count, {
    double canvasWidth = width,
  }) {
    if (count <= 0) return const [];
    final double contentWidth = canvasWidth - (defaultMargin * 2);

    if (count <= optionSingleColumnMax) {
      return List.generate(
        count,
        (i) => LabelOptionCell(
          defaultMargin,
          i * optionRowHeight,
          contentWidth,
        ),
      );
    }

    final double cellWidth = (contentWidth - optionColGutter) / 2;
    final int shown = count > optionMaxShown ? optionMaxShown : count;
    return List.generate(shown, (i) {
      final int row = i ~/ 2;
      final int col = i % 2;
      return LabelOptionCell(
        defaultMargin + col * (cellWidth + optionColGutter),
        row * optionRowHeight,
        cellWidth,
      );
    });
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
      contentY = startY + sectionGapTight;
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

  /// [maxWidth] × [maxLines] 안에 들어가는 최대 폰트 크기를 찾는다.
  ///
  /// **기본 크기를 먼저 쓰고, 줄 수를 다 소진한 뒤에야 축소한다.** 즉 메뉴명은
  /// 28px 2줄까지 원본 크기로 가고 그래도 넘칠 때만 작아진다.
  ///
  /// base 에서 1px 씩 내리는 단순 하향 스캔이다. 탐색 범위가
  /// `baseFontSize - minFontSize` (메뉴 8, 옵션 3) 로 좁아 최악 9회 layout 이며,
  /// 같은 라벨의 QR 래스터화·PNG 인코딩(수십 ms)에 비하면 무시할 수준이다.
  /// 비례 추정을 쓰지 않는 이유는 [maxLines] > 1 일 때 줄바꿈 낭비 때문에
  /// 추정이 빗나가기 때문 — 정확성을 택했다.
  ///
  /// flutter test 에서는 Pretendard 가 로드되지 않아 반환값의 절대치가 폰트에
  /// 의존한다. 테스트는 `[minFontSize, baseFontSize]` 범위·단조성만 검증할 것.
  @visibleForTesting
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
  /// [slotHeight] 를 주면 **슬롯 하단 정렬**. 2줄 슬롯에 1줄짜리가 오면 남는
  /// 한 줄이 위쪽으로 몰린다 — 호출부가 그 위에 subinfo 를 붙여 [상품명+subinfo]
  /// 한 덩어리를 슬롯 아래쪽에 정렬하기 위한 것이다(중앙 정렬은 subinfo 와
  /// 상품명 사이가 벌어져 subinfo 가 QR 에 붙어 보였다).
  /// 주지 않으면 축소분의 절반만큼 내려 원래 폰트 슬롯의 세로 중앙에 맞춘다
  /// (`_drawText` 가 dy 를 텍스트 박스 top 으로 쓰기 때문에 필요한 보정 —
  /// `centerOrderNoToQr` 와 같은 패턴).
  ///
  /// 실제로 텍스트를 그린 상단 Y 를 반환한다 — 호출부가 그 위에 다른 요소를
  /// 붙일 수 있도록.
  double _drawAutoFitText(
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
      dy = offset.dy + (baseFontSize - fs) * _fitVerticalCenterFactor;
    }

    _drawText(
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
    bool isFastMenu = false,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final String? targetPath = BrandAssets.labelLogoPath;
    if (_cachedLogoPath != targetPath) {
      // 브랜드 전환(또는 첫 로드) — 캐시 무효화 후 재시도.
      _cachedLogo = null;
      _logoLoadAttempted = false;
      _cachedLogoPath = null;
    }
    if (targetPath == null) {
      // hasLabelLogo=false 브랜드 — 로고 미표시(자산 준비 전 임시 비활성화).
      _logoLoadAttempted = false;
      _cachedLogoPath = null;
    } else if (!_logoLoadAttempted) {
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
    final ui.Image? logo = targetPath == null ? null : _cachedLogo;

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
      isFastMenu: isFastMenu,
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

/// 라벨 옵션 셀 1개의 배치 — 좌상단 좌표 + 허용 폭.
///
/// [y] 는 옵션 영역 시작(`optionStartY`) 기준 상대값이다.
/// `LabelPainter.optionCells` 가 생성하며, 렌더와 분리된 순수 값이라
/// 폰트 로딩 없이 단위 테스트로 기하학을 고정할 수 있다.
class LabelOptionCell {
  final double x;
  final double y;
  final double maxWidth;

  const LabelOptionCell(this.x, this.y, this.maxWidth);
}
