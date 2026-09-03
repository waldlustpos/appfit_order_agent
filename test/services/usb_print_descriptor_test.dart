import 'package:flutter_test/flutter_test.dart';

import 'package:appfit_order_agent/services/usb_print_descriptor.dart';

/// usbprint 장치 식별 값 객체 / 경로 파싱 characterization.
///
/// 이 파싱은 단순한 표시용이 아니다 — `UsbPrintService` 의 **라벨 프린터 제외**가
/// 여기서 나온 VID 로 판정되므로, 파싱이 깨지면 영수증 경로가 라벨 프린터를
/// 후보로 노출한다(2026-09-01 G30 선점 사고와 같은 계열). Windows 없이 돌 수 있는
/// 순수 함수라 여기서 고정한다.
void main() {
  // 본 PC 실측 경로 형태. usbprint 인터페이스 경로는 소문자 16진수로 나온다.
  const a8Path =
      r'\\?\usb#vid_0483&pid_a319#207f38734b30#{28d78fad-5a12-11d1-ae5b-0000f803a8c2}';

  group('parseUsbIdsFromDevicePath', () {
    test('소문자 경로에서 VID/PID 를 뽑는다', () {
      final ids = parseUsbIdsFromDevicePath(a8Path);
      expect(ids.vendorId, 0x0483);
      expect(ids.productId, 0xA319);
    });

    test('대문자 경로도 동일하게 파싱한다 — OS/드라이버 버전에 따라 표기가 갈린다', () {
      final ids = parseUsbIdsFromDevicePath(a8Path.toUpperCase());
      expect(ids.vendorId, 0x0483);
      expect(ids.productId, 0xA319);
    });

    test('라벨 프린터 VID 도 정확히 읽힌다 — 제외 판정의 입력', () {
      // BIXOLON G30 (0x1504) / Caysn (0x4B43) / REXOD (0x0FE6).
      expect(
        parseUsbIdsFromDevicePath(r'\\?\usb#vid_1504&pid_0147#...').vendorId,
        0x1504,
      );
      expect(
        parseUsbIdsFromDevicePath(r'\\?\usb#vid_0fe6&pid_811e#...').vendorId,
        0x0FE6,
      );
    });

    test('뒤따르는 GUID 의 16진수에 속지 않는다', () {
      // GUID 안에도 4자리 16진수가 널려 있으므로 vid_/pid_ 앵커가 필수다.
      final ids = parseUsbIdsFromDevicePath(a8Path);
      expect(ids.vendorId, isNot(0x28d7));
    });

    test('VID/PID 가 없으면 null — 이때는 라벨 제외가 걸리지 않는다(fail-open)', () {
      // 의도적 fail-open: 파싱 실패로 전부 제외하면 정작 쓰려는 영수증 프린터가
      // 목록에서 사라진다. 오선택 방지는 "사용자가 friendlyName 을 보고 명시적으로
      // 고른다" 는 상위 규율이 맡는다.
      final ids = parseUsbIdsFromDevicePath(r'\\?\usb#somethingelse#...');
      expect(ids.vendorId, isNull);
      expect(ids.productId, isNull);
    });
  });

  group('UsbPrintDescriptor.displayLabel', () {
    test('이름 + VID:PID — 같은 모델 두 대를 구분할 수 있어야 한다', () {
      const d = UsbPrintDescriptor(
        devicePath: a8Path,
        friendlyName: 'EASYSET PBP_A8',
        vendorId: 0x0483,
        productId: 0xA319,
      );
      expect(d.displayLabel, 'EASYSET PBP_A8 (0483:A319)');
      expect(d.hexIds, '0483:A319');
    });

    test('이름이 없으면 일반 명칭으로 대체하되 식별자는 유지한다', () {
      const d = UsbPrintDescriptor(
        devicePath: a8Path,
        vendorId: 0x0483,
        productId: 0xA319,
      );
      expect(d.displayLabel, 'USB 프린터 (0483:A319)');
    });

    test('식별자가 없으면 이름만', () {
      const d = UsbPrintDescriptor(
        devicePath: a8Path,
        friendlyName: '  EASYSET PBP_A8  ',
      );
      expect(d.displayLabel, 'EASYSET PBP_A8');
      expect(d.hexIds, isNull);
    });

    test('VID 를 4자리로 zero-pad 한다 (0x0FE6 → 0FE6)', () {
      const d = UsbPrintDescriptor(
        devicePath: '',
        vendorId: 0x0FE6,
        productId: 0x811E,
      );
      expect(d.hexIds, '0FE6:811E');
    });
  });
}
