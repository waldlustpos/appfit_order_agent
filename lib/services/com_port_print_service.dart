import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:serial_port_win32/serial_port_win32.dart';
import 'package:win32/win32.dart';

import '../utils/logger.dart';
import 'platform_service.dart';
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
///
/// 추가 방어 (re-enumerate lag / 외부 프로세스 점유 / 패키지 cache 잔재):
/// - 진입 시 enumerate 결과로 노드 존재 검증 → 없으면 즉시 false (noDevice).
/// - close 후 enumerate polling 으로 OS USB stack release 완료 확인.
/// - 직전 실패 직후라면 settle 에 failure-cooldown 250ms 추가.
/// - 외부 catch 진입 시 stale handle 정리용 안전 close + 사유 분류 진단 로그.
///
/// 실패 사유 정밀 분류는 [lastFailureReason] 에 기록되며, `WindowsTransport`
/// 가 이를 읽어 PrinterBusy / PrinterNoDevice / PrinterTransportError 로 분류한다.
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

  /// close 후 OS USB stack release / enumerate 가 끝났는지 능동 확인하는 폴링.
  /// 25ms 간격으로 [SerialPort.getAvailablePorts] 가 해당 포트를 다시 보고하는지
  /// 점검 → 정상 환경에서는 첫 폴링(25ms) 에 통과해 종전 100ms 고정 대기보다
  /// 빠르게 다음 open 으로 진입한다. 300ms 안에도 enumerate 못하면 그 자체로
  /// re-enumerate lag 로 판정해 false 반환 → backoff 로 자연 복구.
  static const Duration _closeSettlePollInterval = Duration(milliseconds: 25);
  static const Duration _closeSettleTimeout = Duration(milliseconds: 300);

  /// 직전 성공 sendRaw 시각. settle delay 가 warm/cold 경로를 판별하는 데 사용.
  static DateTime? _lastSuccessfulSendAt;

  /// 직전 실패 sendRaw 시각. failure-cooldown 진입 판정.
  static DateTime? _lastFailureAt;

  /// 직전 false 반환의 정확한 사유. `WindowsTransport` 가 결과 분류에 사용.
  /// success 시 null 로 초기화된다.
  ///
  /// 값 도메인 (관용적 enum 대신 문자열로 두는 이유: 이 파일 외부에서 패턴
  /// 매칭만 하고, 의미는 호출 측 분류 표에서 정의):
  /// - 'not-enumerated'                : 진입 시 포트 enumerate 결과에 없음
  /// - 'enumerate-timeout-after-close' : close 후 300ms 안에 재 enumerate 못함
  /// - 'open-throws-file-not-found'    : openWithSettings 가 "is not available"
  /// - 'open-throws-access-denied'     : openWithSettings 가 win32 error 5
  /// - 'open-throws-other'             : openWithSettings 가 그 외 예외
  /// - 'open-failed-silent'            : isOpened 가 false (예외 없이 실패)
  /// - 'probe-write-failed'            : DLE EOT 1 write 가 false / throw
  /// - 'probe-timeout'                 : RX 폴링 timeout (응답 없음)
  /// - 'write-exception'               : 본 데이터 writeBytesFromUint8List 예외
  static String? _lastFailureReason;

  /// 외부에서 마지막 실패 사유를 읽기 위한 접근자. (transport 분류용)
  static String? get lastFailureReason => _lastFailureReason;

  /// warm path 윈도우 — 마지막 성공 send 후 이 시간 안에 다시 보내면
  /// 포트/프린터가 이미 안정 상태라고 판단해 settle delay 를 짧게 가져간다.
  static const Duration _warmWindow = Duration(seconds: 60);

  /// failure-cooldown 윈도우 — 직전 실패 후 이 시간 안에 다시 보내면 cold
  /// settle 위에 추가 250ms 를 더해 USB-Serial CDC 재 enumerate / OS release
  /// lag 가 자연 풀리도록 시간을 더 준다.
  static const Duration _failureCooldownWindow = Duration(milliseconds: 500);

  static const Duration _settleWarm = Duration(milliseconds: 150);
  static const Duration _settleCold = Duration(milliseconds: 1500);
  static const Duration _settleFailureCooldown = Duration(milliseconds: 250);

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

  /// 포트가 OS USB stack 에서 다시 enumerate 될 때까지 폴링.
  /// 정상 환경에서는 첫 폴링(25ms) 에 통과. 300ms 안에도 못 보면 lag 판정.
  static Future<bool> _waitPortEnumerated(String comPort) async {
    final deadline = DateTime.now().add(_closeSettleTimeout);
    while (DateTime.now().isBefore(deadline)) {
      try {
        final ports = SerialPort.getAvailablePorts();
        if (ports.contains(comPort)) return true;
      } catch (_) {
        // enumerate 자체가 일시 예외라도 다음 폴링에서 회복 가능.
      }
      await Future.delayed(_closeSettlePollInterval);
    }
    return false;
  }

  /// 외부 catch 진입 시 cache 인스턴스의 stale handle 정리.
  /// CloseHandle 은 INVALID_HANDLE_VALUE 에도 ERROR_INVALID_HANDLE 만 줄 뿐
  /// throw 하지 않으므로 try-catch 로 안전하게 호출 가능.
  static void _safeClose(SerialPort port) {
    try {
      if (port.isOpened) port.close();
    } catch (_) {
      // 정리 시도일 뿐, 실패해도 다음 폴링 / backoff 가 흡수.
    }
  }

  /// COM 포트로 바이트 데이터 전송
  static Future<bool> sendRaw(
    Uint8List data, {
    String comPort = defaultComPort,
    int baudRate = defaultBaudRate,
  }) async {
    _lastFailureReason = null;
    SerialPort? port;
    try {
      // serial_port_win32 레지스트리 enumerate. SerialPort 싱글턴 캐시 리셋
      // 효과를 노린 보조책 (사용자 환경에서 "재연결 버튼 직후만 정상" 패턴 대응).
      // 결과를 활용해 진입 단계에서 빠르게 noDevice 차단 — 현재 USB stack 에
      // 노드 자체가 없으면 openWithSettings 가 throw 까지 가는 진단 노이즈를
      // 줄인다.
      List<String> ports = const [];
      try {
        ports = SerialPort.getAvailablePorts();
      } catch (_) {}
      if (!ports.contains(comPort)) {
        _lastFailureReason = 'not-enumerated';
        _lastFailureAt = DateTime.now();
        logToFile(
            tag: LogTag.PLATFORM,
            message:
                '[ComPortPrint] $comPort 가 enumerate 결과에 없음 — 즉시 noDevice (다음 attempt backoff 안에서 자연 복구 예상)');
        return false;
      }

      // 포트 객체 얻기. openNow: false 로 팩토리가 자동으로 default 115200 baud
      // 로 열지 않도록 지정한다. (싱글턴 캐시: 첫 호출의 인자만 적용되지만,
      // 이후엔 어차피 openWithSettings 가 dcb 를 우리 baud 로 갱신하고 open 함.)
      port = SerialPort(comPort, openNow: false);
      logger.d('[ComPortPrint] Pre-open: isOpened=${port.isOpened}');

      // 기존에 열려있으면 닫기. 100ms 고정 대기 대신 OS USB stack 의 release
      // 가 끝났는지 enumerate 폴링으로 능동 확인 (USB-Serial CDC re-enumerate lag).
      if (port.isOpened) {
        logger.d('[ComPortPrint] Port already opened, closing...');
        try {
          port.close();
        } catch (e) {
          logger.w('[ComPortPrint] Error closing existing port: $e');
        }
        final ok = await _waitPortEnumerated(comPort);
        if (!ok) {
          _lastFailureReason = 'enumerate-timeout-after-close';
          _lastFailureAt = DateTime.now();
          logToFile(
              tag: LogTag.WARNING,
              message:
                  '[ComPortPrint] $comPort enumerate timeout (close 후 ${_closeSettleTimeout.inMilliseconds}ms) — USB stack release lag');
          return false;
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
        _lastFailureReason = 'open-failed-silent';
        _lastFailureAt = DateTime.now();
        logger.e('[ComPortPrint] Failed to open $comPort (silent)');
        return false;
      }

      logger.d('[ComPortPrint] Opened $comPort with baud rate $baudRate');

      // Settle delay 적응형 (3-way):
      // - failure-cooldown (직전 실패 후 _failureCooldownWindow 이내):
      //   cold 위에 _settleFailureCooldown 추가. USB-Serial CDC re-enumerate
      //   / OS release lag 가 풀릴 시간을 더 준다.
      // - cold path (첫 open 또는 직전 성공 후 _warmWindow 경과): 1.5초.
      //   PR800 펌웨어 부팅 또는 USB-Serial 재인식 직후 명령 무시 방지.
      // - warm path (직전 성공 후 _warmWindow 이내): 150ms.
      //   연속 영수증 출력 등 정상 흐름에서 체감 지연 최소화.
      final now = DateTime.now();
      final lastSend = _lastSuccessfulSendAt;
      final lastFail = _lastFailureAt;
      final isWarm = lastSend != null && now.difference(lastSend) < _warmWindow;
      final isFailureCooldown =
          lastFail != null && now.difference(lastFail) < _failureCooldownWindow;
      final Duration settle;
      final String settleLabel;
      if (isFailureCooldown) {
        settle = _settleCold + _settleFailureCooldown;
        settleLabel = 'failure-cooldown';
      } else if (isWarm) {
        settle = _settleWarm;
        settleLabel = 'warm';
      } else {
        settle = _settleCold;
        settleLabel = 'cold';
      }
      logger.d(
          '[ComPortPrint] Settle delay: ${settle.inMilliseconds}ms ($settleLabel)');
      await Future.delayed(settle);

      try {
        // ESC/POS DLE EOT 1 핑으로 디바이스 생존 확인. probe 실패 = 오프라인
        // 또는 응답 안 함 → sendRaw false → PrinterJobQueue backoff 재시도.
        final alive = await _probePrinter(port);
        if (!alive) {
          // _probePrinter 내부에서 _lastFailureReason 을 'probe-timeout' /
          // 'probe-write-failed' 로 이미 세팅.
          _lastFailureAt = DateTime.now();
          logger.w(
              '[ComPortPrint] Probe failed: no response from $comPort within '
              '${_probeTimeout.inMilliseconds}ms — printer offline?');
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
          _lastFailureReason = null;
          return true;
        } catch (writeError, writeStack) {
          _lastFailureReason = 'write-exception';
          _lastFailureAt = DateTime.now();
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
      // openWithSettings 같은 함수가 throw 한 경우 try 안쪽 finally 가 실행되지
      // 않으므로 여기서 stale handle 정리. cache 인스턴스 안의 _isOpened 가
      // false 로 강제 reset 되어 다음 호출이 깨끗한 출발점에서 시작.
      if (port != null) _safeClose(port);
      _lastFailureAt = DateTime.now();
      // 예외 메시지 패턴으로 사유 분류 + 운영 진단 로그.
      final msg = e.toString();
      final lower = msg.toLowerCase();
      if (msg.contains('is not available')) {
        // serial_port_win32 가 CreateFile 에서 ERROR_FILE_NOT_FOUND (= 2) 받았을 때.
        // = USB-Serial CDC 가상 COM 이 일시 enumerate 에서 사라진 상태.
        _lastFailureReason = 'open-throws-file-not-found';
        logToFile(
            tag: LogTag.PLATFORM,
            message:
                '[ComPortPrint] $comPort enumerate lag — 다음 attempt backoff 안에서 자연 복구 예상');
      } else if (msg.contains('win32 error code is 5') ||
          (lower.contains('access') && lower.contains('denied'))) {
        // ERROR_ACCESS_DENIED (= 5). 다른 프로세스가 점유 중.
        _lastFailureReason = 'open-throws-access-denied';
        logToFile(
            tag: LogTag.WARNING,
            message:
                '[ComPortPrint] $comPort access denied — 외부 프로세스(POS/유틸) 점유 의심');
      } else {
        _lastFailureReason = 'open-throws-other';
      }
      logger.e('[ComPortPrint] Error sending data', error: e, stackTrace: s);
      return false;
    }
  }

  /// ESC/POS DLE EOT 1 핑으로 디바이스 생존을 확인한다.
  ///
  /// 1) RX 버퍼 비우기 (이전 잡 잔재 제거)
  /// 2) DLE EOT 1 전송 — 표준 ESC/POS 는 즉시 1바이트 상태로 응답
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
      _lastFailureReason = 'probe-write-failed';
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
        _lastFailureReason = 'probe-write-failed';
        logger.w('[ComPortPrint] probe write returned false');
        return false;
      }
    } catch (e) {
      _lastFailureReason = 'probe-write-failed';
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
      _lastFailureReason = 'probe-timeout';
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
