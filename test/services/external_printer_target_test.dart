import 'package:flutter_test/flutter_test.dart';

import 'package:appfit_order_agent/services/external_printer_target.dart';

/// 재연결 통합 스캔의 후보 순서 characterization.
///
/// 순서는 취향이 아니라 운영 규칙이다:
/// - 저장 대상을 먼저 훑어야 "쓰던 프린터"로 조기 종료된다.
/// - 그 다음은 **COM 먼저**. 현장 설치가 오래도록 COM 표기(`COM3` 등)에 맞춰져
///   있고 일반 설치 기종(PR800)이 COM 이라, 애매할 때 COM 으로 수렴시킨다.
///   usbprint 전용 기종(POSBANK A8)은 예외 설치다.
/// - 같은 물리 장치가 양쪽에 잡히는 중복은 순서가 아니라
///   [dedupeSameDevicePreferringCom] 이 없앤다.
void main() {
  ExternalPrinterTarget usb(String id, {String? path}) => ExternalPrinterTarget(
        kind: ExternalPrinterKind.usbPrint,
        id: path ?? id,
        label: 'USB $id',
      );
  ExternalPrinterTarget com(String id, {String? hardwareId}) =>
      ExternalPrinterTarget(
        kind: ExternalPrinterKind.com,
        id: id,
        label: 'COM $id',
        hardwareId: hardwareId,
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

    test('저장이 없으면 COM 먼저, usbprint 나중', () {
      // 현장 설치가 COM 표기(COM3 등)에 맞춰져 있어 애매할 때 COM 으로 수렴시킨다.
      final r = orderScanCandidates(
        [usb('u1'), com('COM3'), usb('u2'), com('COM5')],
        null,
      );
      expect(
        r.map((t) => t.uiValue),
        ['com:COM3', 'com:COM5', 'usbprint:u1', 'usbprint:u2'],
      );
    });

    test('저장이 usbprint 면 COM 보다 앞선다 — 사용자 선택이 기본 선호를 이긴다', () {
      final r = orderScanCandidates([com('COM3'), usb('u1')], usb('u1'));
      expect(r.map((t) => t.uiValue), ['usbprint:u1', 'com:COM3']);
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
      expect(r.map((t) => t.uiValue), ['com:X', 'usbprint:X']);
    });

    test('후보가 없고 저장도 없으면 빈 목록', () {
      expect(orderScanCandidates(const [], null), isEmpty);
    });
  });

  group('dedupeSameDevicePreferringCom', () {
    // 본 PC 실측 문자열 (2026-09-04).
    const pr800UsbPath =
        r'\\?\usb#vid_0d28&pid_4c59&mi_00#7&25e4af7&0&0000#{28d78fad-5a12-11d1-ae5b-0000f803a8c2}';
    const pr800HardwareId = r'USB\VID_0D28&PID_4C59&MI_01\6&1a2b3c&0&0001';
    const a8UsbPath =
        r'\\?\usb#vid_0483&pid_a319#207f38734b30#{28d78fad-5a12-11d1-ae5b-0000f803a8c2}';

    test('PR800 처럼 COM 과 usbprint 양쪽에 잡히면 usbprint 쪽을 버린다', () {
      final r = dedupeSameDevicePreferringCom([
        com('COM3', hardwareId: pr800HardwareId),
        usb('PR800', path: pr800UsbPath),
      ]);
      expect(r.map((t) => t.uiValue), ['com:COM3']);
    });

    test('짝이 없는 usbprint 전용 기종(A8)은 그대로 남는다', () {
      // 예외 설치를 못 쓰게 만들면 안 된다 — 중복만 없애고 선택지는 줄이지 않는다.
      final r = dedupeSameDevicePreferringCom([
        com('COM3', hardwareId: pr800HardwareId),
        usb('PR800', path: pr800UsbPath),
        usb('A8', path: a8UsbPath),
      ]);
      expect(r.map((t) => t.uiValue), ['com:COM3', 'usbprint:$a8UsbPath']);
    });

    test('VID/PID 를 못 뽑는 COM(물리 RS-232)은 아무것도 버리지 않는다', () {
      final r = dedupeSameDevicePreferringCom([
        com('COM1'), // hardwareId 없음
        usb('A8', path: a8UsbPath),
      ]);
      expect(r.map((t) => t.uiValue), ['com:COM1', 'usbprint:$a8UsbPath']);
    });

    test('COM 후보가 아예 없으면 원본을 그대로 돌려준다', () {
      final input = [usb('A8', path: a8UsbPath)];
      expect(dedupeSameDevicePreferringCom(input), same(input));
    });

    test('이미 usbprint 로 쓰고 있으면 그 항목은 남긴다 — 드롭다운이 "미선택"이 되면 안 된다', () {
      final saved = usb('PR800', path: pr800UsbPath);
      final r = dedupeSameDevicePreferringCom(
        [com('COM3', hardwareId: pr800HardwareId), saved],
        keep: saved,
      );
      expect(r.map((t) => t.uiValue), ['com:COM3', 'usbprint:$pr800UsbPath']);
    });

    test('저장 대상이 COM 이면 usbprint 중복은 평소대로 사라진다', () {
      final r = dedupeSameDevicePreferringCom(
        [
          com('COM3', hardwareId: pr800HardwareId),
          usb('PR800', path: pr800UsbPath)
        ],
        keep: com('COM3', hardwareId: pr800HardwareId),
      );
      expect(r.map((t) => t.uiValue), ['com:COM3']);
    });

    test('COM 끼리는 서로 지우지 않는다', () {
      final r = dedupeSameDevicePreferringCom([
        com('COM3', hardwareId: pr800HardwareId),
        com('COM5', hardwareId: pr800HardwareId),
      ]);
      expect(r.map((t) => t.uiValue), ['com:COM3', 'com:COM5']);
    });

    test('제거 후 스캔 순서에 usbprint 중복이 남지 않는다', () {
      final r = orderScanCandidates(
        dedupeSameDevicePreferringCom([
          com('COM3', hardwareId: pr800HardwareId),
          usb('PR800', path: pr800UsbPath),
        ]),
        null,
      );
      expect(r.map((t) => t.uiValue), ['com:COM3']);
    });
  });

  group('usbIdKeyOrNull', () {
    test('usbprint 는 장치 경로에서, COM 은 hardwareId 에서 같은 키를 뽑는다', () {
      final u = usb('PR800',
          path: r'\\?\usb#vid_0d28&pid_4c59&mi_00#7&25e4af7&0&0000#{guid}');
      final c = com('COM3', hardwareId: r'USB\VID_0D28&PID_4C59&MI_01\x');
      expect(u.usbIdKeyOrNull, '0D28:4C59');
      expect(c.usbIdKeyOrNull, equals(u.usbIdKeyOrNull));
    });

    test('VID/PID 가 없으면 null', () {
      expect(com('COM1').usbIdKeyOrNull, isNull);
      expect(usb('X', path: 'nonsense').usbIdKeyOrNull, isNull);
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
        knownColumnsForDeviceString(
            r'USB\VID_0D28&PID_4C59&MI_01\6&abc&0&0001'),
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
