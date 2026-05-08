// autoreplyprint SDK enum / 비트마스크 상수.
// 헤더(autoreplyprint.h) 의 정의를 그대로 미러링.
// 원본: external/autoreplyprint/win64/autoreplyprint.h

/// `CP_ImagePixelsFormat` (header line 117-127).
class CpImagePixelsFormat {
  static const int mono = 1;
  static const int monoLsb = 2;
  static const int gray8 = 3;
  static const int byteOrderedRgb24 = 4;
  static const int byteOrderedBgr24 = 5;
  static const int byteOrderedArgb32 = 6;
  static const int byteOrderedRgba32 = 7;
  static const int byteOrderedAbgr32 = 8;
  static const int byteOrderedBgra32 = 9;
}

/// `CP_ImageBinarizationMethod` (header line 111).
class CpImageBinarization {
  static const int dithering = 0;
  static const int thresholding = 1;
  static const int errorDiffusion = 2;
}

/// `CP_ImageCompressionMethod` (header line 114).
class CpImageCompression {
  static const int none = 0;
  static const int level1 = 1;
  static const int level2 = 2;
}

/// `CP_Label_Rotation` (header line 204).
class CpLabelRotation {
  static const int rot0 = 0;
  static const int rot90 = 1;
  static const int rot180 = 2;
  static const int rot270 = 3;
}

/// `CP_PRINTERSTATUS_ERROR_*` 비트마스크 (header line 243-251).
class CpPrinterErrorBits {
  static const int cutter = 0x01;
  static const int flash = 0x02;
  static const int noPaper = 0x04;
  static const int voltage = 0x08;
  static const int marker = 0x10;
  static const int engine = 0x20;
  static const int overheat = 0x40;
  static const int coverUp = 0x80;
  static const int motor = 0x100;
}

/// `CP_PRINTERSTATUS_INFO_*` 비트마스크 (header line 252-258).
class CpPrinterInfoBits {
  static const int labelPaper = 0x02;
  static const int labelMode = 0x04;
  static const int haveData = 0x08;
  static const int noPaperCanceled = 0x10;
  static const int paperNoFetch = 0x20;
  static const int printIdle = 0x40;
  static const int recvIdle = 0x80;
}

/// `autoreplymode` 매개변수 (header line 492-494, 529-531, ...).
class CpAutoReplyMode {
  static const int disabled = 0;
  static const int enabled = 1;
}
