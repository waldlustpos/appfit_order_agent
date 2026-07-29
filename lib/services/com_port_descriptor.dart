/// Windows COM 포트 1개와 그 포트에 물린 장치의 식별 정보.
///
/// 이 파일은 **native 의존이 0** 이어야 한다. `ComPortPrintService` /
/// `external_receipt_printer_windows.dart` 는 UI 에서 `deferred as` 로만 import
/// 되는데(Android 에서 win32 → kernel32.dll lookup 크래시 회피), deferred
/// 라이브러리의 **타입**을 UI 위젯의 필드 타입으로 쓰는 것은 Dart 가 허용하지
/// 않는다. 그래서 값 객체만 여기로 분리해 양쪽이 공유한다.
///
/// 서버 DTO 가 아니라 서비스 계층 값 객체이므로 `lib/models/` 가 아닌
/// `lib/services/` 에 둔다.
library;

/// COM 포트 + SetupAPI 장치 식별 정보.
///
/// [portName] 은 레지스트리 `SERIALCOMM`(= `SerialPort.getAvailablePorts()`)
/// 에서 온 **정본**이고, 나머지 필드는 SetupAPI(`getPortsWithFullMessages`)
/// 에서 조인해 붙인 **장식**이다. 두 소스는 집합이 다를 수 있어(블루투스 SPP 등)
/// 조인이 실패하면 null 로 남는다.
///
/// 주의: [friendlyName] / [manufacturer] 는 **USB-Serial 어댑터·드라이버**의
/// 이름이지 프린터 본체 모델명이 아니다. PR800 을 NEXT-340PL(PL2303) 케이블에
/// 물리면 "Prolific ..." 로 표시된다. UI 문구도 "장치명" 으로 쓸 것.
class ComPortDescriptor {
  const ComPortDescriptor({
    required this.portName,
    this.friendlyName,
    this.manufacturer,
    this.hardwareId,
  });

  /// 'COM5'. 열거/probe 가 모두 이 값을 쓴다.
  final String portName;

  /// SetupAPI `SPDRP_FRIENDLYNAME`. 예: 'Prolific PL2303GT USB Serial COM Port (COM5)'
  final String? friendlyName;

  /// SetupAPI `SPDRP_MFG`. 예: 'Prolific'
  final String? manufacturer;

  /// SetupAPI `SPDRP_HARDWAREID`. 예: 'USB\\VID_067B&PID_23A3&REV_0105'
  final String? hardwareId;

  /// 드롭다운 항목 / 진단 로그용 한 줄.
  ///
  /// friendlyName 은 관례적으로 `'... (COM5)'` 처럼 포트명을 접미사로 달고 있어
  /// 그대로 쓰면 `'COM5 · ... (COM5)'` 로 중복된다. 접미사를 떼고 조합한다.
  /// 식별 정보가 없으면 포트명만.
  String get displayLabel {
    final device = deviceName;
    return device == null ? portName : '$portName · $device';
  }

  /// 포트명 접미사를 제거한 장치명. 식별 정보가 전혀 없으면 null.
  ///
  /// friendlyName 우선, 없으면 manufacturer 로 대체 (드라이버에 따라 MFG 만
  /// 채워지는 경우가 있다).
  String? get deviceName {
    final raw = _nonEmpty(friendlyName) ?? _nonEmpty(manufacturer);
    if (raw == null) return null;
    final suffix = ' ($portName)';
    final stripped = raw.endsWith(suffix)
        ? raw.substring(0, raw.length - suffix.length)
        : raw;
    return _nonEmpty(stripped) ?? raw;
  }

  static String? _nonEmpty(String? s) {
    if (s == null) return null;
    final t = s.trim();
    return t.isEmpty ? null : t;
  }

  @override
  String toString() => 'ComPortDescriptor($displayLabel'
      '${hardwareId == null ? '' : ', hwid=$hardwareId'})';
}

/// 재연결 스캔이 probe 할 포트 순서를 정한다.
///
/// - [savedPort] 가 있으면 항상 맨 앞 (사용자가 고른 포트를 먼저 존중).
/// - [savedPort] 가 [ports] 에 없어도 후보에 포함한다. 열거 소스가 순간적으로
///   포트를 놓치는 경우(USB re-enumerate lag)가 있어, 실제로 열어보는 편이
///   목록만 믿는 것보다 정확하다. probe 의 진입 가드가 없는 포트는 즉시
///   false 로 걸러낸다.
/// - 나머지는 열거 순서 그대로, 중복 없이.
///
/// 순수 함수 — Windows 없이 테스트 가능.
List<String> orderProbeCandidates(List<String> ports, String? savedPort) {
  final seen = <String>{};
  final result = <String>[];

  void add(String? p) {
    if (p == null) return;
    final t = p.trim();
    if (t.isEmpty) return;
    if (seen.add(t)) result.add(t);
  }

  add(savedPort);
  for (final p in ports) {
    add(p);
  }
  return result;
}
