// 브랜드 영수증 로고(receipt_logo.png) 정규화 생성기.
//
// docs/BRAND_ASSETS.md 4.2 의 표준 사양을 그대로 구현한다:
//   - 투명 배경을 흰색으로 평탄화(알파 제거) — 영수증은 흰 종이에 찍힌다
//   - 높이 80px / 폭 384도트(58mm 용지) 박스에 비율 유지로 fit
//   - 8-bit PNG 저장
//
// 앱은 영수증 로고를 리사이즈하지 않는다(1픽셀 = 1도트). 즉 여기서 만든 픽셀 크기가
// 그대로 인쇄 도트 크기가 된다. 또 ESC/POS 래스터화(receipt_escpos_builder.dart
// addImageRaster)는 gray < 128 하드 임계값으로 1비트화하므로(디더링 없음),
// 축소 후 획이 끊기는지 확인할 수 있도록 1비트 프리뷰 PNG 를 함께 낸다.
//
// 실행:
//   dart run tool/gen_receipt_logo.dart --src=/path/to/logo.png --slug=mammoth
//
// docs 의 PIL 스크립트와 동등하지만, Windows 개발 머신에는 python/PIL 이 없으므로
// 이 Dart 스크립트를 정본으로 쓴다.
//
// image 는 flutter_launcher_icons 의 전이 의존성이라 직접 의존성 선언 없이 사용한다.
// ignore_for_file: depend_on_referenced_packages, avoid_print
import 'dart:io';

import 'package:image/image.dart' as img;

const targetHeight = 80; // 표준 높이
const maxWidth = 384; // 58mm 용지 도트 폭

String? _arg(List<String> args, String name) {
  final prefix = '--$name=';
  for (final a in args) {
    if (a.startsWith(prefix)) return a.substring(prefix.length);
  }
  return null;
}

void main(List<String> args) {
  final srcPath = _arg(args, 'src');
  final slug = _arg(args, 'slug');
  if (srcPath == null || slug == null) {
    stderr.writeln(
      'usage: dart run tool/gen_receipt_logo.dart --src=<원본 PNG> --slug=<브랜드 slug>',
    );
    exit(64);
  }

  final srcFile = File(srcPath);
  if (!srcFile.existsSync()) {
    stderr.writeln('원본 파일 없음: $srcPath');
    exit(66);
  }

  final src = img.decodePng(srcFile.readAsBytesSync());
  if (src == null) {
    stderr.writeln('PNG 디코드 실패: $srcPath');
    exit(65);
  }

  // 흰 종이 위에 평탄화 → 알파 제거(RGB).
  final canvas = img.Image(
    width: src.width,
    height: src.height,
    numChannels: 4,
  );
  img.fill(canvas, color: img.ColorRgba8(255, 255, 255, 255));
  img.compositeImage(canvas, src);
  final flat = canvas.convert(numChannels: 3);

  // 80x384 박스 fit (비율 유지).
  final scale = [
    targetHeight / flat.height,
    maxWidth / flat.width,
  ].reduce((a, b) => a < b ? a : b);
  final outWidth = (flat.width * scale).round().clamp(1, maxWidth);
  final outHeight = (flat.height * scale).round().clamp(1, targetHeight);
  final out = img.copyResize(
    flat,
    width: outWidth,
    height: outHeight,
    interpolation: img.Interpolation.cubic,
  );

  final dstPath = 'assets/images/brand/$slug/receipt_logo.png';
  final dstFile = File(dstPath)..parent.createSync(recursive: true);
  dstFile.writeAsBytesSync(img.encodePng(out));

  // 프린터 1비트화 시뮬레이션 — receipt_escpos_builder.dart addImageRaster 와 동일 로직.
  final preview = img.Image(width: out.width, height: out.height);
  var black = 0;
  for (var y = 0; y < out.height; y++) {
    for (var x = 0; x < out.width; x++) {
      final p = out.getPixel(x, y);
      final gray = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
      final isBlack = gray < 128;
      if (isBlack) black++;
      final v = isBlack ? 0 : 255;
      preview.setPixelRgb(x, y, v, v, v);
    }
  }
  const previewPath = 'build/receipt_logo_1bit_preview.png';
  final previewFile = File(previewPath)..parent.createSync(recursive: true);
  previewFile.writeAsBytesSync(img.encodePng(preview));

  final total = out.width * out.height;
  print('src     : ${src.width}x${src.height} -> ${out.width}x${out.height}');
  print('dst     : $dstPath (${dstFile.lengthSync()} B)');
  print('폭<=384 : ${out.width <= maxWidth}');
  print('검정비율: $black/$total (${(black * 100 / total).toStringAsFixed(1)}%)');
  print('1비트 프리뷰(실제 인쇄와 동일): $previewPath');
}
