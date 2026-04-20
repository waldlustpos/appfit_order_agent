import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../constants/app_styles.dart';

/// 활성 브랜드의 로고. [BrandTheme.logoAsset] 이 지정돼 있으면 이미지를,
/// 지정되지 않았으면 [fallbackText] 를 렌더한다.
///
/// `.svg` 에셋은 flutter_svg 로, 그 외(png/jpg)는 Image.asset 으로 로드한다.
class BrandLogo extends StatelessWidget {
  const BrandLogo({
    super.key,
    this.height = 48,
    this.fallbackText = 'AppFit',
    this.fallbackStyle,
  });

  final double height;
  final String fallbackText;
  final TextStyle? fallbackStyle;

  @override
  Widget build(BuildContext context) {
    final asset = AppStyles.activeBrand.logoAsset;
    if (asset == null) {
      return Text(fallbackText, style: fallbackStyle);
    }
    if (asset.toLowerCase().endsWith('.svg')) {
      return SvgPicture.asset(
        asset,
        height: height,
        fit: BoxFit.contain,
        placeholderBuilder: (_) => Text(fallbackText, style: fallbackStyle),
      );
    }
    return Image.asset(
      asset,
      height: height,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Text(fallbackText, style: fallbackStyle),
    );
  }
}
