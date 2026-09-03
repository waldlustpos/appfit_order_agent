/// Windows 외부 영수증 프린터의 "연결 대상" — 케이블 종류를 감춘 단일 표현.
///
/// 이 파일은 [ComPortDescriptor] / [UsbPrintDescriptor] 와 **같은 이유로** native
/// 의존이 0 이어야 한다: win32 모듈은 UI 에서 `deferred as` 로만 import 되는데,
/// deferred 라이브러리의 타입은 위젯 필드 타입으로 쓸 수 없다.
library;

import 'package:appfit_order_agent/services/usb_print_descriptor.dart'
    show parseUsbIdsFromDevicePath, usbIdKey;

/// 대상이 어느 OS 경로에 붙어 있는지.
///
/// **두 종류는 서로소 집합이다** — 어느 쪽이 "더 낫다" 가 아니라 물리적으로
/// 배타적이라 둘 다 필요하다:
/// - 물리 RS-232 로 붙은 프린터는 USB 장치가 아니므로 usbprint 열거에 안 나온다.
/// - usbprint.sys 에 바인딩된 프린터(POSBANK A8)는 CDC 를 노출하지 않으므로
///   COM 포트를 만들지 않는다.
///
/// 그래서 사용자에게 종류를 고르게 하지 않고 [ExternalPrinterTarget] 로 묶어
/// **앱이 양쪽을 훑어 응답하는 장치를 채택**한다.
enum ExternalPrinterKind {
  /// 가상 COM(usbser.sys) 또는 물리 RS-232. `ComPortPrintService`.
  com,

  /// USB 프린터 클래스(usbprint.sys). `UsbPrintService`.
  usbPrint;

  /// `PreferenceService.extPrinterConn*` 에 저장되는 문자열.
  String get prefValue => this == com ? 'com' : 'usbprint';
}

/// 실효 컬럼 수가 **기본값(42)과 다른 것이 실측으로 확인된** 프린터.
///
/// 기본값을 42(POSBANK 계열)로 두고 **넓은 기종만 예외로 등재**한다. 근거:
/// 폭을 실제보다 **크게** 잡으면 구분선과 수량 칸이 다음 줄로 밀려 출력물이
/// 망가지지만, **작게** 잡으면 우측 여백이 남을 뿐 읽을 수는 있다. 모르는
/// 기종에서는 조용히 망가지는 쪽보다 여백이 남는 쪽으로 실패해야 한다.
///
/// 키는 `VID:PID` 대문자 16진수. usbprint 는 장치 경로에서, COM 은 SetupAPI
/// `SPDRP_HARDWAREID` 에서 같은 방식으로 뽑는다 ([parseUsbIdsFromDevicePath]).
///
/// 어디까지나 **초기값 추정**이고 사용자가 설정에서 고른 값이 항상 이긴다 —
/// 프리시드는 `PreferenceService.getExternalPrinterColumns()` 가 null 일 때만
/// 개입해야 한다. 추측으로 채우지 말 것: 틀린 프리시드는 "설정을 만진 적 없는데
/// 출력이 어긋난다" 가 되어 원인 추적이 훨씬 어렵다. 눈금자 출력
/// (`ReceiptEscPosBuilder.buildWidthRulerBytes`)으로 확인한 기종만 추가한다.
const Map<String, int> knownPrinterColumns = {
  // PR800 계열 (NXP LPC 마이크로컨트롤러). Windows 에서는 CDC 로 COM 포트가
  // 생기고 Android 에서는 CDC-data 인터페이스로 붙는 그 기종이다. 576dot / 48컬럼.
  '0D28:4C59': 48,
};

/// [deviceString] (usbprint 장치 경로 또는 COM 포트의 hardwareId) 이 가리키는
/// 기종의 알려진 컬럼 수. 모르는 기종이면 null — 호출부가 기본값(42)을 쓴다.
int? knownColumnsForDeviceString(String? deviceString) {
  if (deviceString == null || deviceString.isEmpty) return null;
  final ids = parseUsbIdsFromDevicePath(deviceString);
  final key = usbIdKey(vendorId: ids.vendorId, productId: ids.productId);
  return key == null ? null : knownPrinterColumns[key];
}

