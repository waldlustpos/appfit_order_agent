/// Windows USB 프린터 클래스(usbprint.sys) 장치 1개의 식별 정보.
///
/// 이 파일은 [ComPortDescriptor] 와 **같은 이유로** native 의존이 0 이어야 한다:
/// `usb_print_service.dart` / `external_receipt_printer_windows.dart` 는 UI 에서
/// `deferred as` 로만 import 되는데, deferred 라이브러리의 **타입**을 UI 위젯의
/// 필드 타입으로 쓰는 것은 Dart 가 허용하지 않는다. 그래서 값 객체만 여기로
/// 분리해 양쪽이 공유한다.
///
/// 서버 DTO 가 아니라 서비스 계층 값 객체이므로 `lib/models/` 가 아닌
/// `lib/services/` 에 둔다.
library;

/// SetupAPI `GUID_DEVINTERFACE_USBPRINT` 열거 결과 1건.
///
/// COM 경로의 [ComPortDescriptor] 와 달리 여기서는 [devicePath] 자체가 정본
/// 식별자다 — COM 포트명(`COM5`)처럼 짧고 안정적인 이름이 없고, `CreateFile` 이
/// 받는 것도 이 경로다. 사용자 설정에도 이 문자열을 그대로 저장한다.
///
/// 주의: [devicePath] 는 USB 허브의 어느 포트에 꽂혔는지를 포함하므로 **다른
/// USB 포트로 옮겨 꽂으면 값이 바뀐다**. 설정이 어긋나면 재연결에서 다시
/// 고르게 하되, 저장값을 말없이 갈아치우지는 않는다(COM 경로와 동일 규율).
class UsbPrintDescriptor {
  const UsbPrintDescriptor({
    required this.devicePath,
    this.friendlyName,
    this.vendorId,
    this.productId,
  });

  /// `\\?\usb#vid_0483&pid_a319#207f38734b30#{28d78fad-...}`.
  /// 열거/오픈/설정 저장이 모두 이 값을 쓴다.
  final String devicePath;

  /// SetupAPI `SPDRP_FRIENDLYNAME`, 없으면 `SPDRP_DEVICEDESC`.
  /// 예: 'EASYSET PBP_A8'
  final String? friendlyName;

  /// [devicePath] 의 `vid_xxxx` 에서 파싱. 파싱 실패 시 null.
  final int? vendorId;

  /// [devicePath] 의 `pid_xxxx` 에서 파싱. 파싱 실패 시 null.
  final int? productId;

  /// 드롭다운 항목 / 진단 로그용 한 줄. 예: `EASYSET PBP_A8 (0483:A319)`.
  ///
  /// VID:PID 를 항상 붙인다 — 같은 모델을 두 대 물리면 friendlyName 이 동일해
  /// 이름만으로는 구분이 안 되고, 오선택은 곧 "영수증이 엉뚱한 장치로" 이기
  /// 때문에 식별자를 눈에 보이게 둔다.
  String get displayLabel {
    final name = _nonEmpty(friendlyName) ?? 'USB 프린터';
    final ids = hexIds;
    return ids == null ? name : '$name ($ids)';
  }

  /// `0483:A319` 형태. VID/PID 를 모르면 null.
  String? get hexIds {
    final v = vendorId;
    final p = productId;
    if (v == null || p == null) return null;
    return '${_hex4(v)}:${_hex4(p)}';
  }

  static String _hex4(int v) =>
      v.toRadixString(16).toUpperCase().padLeft(4, '0');

  static String? _nonEmpty(String? s) {
    if (s == null) return null;
    final t = s.trim();
    return t.isEmpty ? null : t;
  }

  @override
  String toString() => 'UsbPrintDescriptor($displayLabel, path=$devicePath)';
}

/// USB VID/PID 를 Windows 장치 문자열에서 뽑는다.
///
/// 두 가지 형태를 모두 받는다 — 둘 다 `vid_xxxx` / `pid_xxxx` 를 품고 있고
/// 대소문자만 다르다:
/// - usbprint 인터페이스 경로: `\\?\usb#vid_0483&pid_a319#...`
/// - COM 포트의 SetupAPI `SPDRP_HARDWAREID`: `USB\VID_0D28&PID_4C59&MI_01\...`
///
/// 그래서 COM 으로 붙은 프린터도 같은 함수로 기종을 식별할 수 있다
/// ([knownPrinterColumns] 프리시드가 이걸 쓴다).
/// 순수 함수 — Windows 없이 테스트 가능.
({int? vendorId, int? productId}) parseUsbIdsFromDevicePath(String devicePath) {
  final m = RegExp(r'vid_([0-9a-f]{4}).*?pid_([0-9a-f]{4})', caseSensitive: false)
      .firstMatch(devicePath);
  if (m == null) return (vendorId: null, productId: null);
  return (
    vendorId: int.tryParse(m.group(1)!, radix: 16),
    productId: int.tryParse(m.group(2)!, radix: 16),
  );
}

/// `0483:A319` 형태의 대문자 16진수 키. 폭 테이블 조회 키를 한 곳에서 만든다.
String? usbIdKey({int? vendorId, int? productId}) {
  if (vendorId == null || productId == null) return null;
  String hex4(int x) => x.toRadixString(16).toUpperCase().padLeft(4, '0');
  return '${hex4(vendorId)}:${hex4(productId)}';
}
