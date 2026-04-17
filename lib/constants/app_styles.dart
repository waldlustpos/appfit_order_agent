import 'package:flutter/material.dart';
import '../models/order_model.dart';

// ─── 간격 토큰 ────────────────────────────────────────────────────────────────
class AppSpacing {
  const AppSpacing._();
  static const double s4 = 4;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double s32 = 32;
}

// ─── 라운딩 토큰 ──────────────────────────────────────────────────────────────
class AppRadius {
  const AppRadius._();
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;

  static const BorderRadius bSm = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius bMd = BorderRadius.all(Radius.circular(md));
  static const BorderRadius bLg = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius bXl = BorderRadius.all(Radius.circular(xl));
}

// ─── 그림자 토큰 ──────────────────────────────────────────────────────────────
class AppElevation {
  const AppElevation._();

  /// 카드·패널: 약한 그림자
  static const List<BoxShadow> soft = [
    BoxShadow(
      color: Color(0x1A000000), // black 10%
      blurRadius: 12,
      offset: Offset(0, 3),
    ),
  ];

  /// 부유 요소: 눈에 띄는 그림자
  static const List<BoxShadow> card = [
    BoxShadow(
      color: Color(0x26000000), // black 15%
      blurRadius: 16,
      offset: Offset(0, 6),
    ),
  ];
}

// ─── 텍스트 스타일 토큰 ───────────────────────────────────────────────────────
class AppTextStyles {
  const AppTextStyles._();
  static const String _font = 'Pretendard';

  /// 화면 상단 대표 수치·타이틀 (24px bold)
  static const TextStyle display = TextStyle(
    fontFamily: _font,
    fontSize: 24,
    fontWeight: FontWeight.bold,
  );

  /// 섹션/다이얼로그 제목 (20px bold)
  static const TextStyle title = TextStyle(
    fontFamily: _font,
    fontSize: 20,
    fontWeight: FontWeight.bold,
  );

  /// 소제목 (17px semibold)
  static const TextStyle titleSm = TextStyle(
    fontFamily: _font,
    fontSize: 17,
    fontWeight: FontWeight.w600,
  );

  /// 본문 (15px regular)
  static const TextStyle body = TextStyle(
    fontFamily: _font,
    fontSize: 15,
    fontWeight: FontWeight.normal,
  );

  /// 보조 본문 (13px regular)
  static const TextStyle bodySm = TextStyle(
    fontFamily: _font,
    fontSize: 13,
    fontWeight: FontWeight.normal,
  );

  /// 캡션·레이블 (11px regular)
  static const TextStyle caption = TextStyle(
    fontFamily: _font,
    fontSize: 11,
    fontWeight: FontWeight.normal,
  );
}

// ─── 앱 스타일 ────────────────────────────────────────────────────────────────
class AppStyles {
  // 폰트 사이즈 상수 정의
  static const double kAppBarTitleSize = 18.0;
  static const double kOrderNumberSize = 17.0 * 1.2;
  static const double kAppBarTimeSize = 16.0;
  static const double kTabIconSize = 28.0;
  static const double kTabTextSize = 16.0;
  static const double kSectionTitleSize = 16.0 * 1.2;
  static const double kSectionCountSize = 14.0 * 1.2;
  static const double kOrderCardTitleSize = 24.0;
  static const double kOrderCardTimeSize = 14.0 * 1.2;

  // 메인 컬러 정의
  static const Color kMainColor = Color(0xFFfb3e7e);
  static const Color kSub = Color(0xff9843cb);
  static const Color kSubAlpha = Color(0x149843cb);

  static const Color kRed = Color(0xffff3750);
  static const Color kRedAlpha = Color(0x14ff3750);

  static const Color kBlue = Color(0xff0084ff);
  static const Color kBlueAlpha = Color(0x140084ff);

  static const Color kCheckedBgColor = Color(0x1fff00d4);

  static const Color gray9 = Color(0xff0d0f11);
  static const Color gray6 = Color(0xff64696e);
  static const Color gray3 = Color(0xffdee1e4);
  static const Color gray4 = Color(0xffc9cdd1);
  static const Color gray1 = Color(0xfff8fafc);
  static const Color gray2 = Color(0xffedf1f3);

  static const Color green100 = Color(0xff37dc28);
  static const Color green100Alpha = Color(0x1437dc28);

  /// 앰버 — 준비완료(READY) 상태 강조색
  static const Color kAmber = Color(0xFFF59E0B);
  static const Color kAmberAlpha = Color(0x14F59E0B);

  /// 메인 핑크 10% 알파 — NEW 상태 배경용
  static const Color kMainColorAlpha = Color(0x14fb3e7e);

  // ─── 공통 버튼 스타일 ───────────────────────────────────────────────────────

  /// 메인 컬러 filled 버튼 (kMainColor 배경, 흰 글씨)
  static ButtonStyle primaryButton({
    EdgeInsetsGeometry? padding,
    Size? minimumSize,
    double elevation = 0,
  }) =>
      ElevatedButton.styleFrom(
        backgroundColor: kMainColor,
        foregroundColor: Colors.white,
        padding: padding,
        minimumSize: minimumSize,
        elevation: elevation,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      );

