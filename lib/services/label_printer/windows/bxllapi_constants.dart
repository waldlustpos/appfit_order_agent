// BIXOLON Windows Label SDK (BXLLAPI_x64.dll) 상수.
//
// 출처: external/bixolon/win64/BXLLApi.h (V3.10) + VC++ 샘플 SampleProgramDlg.cpp.
// 상태 코드 의미는 샘플 GetStatusMsg 스위치에서 확정.
//
// Android BixolonLabelDriver.java 와 의미론을 공유한다 — 특히 이진화 임계값
// 210 은 Android 실기기 검증값(project_bixolon_xd5_40d 메모리)을 그대로 쓴다.

/// _SLCS_COMMUNICATION_TYPE — ConnectPrinterEx 의 nInterface.
abstract final class BxlInterface {
  static const int usb = 2; // INF_USB — szPortName="" 로 DLL 이 자체 감지
}

/// CheckStatus() / ConnectPrinterEx() 가 반환하는 SLCS_ERROR_CODE.
abstract final class BxlStatus {
  static const int ok = 0;
  static const int noPaper = 1;
  static const int coverOpen = 2;
  static const int cutterJam = 3;
  static const int tphOverheat = 4;
  static const int autoSensing = 5;
  static const int noRibbon = 6;
  static const int powerOff = 7;
  static const int cutterUncabled = 8;
  static const int nowPrinting = 9;
  static const int labelPaused = 10;
  static const int waitLabelTaken = 13;
  static const int makeLabel = 14;
  static const int waitPeeler = 15;
  static const int invalidParam = 60;
  static const int connect = 71;
  static const int getName = 72;
  static const int offline = 73;
  static const int write = 74;
  static const int read = 75;
  static const int unknown = 99;

  /// 운영자 개입(용지 교체/커버 닫기+재개버튼)으로 회복 가능한 상태.
  static const Set<int> recoverable = {noPaper, coverOpen};

  /// 인쇄 진행/라벨 회수 대기류 — 실패가 아니라 무한 대기 대상.
  /// XD5-40d 가 실제로 어느 코드를 쓰는지는 실기기 로그로 확정한다
  /// (Android 는 PAUSED_IN_PEELER 였음 — 회수 전까지 유지).
  static const Set<int> takenWait = {
    nowPrinting,
    labelPaused,
    waitLabelTaken,
    makeLabel,
    waitPeeler,
  };

  /// 연결 자체가 죽은 상태 — 재연결 대상.
  static const Set<int> connDead = {powerOff, connect, getName, offline};
}

/// _SLCS_DITHER_OPTION — PrintImageLibW 의 nDither.
abstract final class BxlDither {
  /// Dart 사전 이진화(순흑/순백)를 쓰므로 SDK 디더링은 항상 끈다.
  static const int none = -1;
}

/// _SLCS_MEDIA_TYPE — SetPaper 의 nMediaType.
abstract final class BxlMediaType {
  static const int gap = 0;
}

/// _SLCS_ORIENTATION — SetConfigOfPrinter 의 nOrientation.
abstract final class BxlOrientation {
  static const int top2bottom = 0;
}

/// SetCharacterset 인자 (샘플 기본값).
abstract final class BxlCharset {
  static const int icsUsa = 0;
  static const int cp1252 = 6;
}

/// SetConfigOfPrinter 의 nSpeed — -1 이면 프린터 보존값 유지.
abstract final class BxlSpeed {
  static const int keepPrinterSetting = -1;
}

// ---------------------------------------------------------------------------
// 라벨 미디어 상수 — Android BixolonLabelDriver 와 동일 값.
// ---------------------------------------------------------------------------

/// 라벨 폭 (dots @203dpi). LabelPainter 이미지 폭과 동일.
const int kBxlLabelWidthDots = 490;

/// 라벨 길이 (dots @203dpi). LabelPainter 이미지 높이와 동일.
const int kBxlLabelLengthDots = 600;

/// 라벨 간 갭 ≈ 3mm. 실기기 오프셋 밀림 시 조정.
const int kBxlLabelGapDots = 24;

/// 사전 이진화 임계값 (luminance < threshold → 검정).
/// Android 실기기 검증값 — black26 구분자(≈189) 포함 + 흰 배경(255) 여유.
const int kBxlBinarizeThreshold = 210;

/// 인쇄 농도 (0~20, 샘플 기본 14). 실기기 품질 비교 후 튜닝점.
const int kBxlDensity = 14;
