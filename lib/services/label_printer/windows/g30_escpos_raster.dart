/// BIXOLON G30 Windows 전송용 ESC/POS 래스터 인코더.
///
/// G30 은 Android 에서 UPOS/JavaPOS(`POSPrinter.printBitmap`)로 구동되지만 Windows
/// 에는 그 서비스 계층이 없다. 대신 G30 이 usbprint 로 잡히고 ESC/POS 를 그대로
/// 받는다는 점을 이용해, 여기서 완성된 바이트열을 만들고
/// `UsbPrintService.sendRaw` 가 devnode 로 직접 써 넣는다.
///
/// ## 이 파일의 제약 — win32/ffi 의존 0
///
/// 이 인코더는 `windows_label_router` ← `print_service` 경유로 **Android import
/// 그래프에서 도달 가능**하다. `package:win32` 를 top-level 로 import 하는 파일을
/// 여기서 참조하면 Android 에서 kernel32.dll lookup 크래시가 난다. 그래서
/// [_escInit] / [_escCutPartial] 은 `EscPos.init` / `EscPos.cutPaper` 와 값이
/// 같지만 **일부러 로컬 상수로 복제**했다 — `escpos_builder.dart` 가 win32 를
/// 끌고 오기 때문이다. 두 값이 갈라지면 안 되므로 출처를 여기 남긴다.
///
/// ## `dart:ui` 를 쓰지 않는다
///
/// PNG 디코드는 호출부(`bixolon_g30_windows_backend.dart`)가 하고 여기는 RGBA 를
/// 받는다. 덕분에 이 파일은 Flutter 엔진 없이 **standalone `dart run` 에서도**
/// 임포트된다 — `tool/g30_windows_probe.dart` 가 실기기 검증용으로 그렇게 쓴다.
///
/// 순수 함수라서 Windows 없이 단위 테스트할 수 있다.
library;

import 'dart:typed_data';

/// 사전 이진화 임계값. Android `BixolonPosDriver.BINARIZE_THRESHOLD` 와 **같은 값**이다.
///
/// SDK 자체 이진화는 임계가 낮게 동작해 안티에일리어싱으로 회색이 된 얇은 글자·
/// 1px 구분선·black26(≈189)이 소실된다. 그래서 Android 는 Java 에서 결정론적으로
/// 이진화했고, Windows 도 같은 임계를 써야 두 플랫폼 출력물이 시각적으로 같다.
/// **재유도하지 말 것** — 실기기로 확정된 승계 결론이다.
const int kG30BinarizeThreshold = 210;

/// `GS v 0` 한 블록에 담을 최대 행 수.
///
/// 한 장(412×최대 800dot)을 단일 래스터로 보내면 펌웨어 입력 버퍼를 넘길 수 있어
/// 밴드로 쪼갠다. 밴드 경계는 이미지 내용과 무관하므로 출력물에는 이음매가 없다.
/// 현장에서 대형 라벨이 깨지면 이 값을 낮추는 것이 첫 번째 조정 지점이다.
const int kG30RasterBandRows = 256;

/// ESC @ — 프린터 초기화. (= `EscPos.init`, 위 주석 참조)
const List<int> _escInit = [0x1B, 0x40];

/// GS V 66 0 — feed + partial cut. (= `EscPos.cutPaper`)
///
/// Android 의 UPOS escape `ESC|90fP`(Feed Partial Cut)와 같은 역할이다. G30 은
/// 연속용지라 갭 센서로 장을 나누지 않는다 — **커터가 장 구분의 유일한 수단**이다.
const List<int> _escCutPartial = [0x1D, 0x56, 0x42, 0x00];

/// RGBA 픽셀 버퍼 → G30 이 그대로 받아 인쇄할 ESC/POS 문서.
///
/// 폭/높이는 **호출부가 디코드한 이미지에서 얻은 실제 값**이다.
/// `Continuous58LabelPainter` 는 내용에 따라 높이가 300~800dot 로 달라지므로
/// 상수를 넘기는 방식은 성립하지 않는다(Caysn 경로가 `LabelPainter.width/height`
/// 490×600 을 하드코딩하던 부채가 여기서는 발생하지 않는다).
///
/// 투명 픽셀은 흰 배경에 합성한다 — 라벨 painter 가 배경을 투명으로 남기는
/// 영역이 있고, 그대로 두면 알파를 무시한 RGB 가 검정으로 읽혀 전면 반전된다.
Uint8List encodeG30RasterFromRgba({
  required Uint8List rgba,
  required int width,
  required int height,
  int threshold = kG30BinarizeThreshold,
  int bandRows = kG30RasterBandRows,
}) {
  if (width <= 0 || height <= 0) {
    throw ArgumentError('G30 래스터 치수가 유효하지 않음: ${width}x$height');
  }
  final expected = width * height * 4;
  if (rgba.length < expected) {
    throw ArgumentError(
        'G30 래스터 버퍼 부족: ${rgba.length} < $expected (${width}x$height RGBA)');
  }

  final byteWidth = (width + 7) ~/ 8;
  final out = BytesBuilder();
  out.add(_escInit);

  for (int bandTop = 0; bandTop < height; bandTop += bandRows) {
    final rows =
        (bandTop + bandRows <= height) ? bandRows : (height - bandTop);
    final band = Uint8List(byteWidth * rows);

    for (int y = 0; y < rows; y++) {
      final srcRow = (bandTop + y) * width;
      final dstRow = y * byteWidth;
      for (int x = 0; x < width; x++) {
        final i = (srcRow + x) * 4;
        final a = rgba[i + 3];
        // 알파 합성(흰 배경). a==255 인 일반 경로는 나눗셈 없이 지나간다.
        final int r, g, b;
        if (a == 255) {
          r = rgba[i];
          g = rgba[i + 1];
          b = rgba[i + 2];
        } else {
          final inv = 255 - a;
          r = (rgba[i] * a + 255 * inv) ~/ 255;
          g = (rgba[i + 1] * a + 255 * inv) ~/ 255;
          b = (rgba[i + 2] * a + 255 * inv) ~/ 255;
        }
        // Android BixolonPosDriver.binarizeForPrint 와 같은 정수 luminance.
        final lum = (r * 299 + g * 587 + b * 114) ~/ 1000;
        if (lum < threshold) {
          band[dstRow + (x >> 3)] |= 0x80 >> (x & 7);
        }
      }
    }

    // GS v 0 m xL xH yL yH — m=0 (normal, 배율 없음).
    out.add([
      0x1D,
      0x76,
      0x30,
      0x00,
      byteWidth & 0xFF,
      (byteWidth >> 8) & 0xFF,
      rows & 0xFF,
      (rows >> 8) & 0xFF,
    ]);
    out.add(band);
  }

  out.add(_escCutPartial);
  return out.toBytes();
}
