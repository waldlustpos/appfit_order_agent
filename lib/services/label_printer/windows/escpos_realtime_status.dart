/// ESC/POS 실시간 상태(DLE EOT) 명령과 응답 바이트 디코더.
///
/// G30 Windows 경로가 용지없음·커버열림을 읽어 Android `waitEntryGateLocked` 와
/// 같은 복구대기를 하기 위한 것이다. 신호 자체는 이 레포가 이미 쓰던 것과 같다 —
/// `ComPortPrintService` 가 외부 영수증 프린터 생존 확인에 `DLE EOT 1` 을 쓴다.
///
/// ## 이 파일의 제약 — `dart:ui`·win32 의존 0
///
/// `g30_escpos_raster.dart` 와 같은 규율이다. Android import 그래프에서 도달
/// 가능하므로 win32 를 끌면 kernel8 lookup 크래시가 나고, standalone `dart run`
/// (`tool/g30_windows_probe.dart`)에서도 같은 디코더를 써야 프로브 실측이
/// 프로덕션 판정을 그대로 검증한다.
library;

/// `DLE EOT n` — 실시간 상태 전송. n 은 아래 상수.
List<int> dleEot(int n) => [0x10, 0x04, n];

/// n=1 프린터 상태 (온라인/오프라인).
const int kDleEotPrinter = 1;

/// n=2 오프라인 원인 — **커버 열림**이 여기 있다.
const int kDleEotOffline = 2;

/// n=3 에러 상태 (커터 에러·복구불능 등).
const int kDleEotError = 3;

/// n=4 용지 센서 — **용지 없음**이 여기 있다.
const int kDleEotPaper = 4;

/// DLE EOT 응답의 **고정 비트 패턴** 검사.
///
/// 표준상 bit0=0, bit1=1, bit4=1, bit7=0 이 항상 고정이다
/// (`b & 0b1001_0011 == 0b0001_0010`).
///
/// 이 검사가 이 파일의 핵심이다. 프린터가 상태를 안 주는데 버퍼에 남은 쓰레기
/// 바이트를 읽어 "용지없음"으로 오독하면 **있지도 않은 용지없음으로 무한 대기**에
/// 빠져 라벨이 영영 안 나온다. 그래서 호출부는 `null`(=상태 모름)과
/// `paperEnd == true`(=진짜 용지없음)를 반드시 다르게 다뤄야 한다.
bool isValidStatusByte(int b) => (b & 0x93) == 0x12;

/// `DLE EOT 2` 응답. 해독 불가면 null.
EscPosOfflineStatus? decodeOfflineStatus(int b) {
  if (!isValidStatusByte(b)) return null;
  return EscPosOfflineStatus(
    raw: b,
    coverOpen: (b & 0x04) != 0,
    paperFeedByButton: (b & 0x08) != 0,
    printingStopped: (b & 0x20) != 0,
    errorOccurred: (b & 0x40) != 0,
  );
}

/// `DLE EOT 4` 응답. 해독 불가면 null.
///
/// 용지 관련 비트는 **2비트가 짝으로** 움직인다(bit2+bit3 = near-end,
/// bit5+bit6 = end). 한쪽만 서는 중간 상태는 규격상 나오지 않으므로 마스크
/// 전체 일치로 판정한다.
EscPosPaperStatus? decodePaperStatus(int b) {
  if (!isValidStatusByte(b)) return null;
  return EscPosPaperStatus(
    raw: b,
    nearEnd: (b & 0x0C) == 0x0C,
    paperEnd: (b & 0x60) == 0x60,
  );
}

class EscPosOfflineStatus {
  const EscPosOfflineStatus({
    required this.raw,
    required this.coverOpen,
    required this.paperFeedByButton,
    required this.printingStopped,
    required this.errorOccurred,
  });

  final int raw;
  final bool coverOpen;
  final bool paperFeedByButton;

  /// 용지 끝으로 인쇄가 멈춤. 기종에 따라 안 서기도 해서 **용지 판정의 정본은
  /// [EscPosPaperStatus.paperEnd]** 다 — 이건 보조 신호로만 쓴다.
  final bool printingStopped;
  final bool errorOccurred;

  @override
  String toString() => 'offline(0x${raw.toRadixString(16).padLeft(2, '0')}'
      '${coverOpen ? " cover" : ""}${printingStopped ? " stopped" : ""}'
      '${errorOccurred ? " err" : ""})';
}

class EscPosPaperStatus {
  const EscPosPaperStatus({
    required this.raw,
    required this.nearEnd,
    required this.paperEnd,
  });

  final int raw;
  final bool nearEnd;
  final bool paperEnd;

  @override
  String toString() => 'paper(0x${raw.toRadixString(16).padLeft(2, '0')}'
      '${paperEnd ? " END" : ""}${nearEnd ? " near" : ""})';
}

/// 진입 게이트가 필요로 하는 두 신호만 묶은 값 객체.
///
/// Android `waitEntryGateLocked` 의 `getCoverOpen()` / `getRecEmpty()` 짝에 대응한다.
/// 이 타입이 **native 의존 없는 이 파일에** 있어야 하는 이유: 게이트를 도는
/// `bixolon_g30_windows_backend` 는 `usb_print_service` 를 `deferred as` 로만
/// import 하는데, deferred 라이브러리에 선언된 타입은 타입 표기에 쓸 수 없다.
/// (`UsbPrintDescriptor` 가 `usb_print_descriptor.dart` 로 분리돼 있는 것과 같은 이유.)
class EscPosGateStatus {
  const EscPosGateStatus({required this.coverOpen, required this.paperEnd});

  final bool coverOpen;
  final bool paperEnd;

  /// 인쇄를 시작해도 되는 상태인가.
  bool get canPrint => !coverOpen && !paperEnd;

  @override
  String toString() =>
      'gate(cover=$coverOpen paperEnd=$paperEnd)';
}

/// 진입 게이트 로그 문구. Android `BixolonPosDriver.describeEntry` 와 같은 어휘를
/// 쓴다 — 두 플랫폼 로그를 같은 눈으로 읽기 위함이다.
String describeEntryBlock({required bool coverOpen, required bool paperEnd}) {
  if (coverOpen && paperEnd) return '용지없음+커버열림';
  if (paperEnd) return '용지없음';
  return '커버열림';
}
