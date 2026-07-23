import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:appfit_order_agent/services/label_printer/windows/label_bmp_converter.dart';

Uint8List _rgbaOf(List<List<int>> pixels) {
  final out = Uint8List(pixels.length * 4);
  for (int i = 0; i < pixels.length; i++) {
    out[i * 4] = pixels[i][0];
    out[i * 4 + 1] = pixels[i][1];
    out[i * 4 + 2] = pixels[i][2];
    out[i * 4 + 3] = pixels[i][3];
  }
  return out;
}

void main() {
  group('binarizeRgba', () {
    test('임계 210: black26 합성 회색(≈189)은 검정, 밝은 회색(211+)은 흰색', () {
      final rgba = _rgbaOf([
        [189, 189, 189, 255], // black26 on white — 반드시 검정으로 살아야 함
        [211, 211, 211, 255], // 임계 이상 — 흰색
        [0, 0, 0, 255], // 순흑
        [255, 255, 255, 255], // 순백
      ]);
      final out = binarizeRgba(rgba, threshold: 210);
      expect(out.sublist(0, 3), [0, 0, 0]);
      expect(out.sublist(4, 7), [255, 255, 255]);
      expect(out.sublist(8, 11), [0, 0, 0]);
      expect(out.sublist(12, 15), [255, 255, 255]);
      // 알파는 항상 255 로 고정
      expect([out[3], out[7], out[11], out[15]], [255, 255, 255, 255]);
    });

    test('반투명 픽셀은 흰 배경 합성 후 판정 (검정 26% 알파 ≈189 → 검정)', () {
      // Colors.black26 원본 표현: 검정 + 알파 66 (0x42)
      final rgba = _rgbaOf([
        [0, 0, 0, 66], // 합성 시 255*(255-66)/255 ≈ 189 → 검정
        [0, 0, 0, 20], // 합성 시 ≈235 → 흰색
        [0, 0, 0, 0], // 완전 투명 → 흰색
      ]);
      final out = binarizeRgba(rgba, threshold: 210);
      expect(out.sublist(0, 3), [0, 0, 0]);
      expect(out.sublist(4, 7), [255, 255, 255]);
      expect(out.sublist(8, 11), [255, 255, 255]);
    });
  });

  group('encodeBmp24', () {
    test('헤더 필드: 매직/파일크기/오프셋/치수/24bpp/BI_RGB', () {
      const w = 490, h = 600;
      final rgba = Uint8List(w * h * 4);
      final bmp = encodeBmp24(rgba, w, h);
      final bd = ByteData.sublistView(bmp);

      const stride = 1472; // (490*3 + 3) & ~3
      const fileSize = 54 + stride * h;

      expect(bmp[0], 0x42); // 'B'
      expect(bmp[1], 0x4D); // 'M'
      expect(bmp.length, fileSize);
      expect(bd.getUint32(2, Endian.little), fileSize);
      expect(bd.getUint32(10, Endian.little), 54); // bfOffBits
      expect(bd.getUint32(14, Endian.little), 40); // biSize
      expect(bd.getInt32(18, Endian.little), w);
      expect(bd.getInt32(22, Endian.little), h); // 양수 = bottom-up
      expect(bd.getUint16(26, Endian.little), 1); // planes
      expect(bd.getUint16(28, Endian.little), 24); // bpp
      expect(bd.getUint32(30, Endian.little), 0); // BI_RGB
      expect(bd.getUint32(34, Endian.little), stride * h);
    });

    test('bottom-up 행 순서 + BGR + stride 패딩', () {
      // 2x2: 좌상 빨강, 우상 초록, 좌하 파랑, 우하 흰색
      const w = 2, h = 2;
      final rgba = _rgbaOf([
        [255, 0, 0, 255], // (0,0) 빨강
        [0, 255, 0, 255], // (1,0) 초록
        [0, 0, 255, 255], // (0,1) 파랑
        [255, 255, 255, 255], // (1,1) 흰색
      ]);
      final bmp = encodeBmp24(rgba, w, h);
      const stride = 8; // (2*3 + 3) & ~3

      // 첫 데이터 행 = 이미지 마지막 행 (bottom-up): 파랑, 흰색
      expect(bmp.sublist(54, 54 + 3), [255, 0, 0]); // 파랑 → BGR(255,0,0)
      expect(bmp.sublist(57, 60), [255, 255, 255]);
      // stride 패딩 2바이트 = 0
      expect(bmp.sublist(60, 62), [0, 0]);
      // 두 번째 데이터 행 = 이미지 첫 행: 빨강, 초록
      expect(
          bmp.sublist(54 + stride, 54 + stride + 3), [0, 0, 255]); // 빨강 → BGR
      expect(bmp.sublist(54 + stride + 3, 54 + stride + 6), [0, 255, 0]);
    });
  });
}