/// 연결 후보 1건. 종류가 달라도 UI/스캔은 이 타입 하나만 다룬다.
class ExternalPrinterTarget {
  const ExternalPrinterTarget({
    required this.kind,
    required this.id,
    required this.label,
    this.hardwareId,
  });

  final ExternalPrinterKind kind;

  /// 종류별 식별자. com 이면 `'COM3'`, usbPrint 면 장치 인터페이스 경로.
  /// 설정에 저장되는 값이자 open 이 받는 값이다.
  final String id;

  /// 드롭다운/로그 표시용. 소스 descriptor 의 `displayLabel`.
  final String label;

  /// COM 후보의 SetupAPI `SPDRP_HARDWAREID`. usbprint 는 [id] 자체가 VID/PID 를
  /// 품고 있어 null 이다. 기종별 폭 프리시드([knownColumnsForDeviceString])가
  /// COM 경로에서도 동작하게 하려고 들고 다닌다.
  final String? hardwareId;

  /// 이 대상의 알려진 컬럼 수. 모르는 기종이면 null.
  int? get knownColumns => knownColumnsForDeviceString(
      kind == ExternalPrinterKind.usbPrint ? id : hardwareId);

  /// DropdownButton 의 value — 종류가 다르면 id 가 겹칠 일이 없지만, 두 목록을
  /// 한 드롭다운에 합치므로 종류를 접두어로 붙여 충돌 가능성을 원천 차단한다.
  String get uiValue => '${kind.prefValue}:$id';

  /// 목록 항목에 종류를 함께 보여준다 — 같은 프린터가 케이블을 바꿔 꽂아
  /// 양쪽에 다 보이는 상황에서 사용자가 무엇을 고르는지 알 수 있어야 한다.
  String get displayLabel =>
      kind == ExternalPrinterKind.com ? label : '$label · USB';

  bool sameAs(ExternalPrinterTarget? other) =>
      other != null &&
      other.kind == kind &&
      other.id.toLowerCase() == id.toLowerCase();

  @override
  String toString() => 'ExternalPrinterTarget(${kind.prefValue}:$id, $label)';
}

/// 재연결 스캔이 probe 할 후보 순서를 정한다.
///
/// - [saved] 가 있으면 항상 맨 앞 (직전에 쓰던 장치를 먼저 존중).
/// - [saved] 가 [targets] 에 없어도 후보에 포함한다. 열거 소스가 순간적으로
///   장치를 놓치는 경우(USB re-enumerate lag)가 있어, 실제로 열어보는 편이
///   목록만 믿는 것보다 정확하다. ([orderProbeCandidates] 와 같은 판단.)
/// - 그 다음은 **usbPrint 먼저, com 나중**. usbprint 후보는 USB Printer class 라
///   프린터임이 확실하고 probe 가 수 ms 로 끝나지만, COM 후보에는 캐시드로어 ·
///   저울 같은 무관한 장비가 섞여 있고 probe 가 포트당 수백 ms 걸린다. 무관한
///   장비를 최대한 안 건드리려면 확실한 쪽을 먼저 훑어 조기 종료해야 한다.
/// - 같은 (종류, id) 는 한 번만.
///
/// 순수 함수 — Windows 없이 테스트 가능.
List<ExternalPrinterTarget> orderScanCandidates(
  List<ExternalPrinterTarget> targets,
  ExternalPrinterTarget? saved,
) {
  final seen = <String>{};
  final result = <ExternalPrinterTarget>[];

  void add(ExternalPrinterTarget? t) {
    if (t == null) return;
    if (t.id.trim().isEmpty) return;
    if (seen.add(t.uiValue.toLowerCase())) result.add(t);
  }

  add(saved);
  for (final t in targets) {
    if (t.kind == ExternalPrinterKind.usbPrint) add(t);
  }
  for (final t in targets) {
    if (t.kind == ExternalPrinterKind.com) add(t);
  }
  return result;
}
