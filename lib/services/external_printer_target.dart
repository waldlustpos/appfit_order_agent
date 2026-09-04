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
  int? get knownColumns => knownColumnsForDeviceString(_deviceString);

  /// 이 대상이 가리키는 물리 장치의 `VID:PID`. 못 뽑으면 null.
  ///
  /// **종류가 달라도 같은 물리 장치면 같은 값이 나온다** — PR800 은 복합 장치라
  /// `MI_00` 은 usbprint 로, `MI_01` 은 CDC→COM 으로 각각 잡히지만 VID/PID 는
  /// 하나다. [dedupeSameDevicePreferringCom] 이 이 성질을 쓴다.
  String? get usbIdKeyOrNull {
    final s = _deviceString;
    if (s == null || s.isEmpty) return null;
    final ids = parseUsbIdsFromDevicePath(s);
    return usbIdKey(vendorId: ids.vendorId, productId: ids.productId);
  }

  /// VID/PID 를 품고 있는 문자열. usbprint 는 장치 경로 자체, COM 은 hardwareId.
  String? get _deviceString =>
      kind == ExternalPrinterKind.usbPrint ? id : hardwareId;

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

/// 같은 물리 장치가 COM 과 usbprint 양쪽에 잡히면 **usbprint 쪽을 버린다.**
///
/// PR800 은 복합 USB 장치라 `MI_00`(usbprint) 과 `MI_01`(CDC→COM) 으로 **두 번**
/// 열거된다. 손대지 않으면 드롭다운에 같은 프린터가 두 줄로 나오고, 재연결 스캔이
/// usbprint 쪽을 채택해 설정에 `COM3` 대신 장치 경로가 박힌다.
///
/// **COM 을 남기는 이유는 기술이 아니라 운영이다.** 현장 설치는 오래도록 COM 포트
/// (`COM3` 등)를 보고 세팅해 왔고, 설치 담당자가 익숙한 표기가 그대로 보여야 한다.
/// PR800 이 일반 설치고 A8 같은 usbprint 전용 기종이 예외라, 예외 때문에 일반이
/// 낯설어지면 안 된다. usbprint 전용 기종은 짝이 되는 COM 후보가 없으므로 그대로
/// 남는다 — 이 함수는 **선택지를 줄이지 않고 중복만 없앤다.**
///
/// VID/PID 를 못 뽑는 후보(물리 RS-232 등)는 짝을 판정할 수 없으므로 건드리지 않는다.
///
/// [keep] 은 **지금 설정에 저장된 대상**이며 절대 버리지 않는다. 이미 usbprint 로
/// 잡아 쓰고 있던 단말에서 그 항목을 목록에서 지우면 드롭다운이 "미선택" 으로
/// 보인다 — 실제로는 멀쩡히 그 경로로 출력되고 있는데도. **쓰고 있는 것은 항상
/// 보여야 한다.** (저장값을 COM 으로 말없이 옮기지도 않는다: 같은 프린터라도
/// COM 쪽 드라이버가 죽어 있을 수 있어, 동작 중인 설정을 자동으로 바꾸면
/// "설정을 만진 적 없는데 출력이 끊긴다" 가 된다.)
///
/// 순수 함수 — Windows 없이 테스트 가능.
List<ExternalPrinterTarget> dedupeSameDevicePreferringCom(
  List<ExternalPrinterTarget> targets, {
  ExternalPrinterTarget? keep,
}) {
  final comKeys = <String>{};
  for (final t in targets) {
    if (t.kind != ExternalPrinterKind.com) continue;
    final k = t.usbIdKeyOrNull;
    if (k != null) comKeys.add(k);
  }
  if (comKeys.isEmpty) return targets;

  return targets.where((t) {
    if (t.kind != ExternalPrinterKind.usbPrint) return true;
    if (t.sameAs(keep)) return true;
    final k = t.usbIdKeyOrNull;
    return k == null || !comKeys.contains(k);
  }).toList(growable: false);
}

/// 재연결 스캔이 probe 할 후보 순서를 정한다.
///
/// - [saved] 가 있으면 항상 맨 앞 (직전에 쓰던 장치를 먼저 존중).
/// - [saved] 가 [targets] 에 없어도 후보에 포함한다. 열거 소스가 순간적으로
///   장치를 놓치는 경우(USB re-enumerate lag)가 있어, 실제로 열어보는 편이
///   목록만 믿는 것보다 정확하다. ([orderProbeCandidates] 와 같은 판단.)
/// - 그 다음은 **com 먼저, usbPrint 나중**. 현장 설치가 COM 표기에 맞춰져 있고
///   일반 설치 기종(PR800)이 COM 이라, 애매할 때 COM 으로 수렴시키는 것이 맞다.
///   (같은 장치가 양쪽에 잡히는 중복 자체는 [dedupeSameDevicePreferringCom] 이
///   먼저 없애므로, 이 순서가 실제로 갈리는 건 **서로 다른 장치**가 두 경로에
///   하나씩 있을 때다.)
///
///   대가를 알고 택한 순서다: COM 후보에는 캐시드로어 · 저울 같은 무관한 장비가
///   섞여 있고 probe 가 포트당 수백 ms 라, usbprint 를 먼저 훑어 조기 종료할
///   때보다 스캔이 느리고 무관한 장비를 더 건드린다. 다만 usbprint 가 못 잡으면
///   어차피 COM 을 전부 훑던 구조라 **건드리는 대상 자체가 늘지는 않는다** —
///   순서만 바뀐다. 재연결은 사용자가 버튼을 눌렀을 때만 도는 수동 동작이라
///   이 정도 지연은 받는다.
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
    if (t.kind == ExternalPrinterKind.com) add(t);
  }
  for (final t in targets) {
    if (t.kind == ExternalPrinterKind.usbPrint) add(t);
  }
  return result;
}
