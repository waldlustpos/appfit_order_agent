import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:appfit_order_agent/services/label_printer/windows/g30_escpos_raster.dart';

/// `encodeG30RasterFromRgba` 는 순수 함수라 Windows/`dart:ui` 없이 검증된다.
/// (PNG 디코드를 하는 `encodeG30Label` 은 `dart:ui` 가 필요해 여기서는 다루지 않는다.)
void main() {
  /// 모든 픽셀이 같은 회색인 RGBA 버퍼.
  Uint8List solid(int w, int h, int level, {int alpha = 255}) {
    final buf = Uint8List(w * h * 4);
    for (int i = 0; i < w * h; i++) {
      buf[i * 4] = level;
      buf[i * 4 + 1] = level;
      buf[i * 4 + 2] = level;
      buf[i * 4 + 3] = alpha;
    }
    return buf;
  }

  /// `GS v 0` 블록의 시작 오프셋들.
  List<int> rasterHeaderOffsets(Uint8List bytes) {
    final offsets = <int>[];
    for (int i = 0; i + 3 < bytes.length; i++) {
      if (bytes[i] == 0x1D &&
          bytes[i + 1] == 0x76 &&
          bytes[i + 2] == 0x30 &&
          bytes[i + 3] == 0x00) {
        offsets.add(i);
      }
    }
    return offsets;
  }

  group('문서 골격', () {
    test('ESC @ 로 시작하고 GS V 66 0 (partial cut) 으로 끝난다', () {
      final out = encodeG30RasterFromRgba(
          rgba: solid(8, 4, 255), width: 8, height: 4);

      expect(out.sublist(0, 2), [0x1B, 0x40]);
      expect(out.sublist(out.length - 4), [0x1D, 0x56, 0x42, 0x00]);
    });

    test('GS v 0 헤더의 xL/xH 는 byteWidth = (w+7)~/8 이다', () {
      // 412dot = G30 58mm 연속용지의 실효 인쇄폭 → 52 byte
      final out = encodeG30RasterFromRgba(
          rgba: solid(412, 10, 255), width: 412, height: 10);

      final at = rasterHeaderOffsets(out).single;
      expect(out[at + 4], 52); // xL
      expect(out[at + 5], 0); // xH
      expect(out[at + 6], 10); // yL
      expect(out[at + 7], 0); // yH
    });

    test('byteWidth/행수가 255 를 넘으면 상위 바이트로 넘어간다', () {
      // 폭 2048dot → byteWidth 256 = xL 0 / xH 1
      final out = encodeG30RasterFromRgba(
          rgba: solid(2048, 300, 255),
          width: 2048,
          height: 300,
          bandRows: 300);

      final at = rasterHeaderOffsets(out).single;
      expect(out[at + 4], 0); // xL
      expect(out[at + 5], 1); // xH
      expect(out[at + 6], 44); // yL  (300 & 0xFF)
      expect(out[at + 7], 1); // yH  (300 >> 8)
    });
  });

  group('이진화 임계 210', () {
    test('209 는 검정 비트, 211 은 흰 비트', () {
      // luminance = (r*299 + g*587 + b*114) / 1000 — 무채색이면 그 값 그대로.
      final dark = encodeG30RasterFromRgba(
          rgba: solid(8, 1, 209), width: 8, height: 1);
      final light = encodeG30RasterFromRgba(
          rgba: solid(8, 1, 211), width: 8, height: 1);

      final darkAt = rasterHeaderOffsets(dark).single;
      final lightAt = rasterHeaderOffsets(light).single;

      expect(dark[darkAt + 8], 0xFF, reason: '209 < 210 → 8픽셀 전부 검정');
      expect(light[lightAt + 8], 0x00, reason: '211 >= 210 → 8픽셀 전부 흰색');
    });

    test('임계 자체(210)는 흰색 쪽이다', () {
      final out = encodeG30RasterFromRgba(
          rgba: solid(8, 1, 210), width: 8, height: 1);
      expect(out[rasterHeaderOffsets(out).single + 8], 0x00);
    });
  });

  group('픽셀 패킹', () {
    test('MSB-first — 첫 픽셀이 0x80 비트다', () {
      final rgba = solid(8, 1, 255);
      rgba[0] = 0; // x=0 픽셀만 검정 (R/G/B)
      rgba[1] = 0;
      rgba[2] = 0;

      final out =
          encodeG30RasterFromRgba(rgba: rgba, width: 8, height: 1);
      expect(out[rasterHeaderOffsets(out).single + 8], 0x80);
    });

    test('폭이 8의 배수가 아니면 행 끝을 흰색으로 패딩한다', () {
      // 4dot 폭이면 byteWidth 1, 하위 4비트는 항상 0.
      final out = encodeG30RasterFromRgba(
          rgba: solid(4, 1, 0), width: 4, height: 1);

      final at = rasterHeaderOffsets(out).single;
      expect(out[at + 4], 1, reason: 'byteWidth = (4+7)~/8 = 1');
      expect(out[at + 8], 0xF0, reason: '앞 4비트만 검정, 패딩은 흰색');
    });

    test('투명 픽셀은 흰 배경에 합성된다 (전면 반전 방지)', () {
      // alpha 0 인 검정 = 흰색으로 읽혀야 한다. 알파를 무시하면 0xFF 가 된다.
      final out = encodeG30RasterFromRgba(
          rgba: solid(8, 1, 0, alpha: 0), width: 8, height: 1);
      expect(out[rasterHeaderOffsets(out).single + 8], 0x00);
    });
  });

  group('밴드 분할', () {
    test('밴드 경계마다 GS v 0 블록이 하나씩 생긴다', () {
      final out = encodeG30RasterFromRgba(
        rgba: solid(8, 300, 255),
        width: 8,
        height: 300,
        bandRows: 128,
      );
      // 300 = 128 + 128 + 44
      final offsets = rasterHeaderOffsets(out);
      expect(offsets.length, 3);
      expect(out[offsets[0] + 6], 128);
      expect(out[offsets[1] + 6], 128);
      expect(out[offsets[2] + 6], 44);
    });

    test('기본 밴드(256행)에서 58mm 최대 라벨(800행)은 4블록이다', () {
      final out = encodeG30RasterFromRgba(
          rgba: solid(412, 800, 255), width: 412, height: 800);
      expect(rasterHeaderOffsets(out).length, 4); // 256*3 + 32
    });

    test('밴드가 높이보다 크면 단일 블록이다', () {
      final out = encodeG30RasterFromRgba(
          rgba: solid(8, 10, 255), width: 8, height: 10, bandRows: 256);
      expect(rasterHeaderOffsets(out).length, 1);
    });

    test('분할해도 픽셀 데이터 총량은 byteWidth * height 이다', () {
      const w = 412, h = 300;
      final out = encodeG30RasterFromRgba(
          rgba: solid(w, h, 0), width: w, height: h, bandRows: 128);

      const byteWidth = (w + 7) ~/ 8;
      final blocks = rasterHeaderOffsets(out).length;
      // ESC @ (2) + 블록당 헤더 8 + 픽셀 전체 + cut (4)
      expect(out.length, 2 + blocks * 8 + byteWidth * h + 4);
    });
  });

  group('입력 검증', () {
    test('치수가 0 이하면 ArgumentError', () {
      expect(() => encodeG30RasterFromRgba(rgba: Uint8List(0), width: 0, height: 1),
          throwsArgumentError);
      expect(() => encodeG30RasterFromRgba(rgba: Uint8List(0), width: 1, height: 0),
          throwsArgumentError);
    });

    test('버퍼가 치수보다 짧으면 ArgumentError', () {
      expect(
        () => encodeG30RasterFromRgba(
            rgba: solid(8, 1, 255), width: 8, height: 2),
        throwsArgumentError,
      );
    });
  });
}
