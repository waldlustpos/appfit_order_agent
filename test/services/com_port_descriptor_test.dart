import 'package:flutter_test/flutter_test.dart';

import 'package:appfit_order_agent/services/com_port_descriptor.dart';

/// COM 포트 재연결 스캔의 순수 로직 검증.
///
/// 실제 열거/probe 는 Windows native (SetupAPI / serial_port_win32) 라 여기서
/// 돌릴 수 없다. 대신 native 결과를 받아 **어떤 순서로 probe 할지** 와 **화면에
/// 뭐라고 보여줄지** 만 떼어내 검증한다 — 회귀가 실제로 나는 지점이 여기다.
void main() {
  group('orderProbeCandidates', () {
    test('저장 포트를 맨 앞에 두고 중복 없이 이어붙인다', () {
      expect(
        orderProbeCandidates(['COM1', 'COM3', 'COM7'], 'COM3'),
        ['COM3', 'COM1', 'COM7'],
      );
    });

    test('저장 포트가 목록에 없어도 후보 맨 앞에 포함한다', () {
      // 열거가 순간적으로 포트를 놓치는 경우(USB re-enumerate lag)가 있어
      // 목록만 믿지 않고 실제로 열어본다. 없으면 probe 진입 가드가 걸러낸다.
      expect(
        orderProbeCandidates(['COM1', 'COM7'], 'COM3'),
        ['COM3', 'COM1', 'COM7'],
      );
    });

    test('저장 포트가 null 이면 열거 순서 그대로', () {
      expect(
        orderProbeCandidates(['COM1', 'COM7'], null),
        ['COM1', 'COM7'],
      );
    });

    test('빈 목록 + 저장 포트 없음이면 후보도 비어 스캔을 건너뛴다', () {
      expect(orderProbeCandidates(const [], null), isEmpty);
    });

    test('빈 목록이라도 저장 포트가 있으면 그 하나는 시도한다', () {
      expect(orderProbeCandidates(const [], 'COM3'), ['COM3']);
    });

    test('열거 결과의 중복/공백 항목을 제거한다', () {
      // getAvailablePorts() 는 레지스트리 열거 실패 시 빈 문자열을 넣는다
      // (serial_port_win32 1.4.2 getAvailablePorts 참조).
      expect(
        orderProbeCandidates(['COM1', '', 'COM1', '  ', 'COM7'], null),
        ['COM1', 'COM7'],
      );
    });

    test('저장 포트가 공백이면 후보에서 제외한다', () {
      expect(orderProbeCandidates(['COM1'], '  '), ['COM1']);
    });
  });

  group('ComPortDescriptor.displayLabel', () {
    test('식별 정보가 없으면 포트명만', () {
      expect(const ComPortDescriptor(portName: 'COM3').displayLabel, 'COM3');
    });

    test('friendlyName 끝의 포트명 접미사를 제거해 중복 표기를 막는다', () {
      const d = ComPortDescriptor(
        portName: 'COM5',
        friendlyName: 'Prolific PL2303GT USB Serial COM Port (COM5)',
      );
      expect(d.displayLabel, 'COM5 · Prolific PL2303GT USB Serial COM Port');
    });

    test('접미사가 다른 포트명이면 그대로 둔다', () {
      const d = ComPortDescriptor(
        portName: 'COM5',
        friendlyName: 'USB Serial Device (COM9)',
      );
      expect(d.displayLabel, 'COM5 · USB Serial Device (COM9)');
    });

    test('friendlyName 이 없으면 manufacturer 로 대체', () {
      const d = ComPortDescriptor(portName: 'COM5', manufacturer: 'Prolific');
      expect(d.displayLabel, 'COM5 · Prolific');
    });

    test('빈 문자열/공백 식별 정보는 없는 것으로 본다', () {
      const d = ComPortDescriptor(
        portName: 'COM5',
        friendlyName: '   ',
        manufacturer: '',
      );
      expect(d.displayLabel, 'COM5');
    });

    test('friendlyName 이 포트명 접미사뿐이면 원문을 유지한다', () {
      // 접미사만 떼면 빈 문자열이 되어 'COM5 · ' 로 보이는 걸 막는다.
      const d = ComPortDescriptor(portName: 'COM5', friendlyName: ' (COM5)');
      expect(d.displayLabel, 'COM5 · (COM5)');
    });
  });
}
