import 'dart:convert' show utf8;
import 'dart:typed_data';

import 'package:serial_port_win32/serial_port_win32.dart';

import '../utils/logger.dart';

/// Windows COM 포트로 직접 ESC/POS 명령을 전송하는 프린터 서비스.
/// PR800 같은 시리얼 영수증 프린터용.
class ComPortPrintService {
  static const String defaultComPort = 'COM3';
  static const int defaultBaudRate = 9600;

  /// COM 포트 목록 조회 (예: ['COM1', 'COM2', 'COM3'])
  static List<String> getAvailableComPorts() {
    try {
      final ports = SerialPort.getAvailablePorts();
      logger.i('[ComPortPrint] Available COM ports: $ports');
      return ports;
    } catch (e, s) {
      logger.e('[ComPortPrint] Failed to get COM ports', error: e, stackTrace: s);
      return [];
    }
  }

  /// COM 포트로 바이트 데이터 전송
  static Future<bool> sendRaw(
    Uint8List data, {
    String comPort = defaultComPort,
    int baudRate = defaultBaudRate,
  }) async {
    try {
      // 포트 객체 얻기 (Singleton 패턴)
      final port = SerialPort(comPort);

      // 기존에 열려있으면 닫기
      if (port.isOpened) {
        logger.d('[ComPortPrint] Port already opened, closing...');
        try {
          port.close();
          await Future.delayed(const Duration(milliseconds: 100));
        } catch (e) {
          logger.w('[ComPortPrint] Error closing existing port: $e');
        }
      }

      // 포트 열기 (BaudRate 설정)
      port.openWithSettings(
        BaudRate: baudRate,
        ByteSize: 8,
        StopBits: 1,
        Parity: 0, // 0 = NOPARITY
      );

      // 포트 열기 확인
      if (!port.isOpened) {
        logger.e('[ComPortPrint] Failed to open $comPort');
        return false;
      }

      logger.d('[ComPortPrint] Opened $comPort with baud rate $baudRate');

      // 데이터 전송
      try {
        port.writeBytesFromUint8List(data);
        logger.i('[ComPortPrint] Successfully sent ${data.length} bytes to $comPort');
        return true;
      } catch (writeError, writeStack) {
        logger.e('[ComPortPrint] Write failed', error: writeError, stackTrace: writeStack);
        return false;
      } finally {
        // 포트 닫기
        try {
          port.close();
          logger.d('[ComPortPrint] Closed port');
        } catch (closeError) {
          logger.w('[ComPortPrint] Error closing port: $closeError');
        }
      }
    } catch (e, s) {
      logger.e('[ComPortPrint] Error sending data', error: e, stackTrace: s);
      return false;
    }
  }

  /// 테스트 페이지를 COM 포트로 출력
  static Future<bool> printTestPage({
    String comPort = defaultComPort,
    int baudRate = defaultBaudRate,
  }) async {
    try {
      // 간단한 ESC/POS 테스트 명령
      const commands = <int>[
        // 프린터 초기화
        0x1B, 0x40,
        // 정렬: 가운데
        0x1B, 0x61, 0x01,
      ];

      // 텍스트 추가: "TEST PRINT"
      final testText = 'TEST PRINT\n';
      final textBytes = utf8.encode(testText);

      // 명령 합치기
      final allBytes = <int>[...commands, ...textBytes];

      // 개행 추가
      allBytes.addAll([0x0A, 0x0A]);

      // 정렬: 좌측
      allBytes.addAll([0x1B, 0x61, 0x00]);

      // 용지 커팅
      allBytes.addAll([0x1D, 0x56, 0x01]);

      final data = Uint8List.fromList(allBytes);
      return await sendRaw(data, comPort: comPort, baudRate: baudRate);
    } catch (e, s) {
      logger.e('[ComPortPrint] Error printing test page', error: e, stackTrace: s);
      return false;
    }
  }
}