  /// kMainColor 테두리 outlined 버튼 (흰 배경, kMainColor 글씨/테두리)
  static ButtonStyle outlinedPrimaryButton({
    EdgeInsetsGeometry? padding,
    Size? minimumSize,
  }) =>
      ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: kMainColor,
        side: const BorderSide(color: kMainColor),
        elevation: 0,
        padding: padding,
        minimumSize: minimumSize,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      );

  /// 회색 테두리 outlined 버튼 (흰 배경, 어두운 글씨)
  static ButtonStyle outlinedButton({
    EdgeInsetsGeometry? padding,
    Size? minimumSize,
    Color borderColor = const Color(0xffc9cdd1), // gray4
  }) =>
      ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        side: BorderSide(color: borderColor),
        elevation: 0,
        padding: padding,
        minimumSize: minimumSize,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      );

  /// 설정 화면 토글 버튼 (선택/미선택 상태)
  static ButtonStyle settingsToggleButton(bool isSelected) =>
      ElevatedButton.styleFrom(
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: isSelected ? kMainColor : gray4,
            width: 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: isSelected ? kMainColor : gray6,
        minimumSize: const Size(60, 40),
      );

  // ─── 공통 InputDecoration ──────────────────────────────────────────────────

  /// filled 스타일 입력 필드 (회색 배경, 포커스 시 kMainColor 테두리)
  static InputDecoration filledInputDecoration({
    String? labelText,
    String? hintText,
    Widget? prefixIcon,
    Widget? suffixIcon,
    FloatingLabelBehavior floatingLabelBehavior = FloatingLabelBehavior.never,
  }) =>
      InputDecoration(
        labelText: labelText,
        hintText: hintText,
        floatingLabelBehavior: floatingLabelBehavior,
        prefixIcon: prefixIcon,
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: const Color(0xffedf1f3), // gray2
        border: OutlineInputBorder(
          borderSide: BorderSide.none,
          borderRadius: BorderRadius.circular(8),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide.none,
          borderRadius: BorderRadius.circular(8),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: kMainColor, width: 2),
          borderRadius: BorderRadius.circular(8),
        ),
      );

  /// outlined 스타일 입력 필드 (회색 테두리, 포커스 시 kMainColor 테두리)
  static InputDecoration outlinedInputDecoration({
    String? hintText,
    String? labelText,
    Widget? prefixIcon,
    Widget? suffixIcon,
    TextStyle? hintStyle,
  }) =>
      InputDecoration(
        hintText: hintText,
        labelText: labelText,
        hintStyle: hintStyle,
        prefixIcon: prefixIcon,
        suffixIcon: suffixIcon,
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Color(0xffc9cdd1)), // gray4
          borderRadius: BorderRadius.circular(8),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: kMainColor, width: 2),
          borderRadius: BorderRadius.circular(8),
        ),
      );

  // ─── KDS 카드 버튼 스타일 ──────────────────────────────────────────────────

  /// KDS 카드 하단 주 액션 버튼 (접수/완료 등)
  static ButtonStyle kdsCardPrimaryButton() => ElevatedButton.styleFrom(
        backgroundColor: kMainColor,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.bSm),
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s16,
          vertical: AppSpacing.s8,
        ),
      );

  /// KDS 카드 하단 보조 액션 버튼 (취소 등)
  static ButtonStyle kdsCardSecondaryButton() => ElevatedButton.styleFrom(
        backgroundColor: gray2,
        foregroundColor: gray9,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.bSm),
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s16,
          vertical: AppSpacing.s8,
        ),
      );

  // ─── 주문 카드 상태 색상 (SSOT) ───────────────────────────────────────────

  /// 주문 유형·상태에 따른 카드 배경·전경 색 페어를 반환한다 (단일 진실 공급원).
  ///
  /// - [type]: 매장/포장/매장+포장 구분
  /// - [isCancelled]: true면 [type]을 무시하고 빨강 계열 반환
  /// - [muted]: KDS 픽업·완료 탭처럼 bg를 중성(gray2)으로 고정하되 fg는 유지
  static OrderPalette orderPalette(
    SpecialProductType type, {
    bool isCancelled = false,
    bool muted = false,
  }) {
    if (isCancelled) {
      return const OrderPalette(kRedAlpha, kRed);
    }
    final fg = switch (type) {
      SpecialProductType.dineIn => kSub,
      SpecialProductType.takeout => kBlue,
      SpecialProductType.both => gray9,
      SpecialProductType.none => kBlue,
    };
    if (muted) return OrderPalette(gray2, fg);
    final bg = switch (type) {
      SpecialProductType.dineIn => kSubAlpha,
      SpecialProductType.takeout => kBlueAlpha,
      SpecialProductType.both => gray2,
      SpecialProductType.none => kBlueAlpha,
    };
    return OrderPalette(bg, fg);
  }

  /// 주문 상태(OrderStatus)별 배경·전경 색 페어 (단일 진실 공급원).
  ///
  /// 상태별 배지·인디케이터·하이라이트 등 전역에서 재사용한다.
  /// - NEW: 핑크(주목 필요)
  /// - PREPARING: 파랑(진행 중)
  /// - READY: 앰버(픽업 대기)
  /// - DONE: 그린(완료)
  /// - CANCELLED: 레드(취소)
  static OrderPalette statusPalette(OrderStatus status) {
    switch (status) {
      case OrderStatus.NEW:
        return const OrderPalette(kMainColorAlpha, kMainColor);
      case OrderStatus.PREPARING:
        return const OrderPalette(kBlueAlpha, kBlue);
      case OrderStatus.READY:
        return const OrderPalette(kAmberAlpha, kAmber);
      case OrderStatus.DONE:
        return const OrderPalette(green100Alpha, green100);
      case OrderStatus.CANCELLED:
        return const OrderPalette(kRedAlpha, kRed);
    }
  }
}

/// 주문 카드에서 사용하는 배경(bg)·전경(fg) 색 페어.
class OrderPalette {
  final Color bg;
  final Color fg;
  const OrderPalette(this.bg, this.fg);
}
