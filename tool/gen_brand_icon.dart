// Tier 1 브랜드 전용 런처 아이콘 자산 생성기.
//
// 공통 아이콘은 tool/gen_korea_icon.dart 가 담당한다(그라데이션 합성). 이 스크립트는
// **브랜드가 제공한 로고 원본을 색 변형 없이 그대로** 런처 아이콘 규격에 맞춘다.
//
// 브랜드 원본은 대개 대형 여백 캔버스(4500x4500 등)로 오기 때문에 bbox 크롭이
// 선행되어야 한다 — 표준 파이프라인에 자동 크롭이 없어서, 크롭을 빼먹으면 로고가
// 아이콘 한가운데 점처럼 찍힌다 (docs/BRAND_ASSETS.md §4.1).
//
// 산출물 (<slug>=mammoth 기준):
//   assets/icons/app_icon_mammoth.png            - 레거시(비-adaptive) 런처: 흰 배경 + 로고
//   assets/icons/app_icon_mammoth_fg.png         - adaptive 전경: 투명 배경 + 로고
//   windows/runner/resources/app_icon_mammoth.ico - Windows 런처/설치 아이콘(256px)
//
// adaptive 배경은 단색이라 PNG 가 필요 없다 — flutter_launcher_icons-<slug>.yaml 의
// adaptive_icon_background 에 hex 로 준다.
// .ico 는 windows/runner/Runner.rc 의 APPFIT_BRAND_MAMMOTH 분기가 직접 참조하므로
// flutter_launcher_icons 실행과 무관하게 이 스크립트만으로 완성된다
// (tool/gen_korea_icon.dart 의 공통 .ico 생성 패턴과 동일).
//
// 실행:
//   dart run tool/gen_brand_icon.dart mammoth "C:/Users/.../mammoth_icon.png"
// 이후:
//   flutter pub run flutter_launcher_icons -f flutter_launcher_icons-mammoth.yaml
//
// image 는 flutter_launcher_icons 의 전이 의존성이라 직접 의존성 선언 없이 사용한다.
// ignore_for_file: depend_on_referenced_packages
import 'dart:io';

import 'package:image/image.dart' as img;

/// 최종 캔버스 한 변(px). flutter_launcher_icons 가 여기서 각 밀도로 축소한다.
const int kCanvas = 1024;

/// 레거시 아이콘에서 로고가 차지하는 비율. 런처가 자체 마스크를 씌우므로 약간의
/// 여백을 남긴다.
const double kLegacyScale = 0.80;

/// adaptive 전경에서 로고가 차지하는 비율.
///
/// adaptive 아이콘은 108dp 캔버스의 가운데 72dp 만 항상 보이고 바깥은 마스크
/// 모양에 따라 잘린다(= 안전 영역이 약 66%). 워드마크가 포함된 록업은 잘리면
/// 글자가 날아가므로 안전 영역 안쪽으로 넣는다.
///
/// **flutter_launcher_icons 가 생성하는 ic_launcher.xml 이 전경에 `inset="16%"`
/// 를 한 번 더 먹인다**(양쪽 합 32%). 즉 최종 크기는 이 값의 68% 다 — 여기서
/// 안전 영역을 또 빼면 이중 축소가 돼 로고가 점처럼 작아진다.
///
/// 0.80 → 최종 폭 = 0.80 x 0.68 = 캔버스의 54%. 원형 마스크(반지름 33.3%) 기준
/// 이 록업(가로:세로 = 1.5:1)의 바운딩 박스 모서리 거리는 54 x 0.60 = 32.6% 로
/// 마스크 안에 들어온다. 더 키우면 원형 런처에서 워드마크 양끝이 잘린다.
const double kAdaptiveScale = 0.80;

/// 배경으로 간주할 밝기 임계값. 이 값보다 밝고 알파가 불투명한 픽셀은 여백으로
/// 보고 bbox 계산에서 제외한다.
const int kWhiteThreshold = 245;

