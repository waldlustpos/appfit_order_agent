import 'package:flutter_test/flutter_test.dart';

import 'package:appfit_order_agent/services/external_printer_target.dart';

/// 재연결 통합 스캔의 후보 순서 characterization.
///
/// 순서는 취향이 아니라 안전 규칙이다:
/// - 저장 대상을 먼저 훑어야 "쓰던 프린터"로 조기 종료된다.
/// - usbprint 를 COM 보다 먼저 훑어야 캐시드로어·저울 같은 **무관한 COM 장비를
///   덜 건드린다** (usbprint 후보는 USB Printer class 라 프린터임이 확실하고
///   probe 가 수 ms, COM probe 는 포트당 수백 ms).
void main() {
  ExternalPrinterTarget usb(String id) => ExternalPrinterTarget(
        kind: ExternalPrinterKind.usbPrint,
        id: id,
        label: 'USB $id',
      );
  ExternalPrinterTarget com(String id) => ExternalPrinterTarget(
        kind: ExternalPrinterKind.com,
        id: id,
        label: 'COM $id',
      );

  group('orderScanCandidates', () {
    test('저장 대상이 항상 맨 앞', () {
      final r = orderScanCandidates(
        [usb('u1'), com('COM3'), com('COM5')],
        com('COM5'),
      );
      expect(r.first.uiValue, 'com:COM5');
    });

    test('저장 대상이 목록에 없어도 후보에 포함한다 (열거 lag 대응)', () {
      final r = orderScanCandidates([usb('u1')], com('COM9'));
      expect(r.map((t) => t.uiValue), ['com:COM9', 'usbprint:u1']);
    });

    test('저장이 없으면 usbprint 먼저, COM 나중', () {
      final r = orderScanCandidates(
        [com('COM3'), usb('u1'), com('COM5'), usb('u2')],
        null,
      );
      expect(
        r.map((t) => t.uiValue),
        ['usbprint:u1', 'usbprint:u2', 'com:COM3', 'com:COM5'],
      );
    });

    test('저장 대상이 중복으로 다시 나오지 않는다', () {
      final r = orderScanCandidates([usb('u1'), com('COM3')], usb('u1'));
      expect(r.map((t) => t.uiValue), ['usbprint:u1', 'com:COM3']);
    });

    test('빈 id 는 후보에서 제외 — 열지 못할 대상을 probe 하지 않는다', () {
      final r = orderScanCandidates([usb('  '), com('COM3')], null);
      expect(r.map((t) => t.uiValue), ['com:COM3']);
    });

    test('같은 id 라도 종류가 다르면 별개 후보다', () {
      final r = orderScanCandidates([usb('X'), com('X')], null);
      expect(r.map((t) => t.uiValue), ['usbprint:X', 'com:X']);
    });

    test('후보가 없고 저장도 없으면 빈 목록', () {
      expect(orderScanCandidates(const [], null), isEmpty);
    });
  });

  group('sameAs — 대소문자 무시', () {
    test('장치 경로 표기가 OS/드라이버 버전에 따라 갈려도 같은 대상으로 본다', () {
      expect(usb(r'\\?\USB#VID_0483').sameAs(usb(r'\\?\usb#vid_0483')), isTrue);
    });

    test('종류가 다르면 다른 대상', () {
      expect(usb('X').sameAs(com('X')), isFalse);
    });

    test('null 과는 같지 않다', () {
      expect(com('COM3').sameAs(null), isFalse);
    });
  });

  group('displayLabel — 사용자가 무엇을 고르는지 알 수 있어야 한다', () {
    test('usbprint 는 USB 표시가 붙는다', () {
      expect(usb('u1').displayLabel, 'USB u1 · USB');
    });

    test('COM 은 라벨 그대로', () {
      expect(com('COM3').displayLabel, 'COM COM3');
    });
  });

  // 폭 프리시드. 기본값이 42(POSBANK 계열)라 **넓은 기종만** 예외로 잡는다 —
  // 폭을 크게 잡으면 출력이 밀려 망가지고, 작게 잡으면 여백만 남기 때문.
  group('knownColumnsForDeviceString', () {
    test('PR800(0D28:4C59) 은 48 — usbprint 장치 경로에서', () {
      expect(
        knownColumnsForDeviceString(r'\\?\usb#vid_0d28&pid_4c59#abc#{guid}'),
        48,
      );
    });

    test('PR800 은 COM 포트의 hardwareId(대문자)에서도 잡힌다', () {
      // COM 경로는 포트명에 VID/PID 가 없어 SetupAPI hardwareId 로만 알 수 있다.
      expect(
        knownColumnsForDeviceString(r'USB\VID_0D28&PID_4C59&MI_01\6&abc&0&0001'),
        48,
      );
    });

    test('POSBANK A8 은 테이블에 없다 — 기본값 42 로 떨어지면 맞는다', () {
      expect(
        knownColumnsForDeviceString(r'\\?\usb#vid_0483&pid_a319#...'),
        isNull,
      );
    });

    test('VID/PID 를 못 읽으면 null (기본값 사용)', () {
      expect(knownColumnsForDeviceString('COM3'), isNull);
      expect(knownColumnsForDeviceString(''), isNull);
      expect(knownColumnsForDeviceString(null), isNull);
    });
  });

  group('ExternalPrinterTarget.knownColumns — 종류별로 다른 곳을 본다', () {
    test('usbprint 는 id(장치 경로)에서 읽는다', () {
      const t = ExternalPrinterTarget(
        kind: ExternalPrinterKind.usbPrint,
        id: r'\\?\usb#vid_0d28&pid_4c59#x#{g}',
        label: 'x',
      );
      expect(t.knownColumns, 48);
    });

    test('COM 은 id 가 아니라 hardwareId 에서 읽는다', () {
      const t = ExternalPrinterTarget(
        kind: ExternalPrinterKind.com,
        id: 'COM3',
        label: 'COM3',
        hardwareId: r'USB\VID_0D28&PID_4C59&MI_01\x',
      );
      expect(t.knownColumns, 48);
    });

    test('COM 인데 hardwareId 가 없으면 null — 열거가 실패해도 오판하지 않는다', () {
      const t = ExternalPrinterTarget(
        kind: ExternalPrinterKind.com,
        id: 'COM3',
        label: 'COM3',
      );
      expect(t.knownColumns, isNull);
    });
  });
}
