import 'dart:typed_data';

import 'package:serial_port_win32/serial_port_win32.dart';

import '../utils/logger.dart';
import 'receipt_escpos_builder.dart';

/// Windows COM 포트로 직접 ESC/POS 명령을 전송하는 프린터 서비스.
/// PR800 같은 시리얼 영수증 프린터용.
class ComPortPrintService {
  static const String defaultComPort = 'COM3';
  static const int defaultBaudRate = 9600;

  /// 직전 성공 sendRaw 시각. settle delay 가 warm/cold 경로를 판별하는 데 사용.
  static DateTime? _lastSuccessfulSendAt;

  /// warm path 윈도우 — 마지막 성공 send 후 이 시간 안에 다시 보내면
  /// 포트/프린터가 이미 안정 상태라고 판단해 settle delay 를 짧게 가져간다.
  static const Duration _warmWindow = Duration(seconds: 60);
  static const Duration _settleWarm = Duration(milliseconds: 150);
  static const Duration _settleCold = Duration(milliseconds: 1500);

  /// COM 포트 목록 조회 (예: ['COM1', 'COM2', 'COM3'])
  static List<String> getAvailableComPorts() {
    try {
      final ports = SerialPort.getAvailablePorts();
      logger.i('[ComPortPrint] Available COM ports: $ports');
      return ports;
    } catch (e, s) {
      logger.e('[ComPortPrint] Failed to get COM ports',
          error: e, stackTrace: s);
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
      // serial_port_win32 레지스트리 enumerate. SerialPort 싱글턴 캐시 리셋
      // 효과를 노린 보조책 (사용자 환경에서 "재연결 버튼 직후만 정상" 패턴에 대응).
      try {
        SerialPort.getAvailablePorts();
      } catch (_) {}

      // 포트 객체 얻기. openNow: false 로 팩토리가 자동으로 default 115200 baud
      // 로 열지 않도록 지정한다. (싱글턴 캐시: 첫 호출의 인자만 적용되지만,
      // 이후엔 어차피 openWithSettings 가 dcb 를 우리 baud 로 갱신하고 open 함.)
      final port = SerialPort(comPort, openNow: false);
      logger.d('[ComPortPrint] Pre-open: isOpened=${port.isOpened}');

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

      // Settle delay 적응형:
      // - cold path (첫 open 또는 마지막 성공 send 후 _warmWindow 경과): 1.5초.
      //   PR800 펌웨어 부팅 또는 USB-Serial 재인식 직후 명령 무시 방지.
      // - warm path (직전 성공 후 _warmWindow 이내): 150ms.
      //   연속 영수증 출력 등 정상 흐름에서 체감 지연 최소화.
      final lastSend = _lastSuccessfulSendAt;
      final isWarm =
          lastSend != null && DateTime.now().difference(lastSend) < _warmWindow;
      final settle = isWarm ? _settleWarm : _settleCold;
      logger.d(
          '[ComPortPrint] Settle delay: ${settle.inMilliseconds}ms (${isWarm ? 'warm' : 'cold'})');
      await Future.delayed(settle);

      // 데이터 전송
      try {
        port.writeBytesFromUint8List(data);
        logger.i(
            '[ComPortPrint] Successfully sent ${data.length} bytes to $comPort');
        // Drain delay 동적 계산: 8N1 기준 1바이트 = 10비트.
        // 실제 wire 전송 시간 + 200ms 안전 마진.
        // 256B@9600 ≈ 467ms, 1KB@9600 ≈ 1242ms, 1KB@115200 ≈ 287ms.
        final transmitMs = (data.length * 10 * 1000 / baudRate).ceil();
        final drainMs = transmitMs + 200;
        await Future.delayed(Duration(milliseconds: drainMs));
        _lastSuccessfulSendAt = DateTime.now();
        return true;
      } catch (writeError, writeStack) {
        logger.e('[ComPortPrint] Write failed',
            error: writeError, stackTrace: writeStack);
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

  /// 테스트 페이지를 COM 포트로 출력.
  ///
  /// 출력물은 [ReceiptEscPosBuilder.buildTestPageBytes] 가 만든 동일 레이아웃을
  /// Android 외부 프린터 경로(MethodChannel `printReceiptSegments`)와 공유한다.
  static Future<bool> printTestPage({
    String comPort = defaultComPort,
    int baudRate = defaultBaudRate,
  }) async {
    try {
      final data = await ReceiptEscPosBuilder.buildTestPageBytes(
        comPort: comPort,
        baudRate: baudRate,
      );
      return await sendRaw(data, comPort: comPort, baudRate: baudRate);
    } catch (e, s) {
      logger.e('[ComPortPrint] Error printing test page',
          error: e, stackTrace: s);
      return false;
    }
  }
}
