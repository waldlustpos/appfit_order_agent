import 'dart:ffi';
import 'dart:typed_data';

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
  ///
  /// 컬럼 패딩의 정본 폭 측정. [ReceiptEscPosBuilder.runeWidth] 가 rune 단위로 호출해
  /// 캐싱한다. 패딩/정렬 헬퍼를 여기 두지 않는 이유: 폭 계산 로직이 두 벌 공존하면
  /// 한쪽만 고쳐져 컬럼이 어긋난다 (실제로 그랬다). 정본은 ReceiptEscPosBuilder 하나.
  static int cp949ByteLength(String s) => encodeCp949(s).length;
}
