// 라벨 이미지의 RGBA → 이진화 → 24-bit BMP 변환 (순수 Dart, 의존성 없음).
//
// BIXOLON BXLLAPI 의 이미지 인쇄는 파일 경로 전용(PrintImageLibW)이라
// 메모리의 라벨 이미지를 임시 BMP 파일로 내려야 한다. SDK 의 자체
// 이진화(dither/level)는 Android 실기기에서 임계가 낮게 동작해 AA 얇은
// 글자·회색 요소가 소실되는 것이 확인됐으므로(project_bixolon_xd5_40d),
// 여기서 결정론적으로 이진화(임계 210)한 순흑/순백 픽셀을 만들고 SDK 에는
// DITHER_NONE 으로 넘긴다.

import 'dart:typed_data';

/// RGBA 픽셀 버퍼를 순흑(0,0,0)/순백(255,255,255)으로 이진화한다 (in-place 아님).
///
/// Android BixolonLabelDriver.binarizeForPrint 의 포팅:
/// - 알파 < 255 픽셀은 흰 배경에 합성 후 판정 (painter 가 흰 배경을 먼저
///   칠하므로 방어용).
/// - BT.601 luminance `(r*299 + g*587 + b*114) / 1000` < [threshold] → 검정.
Uint8List binarizeRgba(Uint8List rgba, {required int threshold}) {
  final out = Uint8List(rgba.length);
  for (int i = 0; i + 3 < rgba.length; i += 4) {
    int r = rgba[i];
    int g = rgba[i + 1];
    int b = rgba[i + 2];
    final a = rgba[i + 3];
    if (a < 255) {
      r = (r * a + 255 * (255 - a)) ~/ 255;
      g = (g * a + 255 * (255 - a)) ~/ 255;
      b = (b * a + 255 * (255 - a)) ~/ 255;
    }
    final lum = (r * 299 + g * 587 + b * 114) ~/ 1000;
    final v = (lum < threshold) ? 0 : 255;
    out[i] = v;
    out[i + 1] = v;
    out[i + 2] = v;
    out[i + 3] = 255;
  }
  return out;
}

/// RGBA 버퍼를 24-bit 무압축 BMP(BI_RGB) 바이트로 인코딩한다.
///
/// - 행 stride 는 4바이트 정렬: `(width*3 + 3) & ~3` (490폭 → 1472).
/// - `biHeight` 양수 = bottom-up: 픽셀 행을 아래에서 위로 기록.
/// - 픽셀 바이트 순서는 BGR, 패딩 바이트는 0.
/// - 해상도 필드는 203dpi ≈ 7992 px/m (표기용).
Uint8List encodeBmp24(Uint8List rgba, int width, int height) {
  assert(rgba.length >= width * height * 4, 'rgba buffer too small');
  const int headerSize = 14 + 40; // BITMAPFILEHEADER + BITMAPINFOHEADER
  final int stride = (width * 3 + 3) & ~3;
  final int imageSize = stride * height;
  final int fileSize = headerSize + imageSize;

  final bytes = Uint8List(fileSize);
  final bd = ByteData.sublistView(bytes);

  // BITMAPFILEHEADER (14B)
  bytes[0] = 0x42; // 'B'
  bytes[1] = 0x4D; // 'M'
  bd.setUint32(2, fileSize, Endian.little);
  bd.setUint32(6, 0, Endian.little); // reserved
  bd.setUint32(10, headerSize, Endian.little); // bfOffBits

  // BITMAPINFOHEADER (40B)
  bd.setUint32(14, 40, Endian.little); // biSize
  bd.setInt32(18, width, Endian.little);
  bd.setInt32(22, height, Endian.little); // 양수 = bottom-up
  bd.setUint16(26, 1, Endian.little); // biPlanes
  bd.setUint16(28, 24, Endian.little); // biBitCount
  bd.setUint32(30, 0, Endian.little); // BI_RGB
  bd.setUint32(34, imageSize, Endian.little);
  bd.setInt32(38, 7992, Endian.little); // biXPelsPerMeter (203dpi)
  bd.setInt32(42, 7992, Endian.little); // biYPelsPerMeter
  bd.setUint32(46, 0, Endian.little); // biClrUsed
  bd.setUint32(50, 0, Endian.little); // biClrImportant

  // 픽셀 데이터: bottom-up + BGR
  for (int row = 0; row < height; row++) {
    final srcRow = height - 1 - row;
    int dst = headerSize + row * stride;
    int src = srcRow * width * 4;
    for (int x = 0; x < width; x++) {
      bytes[dst] = rgba[src + 2]; // B
      bytes[dst + 1] = rgba[src + 1]; // G
      bytes[dst + 2] = rgba[src]; // R
      dst += 3;
      src += 4;
    }
    // stride 잔여분은 Uint8List 초기값 0 그대로 = 패딩.
  }
  return bytes;
}
