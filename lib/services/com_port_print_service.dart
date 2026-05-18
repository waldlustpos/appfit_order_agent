import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:serial_port_win32/serial_port_win32.dart';
import 'package:win32/win32.dart';

import '../utils/logger.dart';
import 'receipt_escpos_builder.dart';

/// Windows COM 포트로 직접 ESC/POS 명령을 전송하는 프린터 서비스.
/// PR800 같은 시리얼 영수증 프린터용.
///
/// 매장 운영 환경에서 확인된 false-success 문제 해결:
/// USB-Serial 가상 COM 포트(NXP CDC 등) 는 프린터 본체 전원만 꺼도 PC USB bus
/// power 로 CDC 칩이 살아있어 포트가 유지된다. 결과적으로
/// [SerialPort.openWithSettings] / [SerialPort.writeBytesFromUint8List] 가
/// 모두 성공하지만 데이터는 chip 내부 buffer 까지만 도달하고 print head 에
/// 전달되지 않는다. 이를 막기 위해 [_probePrinter] 가 ESC/POS 실시간 상태
/// 명령(DLE EOT 1) 을 보내고 응답 폴링으로 디바이스가 살아있는지 확인한다.
class ComPortPrintService {
  static const String defaultComPort = 'COM3';
  static const int defaultBaudRate = 9600;

  /// ESC/POS real-time status transmission (Transmit printer status).
  /// 표준상 모든 ESC/POS 호환 프린터가 지원하며, 다른 명령 처리 중에도
  /// in-band 로 즉시 1바이트 응답을 돌려준다.
  static const List<int> _dleEot1 = [0x10, 0x04, 0x01];

  /// probe 응답 대기 총 시간. CDC 가상 COM 의 RX 지연을 흡수할 만큼 여유 두되,
  /// backoff 첫 단계(2s) 안에 의미 있게 끝나도록 짧게.
  static const Duration _probeTimeout = Duration(milliseconds: 300);

  /// RX buffer polling 간격.
  static const Duration _probePollInterval = Duration(milliseconds: 20);

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

      try {
        // ESC/POS DLE EOT 1 핑으로 디바이스 생존 확인. probe 실패 = 오프라인
        // 또는 응답 안 함 -> sendRaw false -> PrinterJobQueue backoff 재시도.
        final alive = await _probePrinter(port);
        if (!alive) {
          logger.w(
              '[ComPortPrint] Probe failed: no response from $comPort within '
              '${_probeTimeout.inMilliseconds}ms -- printer offline?');
          return false;
        }

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
        }
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

  /// ESC/POS DLE EOT 1 핑으로 디바이스 생존을 확인한다.
  ///
  /// 1) RX 버퍼 비우기 (이전 잡 잔재 제거)
  /// 2) DLE EOT 1 전송 -- 표준 ESC/POS 는 즉시 1바이트 상태로 응답
  /// 3) [_probeTimeout] 안에 ClearCommError 의 cbInQue 가 > 0 되는지 폴링
  /// 4) 응답 확인되면 RX 비우고 true. 없으면 false.
  ///
  /// USB-Serial CDC 가상 COM 에서 본체 전원만 꺼진 경우 chip 자체는 살아
  /// 있지만 print head 가 응답 안 하므로 cbInQue 가 0 으로 유지되어 정확히
  /// 오프라인 판정 가능. 케이블 분리 / 다른 프로세스 점유 케이스는 어차피
  /// open 단계에서 실패하므로 여기까지 오지 않는다.
  static Future<bool> _probePrinter(SerialPort port) async {
    final handle = port.handler;
    if (handle == null) {
      logger.w('[ComPortPrint] probe: handler null');
      return false;
    }

    // 1) RX 버퍼 비우기 - 이전 응답 잔재 제거.
    try {
      PurgeComm(handle, PURGE_RXCLEAR);
    } catch (e) {
      logger.w('[ComPortPrint] PurgeComm before probe failed: $e');
    }

    // 2) DLE EOT 1 전송. 패키지의 write 사용 -- 자체 OVERLAPPED 관리.
    final probeBytes = Uint8List.fromList(_dleEot1);
    try {
      final written = port.writeBytesFromUint8List(probeBytes, timeout: 200);
      if (!written) {
        logger.w('[ComPortPrint] probe write returned false');
        return false;
      }
    } catch (e) {
      logger.w('[ComPortPrint] probe write threw: $e');
      return false;
    }

    // 3) RX buffer polling.
    final errors = calloc<Uint32>();
    final status = calloc<COMSTAT>();
    try {
      final deadline = DateTime.now().add(_probeTimeout);
      while (DateTime.now().isBefore(deadline)) {
        final ok = ClearCommError(handle, errors, status);
        if (ok != 0 && status.ref.cbInQue > 0) {
          // 응답 도착. 잔류 바이트가 다음 잡에 섞이지 않게 비운다.
          try {
            PurgeComm(handle, PURGE_RXCLEAR);
          } catch (_) {}
          return true;
        }
        await Future.delayed(_probePollInterval);
      }
      return false;
    } finally {
      calloc.free(errors);
      calloc.free(status);
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