void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln('사용법: dart run tool/gen_brand_icon.dart <slug> <원본 PNG 경로>');
    stderr.writeln('예:    dart run tool/gen_brand_icon.dart mammoth '
        '"C:/Users/Administrator/Downloads/mammoth_icon.png"');
    exit(64);
  }
  final slug = args[0];
  final srcPath = args[1];

  final srcFile = File(srcPath);
  if (!srcFile.existsSync()) {
    stderr.writeln('원본을 찾을 수 없습니다: $srcPath');
    exit(1);
  }
  final src = img.decodePng(srcFile.readAsBytesSync()) ??
      img.decodeImage(srcFile.readAsBytesSync());
  if (src == null) {
    stderr.writeln('이미지 디코딩 실패: $srcPath');
    exit(1);
  }
  stdout.writeln('원본: ${src.width}x${src.height}, '
      'channels=${src.numChannels}, hasAlpha=${src.hasAlpha}');

  final box = _contentBounds(src);
  if (box == null) {
    stderr.writeln('내용이 없는 이미지입니다(전부 배경으로 판정).');
    exit(1);
  }
  stdout.writeln('내용 bbox: x=${box.x} y=${box.y} '
      'w=${box.width} h=${box.height} '
      '(원본 대비 ${(box.width * 100 / src.width).toStringAsFixed(1)}% x '
      '${(box.height * 100 / src.height).toStringAsFixed(1)}%)');

  // 크롭 + 알파화. 원본 색은 건드리지 않고, 흰 배경만 투명으로 바꾼다.
  final cropped = img.copyCrop(src, x: box.x, y: box.y, width: box.width, height: box.height);
  final logo = _whiteToTransparent(cropped);

  final legacyPath = 'assets/icons/app_icon_$slug.png';
  final foregroundPath = 'assets/icons/app_icon_${slug}_fg.png';
  final windowsIcoPath = 'windows/runner/resources/app_icon_$slug.ico';

  final legacyImage = _place(logo, kLegacyScale, background: _white);
  File(legacyPath).writeAsBytesSync(img.encodePng(legacyImage));
  File(foregroundPath).writeAsBytesSync(
    img.encodePng(_place(logo, kAdaptiveScale, background: null)),
  );

  // Windows 런처/설치 아이콘: 레거시(흰 배경) 합성본을 256px ICO 로 인코딩.
  final ico = img.copyResize(legacyImage, width: 256, height: 256);
  File(windowsIcoPath).writeAsBytesSync(img.encodeIco(ico));

  stdout.writeln('생성 완료:');
  stdout.writeln('  $legacyPath        (레거시 런처, 로고 ${(kLegacyScale * 100).round()}%)');
  stdout.writeln('  $foregroundPath  (adaptive 전경, 로고 ${(kAdaptiveScale * 100).round()}%)');
  stdout.writeln('  $windowsIcoPath (Windows 런처/설치 아이콘, 256px)');
  stdout.writeln('');
  stdout.writeln('다음: flutter pub run flutter_launcher_icons '
      '-f flutter_launcher_icons-$slug.yaml');
  stdout.writeln('확인: git status 로 android/app/src/main/res/mipmap-* 이 '
      '오염되지 않았는지 볼 것 (공통 아이콘이 덮이면 전 함대 회귀).');
}

final _white = img.ColorRgba8(255, 255, 255, 255);

class _Box {
  const _Box(this.x, this.y, this.width, this.height);
  final int x;
  final int y;
  final int width;
  final int height;
}

/// 여백을 제외한 내용 영역. 알파가 있으면 알파 기준, 없으면 흰색 기준으로 판정한다.
_Box? _contentBounds(img.Image im) {
  var minX = im.width, minY = im.height, maxX = -1, maxY = -1;
  for (var y = 0; y < im.height; y++) {
    for (var x = 0; x < im.width; x++) {
      if (_isBackground(im.getPixel(x, y))) continue;
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
    }
  }
  if (maxX < 0) return null;
  return _Box(minX, minY, maxX - minX + 1, maxY - minY + 1);
}

/// 투명하거나(알파 원본), 거의 흰색이면(불투명 원본) 배경으로 본다.
bool _isBackground(img.Pixel p) {
  if (p.a < 8) return true;
  return p.r >= kWhiteThreshold &&
      p.g >= kWhiteThreshold &&
      p.b >= kWhiteThreshold;
}

/// 흰 배경을 투명으로 바꿔 adaptive 전경에 쓸 수 있게 한다. 로고 자체의 색은
/// 그대로 둔다(사용자 지정: 원본 색 유지).
img.Image _whiteToTransparent(img.Image im) {
  final out = im.convert(numChannels: 4);
  for (var y = 0; y < out.height; y++) {
    for (var x = 0; x < out.width; x++) {
      final p = out.getPixel(x, y);
      if (_isBackground(p)) {
        out.setPixelRgba(x, y, 0, 0, 0, 0);
      }
    }
  }
  return out;
}

/// 로고를 정사각 캔버스 가운데에 [scale] 비율로 배치한다. 종횡비는 유지한다.
img.Image _place(img.Image logo, double scale, {img.Color? background}) {
  final canvas = img.Image(width: kCanvas, height: kCanvas, numChannels: 4);
  if (background != null) {
    img.fill(canvas, color: background);
  }

  final target = (kCanvas * scale).round();
  final ratio = logo.width / logo.height;
  final w = ratio >= 1 ? target : (target * ratio).round();
  final h = ratio >= 1 ? (target / ratio).round() : target;

  final resized = img.copyResize(
    logo,
    width: w,
    height: h,
    interpolation: img.Interpolation.cubic,
  );
  img.compositeImage(
    canvas,
    resized,
    dstX: ((kCanvas - w) / 2).round(),
    dstY: ((kCanvas - h) / 2).round(),
  );
  return canvas;
}
