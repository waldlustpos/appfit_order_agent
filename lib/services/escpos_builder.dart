import 'dart:ffi';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// ESC/POS 명령 상수 + Windows(CP949) 텍스트 인코딩 유틸.
///
/// 기존 Android `PrintUtil.java` 의 바이트 시퀀스와 1:1 대응한다.
/// CP949 는 EUC-KR 슈퍼셋이므로 프린터가 EUC-KR 모드여도 호환된다.
class EscPos {
  // ---- font size ----
  // GS ! n 비트 정의는 ESC/POS 표준 그대로 따르되, 이 코드의 운영 환경에서 검증된
  // 의미 매핑은 kokonut_order_agent_v2 와 동일하다 — fontTall 이 height 2x.
  static const int fontNormal = 0x00;
  static const int fontLarge = 0x11; // both 2x
  static const int fontTall = 0x01; // height 2x only
  static const int fontWide = 0x10; // width 2x only

  // ---- alignment ----
  static const int alignLeft = 0x00;
  static const int alignCenter = 0x01;
  static const int alignRight = 0x02;

  // ---- simple commands ----
  static const List<int> init = [0x1B, 0x40];
  static const List<int> lf = [0x0A];
  static const List<int> cutPaper = [0x1D, 0x56, 0x42, 0x00];
  static const List<int> boldOn = [0x1B, 0x45, 0x01];
  static const List<int> boldOff = [0x1B, 0x45, 0x00];
  static const List<int> underlineOff = [0x1B, 0x2D, 0x00];

  static List<int> setSize(int sizeMode) => [0x1D, 0x21, sizeMode];
  static List<int> setAlign(int align) => [0x1B, 0x61, align];

  // ---- CP949 (EUC-KR 호환) 인코딩 via WideCharToMultiByte ----

  /// UTF-16 유니코드 문자열 → CP949 바이트.
  /// Windows 가 아닌 환경에서는 `UnsupportedError`.
  static Uint8List encodeCp949(String s) {
    if (s.isEmpty) return Uint8List(0);
    const codePage = 949;

    final wide = s.toNativeUtf16();
    final wideLen = s.length;
    try {
      final needed = WideCharToMultiByte(
        codePage,
        0,
        wide,
        wideLen,
        nullptr,
        0,
        nullptr,
        nullptr,
      );
      if (needed <= 0) return Uint8List(0);
      final buf = calloc<Uint8>(needed);
      try {
        WideCharToMultiByte(
          codePage,
          0,
          wide,
          wideLen,
          buf.cast(),
          needed,
          nullptr,
          nullptr,
        );
        return Uint8List.fromList(buf.asTypedList(needed));
      } finally {
        calloc.free(buf);
      }
    } finally {
      calloc.free(wide);
    }
  }

  /// `text.getBytes("EUC-KR").length` 와 동일한 결과.
  static int cp949ByteLength(String s) => encodeCp949(s).length;

  /// PrintUtil.java 의 `padRight` 와 동일. 바이트 길이 기준으로 공백 채움.
  static String padRight(String text, int totalWidth) {
    final need = totalWidth - cp949ByteLength(text);
    if (need <= 0) return text;
    return text + ' ' * need;
  }

  /// PrintUtil.java 의 `padLeft` 와 동일.
  static String padLeft(String text, int totalWidth) {
    final need = totalWidth - cp949ByteLength(text);
    if (need <= 0) return text;
    return ' ' * need + text;
  }

  /// 하이픈 라인. `getSeparatorLine(42)` 등.
  static String separatorLine(int width) => '-' * width;
}

/// ESC/POS 명령 스트림을 점진적으로 빌드하는 헬퍼.
class EscPosStreamBuilder {
  final BytesBuilder _bb = BytesBuilder();

  void add(List<int> bytes) => _bb.add(bytes);

  /// 한글 포함 문자열을 CP949 로 인코딩해서 append.
  void text(String s) => _bb.add(EscPos.encodeCp949(s));

  void textLn(String s) {
    text(s);
    _bb.add(EscPos.lf);
  }

  void ln() => _bb.add(EscPos.lf);

  void setSize(int sizeMode) => _bb.add(EscPos.setSize(sizeMode));
  void setAlign(int align) => _bb.add(EscPos.setAlign(align));
  void boldOn() => _bb.add(EscPos.boldOn);
  void boldOff() => _bb.add(EscPos.boldOff);
  void init() => _bb.add(EscPos.init);
  void cut() => _bb.add(EscPos.cutPaper);

  Uint8List build() => _bb.toBytes();

  /// PNG/이미지 바이트를 ESC/POS 래스터 비트맵으로 변환하여 추가.
  /// RGBA → 그레이스케일 → 1비트 → GS v 0 명령
  Future<void> addImageRaster(Uint8List imageBytes) async {
    try {
      final codec = await ui.instantiateImageCodec(imageBytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;

      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) return;

      final rgba = byteData.buffer.asUint8List();
      final width = image.width;
      final height = image.height;
      final byteWidth = (width + 7) ~/ 8;

      final bitData = Uint8List(byteWidth * height);
      int byteIndex = 0;
      int bitInByte = 0;

      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final pixelIndex = ((y * width) + x) * 4;
          final r = rgba[pixelIndex];
          final g = rgba[pixelIndex + 1];
          final b = rgba[pixelIndex + 2];

          final gray = ((0.299 * r + 0.587 * g + 0.114 * b).toInt());
          final bit = (gray < 128) ? 1 : 0;

          if (bit == 1) {
            bitData[byteIndex] |= (0x80 >> bitInByte);
          }

          bitInByte++;
          if (bitInByte == 8) {
            bitInByte = 0;
            byteIndex++;
          }
        }
        if (bitInByte != 0) {
          byteIndex++;
          bitInByte = 0;
        }
      }

      final xL = (byteWidth & 0xFF);
      final xH = ((byteWidth >> 8) & 0xFF);
      final yL = (height & 0xFF);
      final yH = ((height >> 8) & 0xFF);

      _bb.add([0x1D, 0x76, 0x30, 0x00, xL, xH, yL, yH]);
      _bb.add(bitData);

      image.dispose();
    } catch (e) {
      // 비트맵 로딩 실패 시 무시하고 계속 출력
    }
  }
}
