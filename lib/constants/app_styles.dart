import 'package:flutter/material.dart';

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
}
