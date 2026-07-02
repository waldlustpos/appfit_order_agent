import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:serial_port_win32/serial_port_win32.dart';
import 'package:win32/win32.dart';

import 'package:appfit_order_agent/utils/logger.dart';
import 'package:appfit_order_agent/services/platform_service.dart';
import 'package:appfit_order_agent/services/receipt_escpos_builder.dart';

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

  /// PR800 시리얼(RS-232) 포트는 115200 고정 (2026-07 COM6 실기: 9600~57600
  /// 무응답, 115200 만 DLE EOT 응답). USB-CDC 가상 COM 은 baud 를 무시하므로
  /// 모든 연결타입 공통 기본값으로 안전하다. PreferenceService /
  /// ExternalPrinterSubSettings 의 기본값과 함께 유지할 것.
  static const int defaultBaudRate = 115200;

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
  /// - 'probe-write-failed'            : DLE EOT 1 write 가 throw
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

  /// 연결 검증(probeConnection) 의 open 직후 1차 안정화 대기. 이후 핑이 실패하면
  /// [_probeRetryInterval] 간격으로 [_probeMaxAttempts] 회까지 재시도하므로 짧게
  /// 둔다. (살아있는 프린터는 1차 시도에 즉시 통과, 죽은 프린터만 한도까지 대기.)
  static const Duration _settleProbe = Duration(milliseconds: 250);

  /// probeConnection 핑 재시도 간격 / 최대 횟수. open 직후 USB-Serial 재인식 ·
  /// 펌웨어 idle 회복 타이밍 편차(수백ms~1.5s) 를 흡수하기 위함. 실제 출력
  /// 경로(sendRaw cold settle 1.5s) 와 달리 "살아있으면 빨리, 죽었으면 확실히"
  /// 를 위해 고정 대기 대신 점진적 재시도를 쓴다.
  static const Duration _probeRetryInterval = Duration(milliseconds: 250);
  static const int _probeMaxAttempts = 5;

  /// 최근 성공 출력 직후엔 프린터가 살아있음이 입증된 상태이므로 포트를 다시
  /// 열어 핑하지 않고(불필요한 포트 토글로 인한 간섭 방지) 연결됨으로 본다.
  static const Duration _recentSendConnectedWindow = Duration(seconds: 20);

  /// Win32 GetCommModemStatus 비트마스크 (win32 패키지 상수에 의존하지 않고 직접
  /// 정의 -- 값은 Win32 API 에서 영구 고정). 시리얼 프린터 전원/온라인 판정용.
  static const int _msCtsOn = 0x0010; // MS_CTS_ON  : Clear-To-Send
  static const int _msDsrOn = 0x0020; // MS_DSR_ON  : Data-Set-Ready
  static const int _msRingOn = 0x0040; // MS_RING_ON
  static const int _msRlsdOn = 0x0080; // MS_RLSD_ON : Carrier Detect

  /// Win32 EscapeCommFunction 명령 코드 (win32 패키지 상수에 의존하지 않고
  /// 직접 정의 -- 값은 Win32 API 에서 영구 고정). 모뎀 라인 assert 용.
  static const int _escSetRts = 3; // SETRTS
  static const int _escSetDtr = 5; // SETDTR

  /// COM 포트 open~close 임계구역 직렬화 락 (Future 체이닝 mutex).
  /// [sendRaw] (실제 출력) 와 [probeConnection] (연결 검증) 이 같은 COM 포트를
  /// 동시에 열어 ACCESS_DENIED / 핸들 경합을 일으키지 않도록 보장한다.
  /// 단일 isolate 라 일반 필드로 충분.
  static Future<void> _portLock = Future<void>.value();

  /// [_portLock] 으로 [action] 을 직렬 실행. action 이 throw 해도 락은 항상
  /// 해제(다음 대기자 진행)된다.
  static Future<T> _synchronized<T>(Future<T> Function() action) {
    final completer = Completer<void>();
    final prev = _portLock;
    _portLock = completer.future;
    return prev.then((_) => action()).whenComplete(completer.complete);
  }

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

  /// openWithSettings 전에 DCB 를 완전한 유효값으로 초기화한다.
  ///
  /// serial_port_win32 는 DCB 를 calloc(zero-init) 상태로 두고 BaudRate/
  /// ByteSize/StopBits/Parity 4개 필드만 채워 SetCommState 를 호출한다.
  /// usbser.sys(USB-CDC) 는 불완전 DCB 도 수용하지만, 검증이 엄격한
  /// USB-RS232 어댑터 드라이버 대비 필수 필드를 채운다: DCBlength,
  /// fBinary(=1, Windows 필수), XonChar != XoffChar. 아울러 fDtrControl/
  /// fRtsControl 을 ENABLE 로 두어 RS-232 프린터(DTR/DSR 흐름제어)가
  /// host-ready 를 보도록 한다.
  static void _primeDcb(SerialPort port) {
    port.dcb.ref
      ..DCBlength = sizeOf<DCB>()
      // bit0 fBinary | bits4-5 fDtrControl=ENABLE | bits12-13 fRtsControl=ENABLE
      ..bitfield = 0x0001 | 0x0010 | 0x1000
      ..XonLim = 2048
      ..XoffLim = 512
      ..XonChar = 0x11 // DC1
      ..XoffChar = 0x13 // DC3
      ..ErrorChar = 0
      ..EofChar = 0
      ..EvtChar = 0;
  }

  /// 패키지 open() 의 핸들 누수 회수.
  ///
  /// serial_port_win32 의 open() 은 CreateFile 성공 후 SetCommState /
  /// SetCommTimeouts / SetCommMask 가 throw 하면 핸들을 닫지 않은 채
  /// 전파하고 _isOpened 는 false 로 남는다. 이 누수 핸들을 방치하면
  /// (share-mode 0 배타 점유) 이후 모든 CreateFile 이 ACCESS_DENIED 로
  /// 락아웃되어 앱 재시작 전까지 출력이 불가능해진다.
  ///
  /// 반드시 openWithSettings throw 직후에만 호출할 것: 그 시점의 handler 는
  /// 이번 open() 이 CreateFile 로 갱신한 값이므로(open 의 첫 문장) stale
  /// 핸들을 닫는 double-close 위험이 없다. 그 외 시점에는 handler 가 이미
  /// 닫힌 과거 값일 수 있어 재사용된 무관한 핸들을 닫을 수 있다.
  static void _recoverLeakedHandle(SerialPort port) {
    if (port.isOpened) return;
    final h = port.handler;
    if (h == null || h == INVALID_HANDLE_VALUE) return;
    try {
      CloseHandle(h);
      logger.w('[ComPortPrint] open 실패 잔여 핸들 회수 (leak guard)');
    } catch (_) {
      // 회수 시도일 뿐. 실패해도 기존과 동일한 상태.
    }
  }

  /// open 직후 DTR/RTS 모뎀 라인을 assert 한다.
  ///
  /// serial_port_win32 는 DCB 를 zero-init 상태로 SetCommState 하므로
  /// fDtrControl/fRtsControl 이 DISABLE(라인 low) 로 열린다. USB-CDC 가상
  /// COM(PR800 내장 USB)은 모뎀 라인을 무시해 문제가 없었지만, USB-RS232
  /// 어댑터(NEXT-340PL 등) 경유 시 DTR/DSR 흐름제어 프린터가 호스트
  /// not-ready 로 판단해 수신을 거부하거나 상태 응답(TX)을 보류할 수 있다.
  /// 터미널 프로그램이 open 시 DTR/RTS 를 올리는 것과 같은 표준 동작.
  ///
  /// SETDTR/SETRTS 는 fDtrControl/fRtsControl 이 HANDSHAKE 일 때만 거부되는데
  /// 여기서는 항상 DISABLE 이므로 유효하다. 실패해도 치명적이지 않으므로
  /// (CDC 포트에서는 사실상 no-op) 진단 로그만 남기고 진행한다.
  static void _assertModemLines(SerialPort port) {
    final handle = port.handler;
    if (handle == null) {
      logger.w('[ComPortPrint] modem assert: handler null');
      return;
    }
    try {
      final dtrOk = EscapeCommFunction(handle, _escSetDtr);
      final rtsOk = EscapeCommFunction(handle, _escSetRts);
      if (dtrOk == 0 || rtsOk == 0) {
        logger.w(
            '[ComPortPrint] DTR/RTS assert 실패 (SETDTR=$dtrOk SETRTS=$rtsOk)');
      } else {
        logger.d('[ComPortPrint] DTR/RTS asserted');
      }
    } catch (e) {
      logger.w('[ComPortPrint] DTR/RTS assert 예외: $e');
    }
  }

  /// COM 포트로 바이트 데이터 전송. [probeConnection] 과 포트 락을 공유해
  /// 출력 중 연결 검증이 같은 포트를 동시에 열지 않도록 직렬화한다.
  static Future<bool> sendRaw(
    Uint8List data, {
    String comPort = defaultComPort,
    int baudRate = defaultBaudRate,
  }) {
    return _synchronized(
        () => _sendRawLocked(data, comPort: comPort, baudRate: baudRate));
  }

  static Future<bool> _sendRawLocked(
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

      // 포트 열기. StopBits 는 win32 DCB raw 값(0=ONESTOPBIT, 1=1.5bit,
      // 2=2bit)이라 1 스톱비트는 0 이다. 종전 값 1(=1.5 스톱비트)은 8
      // 데이터비트와 조합 불가한 무효 설정인데 usbser.sys(USB-CDC)가 검증
      // 없이 수용해 잠복해 있다가, 검증이 엄격한 ser2pl.sys(PL2303 USB-RS232
      // 어댑터)의 SetCommState 거부(open throw)로 드러났다 (COM6 실기 재현).
      _primeDcb(port);
      try {
        port.openWithSettings(
          BaudRate: baudRate,
          ByteSize: 8,
          StopBits: 0, // ONESTOPBIT
          Parity: 0, // 0 = NOPARITY
        );
      } catch (_) {
        _recoverLeakedHandle(port);
        rethrow;
      }

      // 포트 열기 확인
      if (!port.isOpened) {
        _lastFailureReason = 'open-failed-silent';
        _lastFailureAt = DateTime.now();
        logger.e('[ComPortPrint] Failed to open $comPort (silent)');
        return false;
      }

      logger.d('[ComPortPrint] Opened $comPort with baud rate $baudRate');

      // RS-232 어댑터 경유 프린터가 settle 동안 host-ready 를 보도록 먼저 assert.
      _assertModemLines(port);

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
        // 디바이스 생존 확인: ESC/POS DLE EOT 1 핑이 권위 신호.
        // 모뎀 DSR/CTS 는 어댑터/배선에 따라 신호를 안 넘기거나(현장 PR800+CDC 는
        // 0x00) 항상 high 로 고정돼 신뢰 불가 -- 판정엔 쓰지 않고 raw 비트만
        // 진단 로깅한다. probe 실패 = 오프라인 → false → 큐 backoff 재시도.
        _readModemAlive(port); // 진단 로깅(DSR/CTS) 용
        final alive = await _probePrinter(port);
        if (!alive) {
          // _probePrinter 가 _lastFailureReason 을 'probe-timeout' /
          // 'probe-write-failed' 로 이미 세팅.
          _lastFailureAt = DateTime.now();
          logger.w(
              '[ComPortPrint] 생존 확인 실패: $comPort DLE EOT 무응답 '
              '-- printer offline?');
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
        // false 는 실패 확정이 아니다: 패키지 _getOverlappedResult 가
        // Future.delayed 를 await 하지 않아 timeout 이 시간이 아닌 루프 횟수로
        // 동작하고, 실제 RS-232 회선에서는 write 가 OVERLAPPED pending 상태
        // (전송은 백그라운드로 계속 진행) 이기만 해도 false 를 돌려준다.
        // 판정의 권위 신호는 RX 응답 유무이므로 폴링으로 진행한다 — 진짜
        // write 실패라면 어차피 RX timeout 으로 동일하게 실패 처리된다.
        logger.w('[ComPortPrint] probe write pending/false — RX 폴링으로 판정 진행');
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

  /// COM 포트의 모뎀 상태(DSR/CTS) 로 프린터 전원/온라인 여부를 판정한다.
  ///
  /// PR800 등 일부 ESC/POS 프린터는 DLE EOT 실시간 상태 명령에 응답하지 않아
  /// [_probePrinter] 만으로는 살아있어도 항상 오프라인으로 오판된다. 시리얼
  /// 프린터는 전원이 켜지면 보통 DSR(또는 CTS) 라인을 assert 하고, 본체 전원을
  /// 끄면 내려가므로 USB-Serial CDC 칩이 살아있어도 전원/온라인 여부를 구분할 수
  /// 있다.
  ///
  /// raw 비트를 항상 로깅해 어댑터/배선별로 어떤 신호가 유효한지 현장 검증한다.
  /// 반환: DSR 또는 CTS 가 assert 되어 있으면 true.
  static bool _readModemAlive(SerialPort port) {
    final handle = port.handler;
    if (handle == null) {
      logger.w('[ComPortPrint] modem: handler null');
      return false;
    }
    final stat = calloc<Uint32>();
    try {
      final ok = GetCommModemStatus(handle, stat);
      if (ok == 0) {
        logger.w('[ComPortPrint] GetCommModemStatus 실패 (rc=0)');
        return false;
      }
      final bits = stat.value;
      final cts = (bits & _msCtsOn) != 0;
      final dsr = (bits & _msDsrOn) != 0;
      final ring = (bits & _msRingOn) != 0;
      final rlsd = (bits & _msRlsdOn) != 0;
      final alive = dsr || cts;
      logger.i(
          '[ComPortPrint] 모뎀상태 0x${bits.toRadixString(16).padLeft(2, '0')} '
          'DSR=$dsr CTS=$cts RING=$ring RLSD=$rlsd -> alive=$alive');
      return alive;
    } finally {
      calloc.free(stat);
    }
  }

  /// 외부 ESC/POS 프린터의 실제 연결(생존) 여부를 검증한다.
  ///
  /// 단순히 COM 포트가 enumerate 되는지가 아니라, 포트를 열어 [_probePrinter]
  /// 의 DLE EOT 1 핑을 보내고 응답을 확인한다. USB-Serial CDC 칩은 프린터 본체
  /// 전원이 꺼져도 PC USB bus power 로 살아 포트가 유지되므로, 포트 존재만으로는
  /// "연결됨" 을 단정할 수 없다(false-positive). 핑 응답이 있어야 print head 가
  /// 살아있다고 판정한다.
  ///
  /// [sendRaw] 와 [_portLock] 을 공유하므로 실제 출력 중에는 검증이 대기한다.
  static Future<bool> probeConnection({
    String comPort = defaultComPort,
    int baudRate = defaultBaudRate,
  }) {
    return _synchronized(
        () => _probeConnectionLocked(comPort: comPort, baudRate: baudRate));
  }

  static Future<bool> _probeConnectionLocked({
    required String comPort,
    required int baudRate,
  }) async {
    // Fast-path: 최근에 실제 출력이 성공했다면 프린터 생존이 이미 입증된 상태.
    // 포트를 다시 열어 핑하면 USB-Serial 토글로 오히려 간섭만 주므로 생략.
    final lastOk = _lastSuccessfulSendAt;
    if (lastOk != null &&
        DateTime.now().difference(lastOk) < _recentSendConnectedWindow) {
      logger.d('[ComPortPrint] probeConnection: $comPort 최근 출력 성공 → connected');
      return true;
    }

    SerialPort? port;
    try {
      // 진입 가드: 현재 USB stack 에 노드 자체가 없으면 즉시 false.
      List<String> ports = const [];
      try {
        ports = SerialPort.getAvailablePorts();
      } catch (_) {}
      if (!ports.contains(comPort)) {
        logger.d('[ComPortPrint] probeConnection: $comPort 미enumerate → false');
        return false;
      }

      port = SerialPort(comPort, openNow: false);
      // 드물게 이미 열려있으면 닫고 OS release 대기 후 재오픈.
      if (port.isOpened) {
        try {
          port.close();
        } catch (_) {}
        await _waitPortEnumerated(comPort);
      }

      _primeDcb(port);
      try {
        port.openWithSettings(
          BaudRate: baudRate,
          ByteSize: 8,
          StopBits: 0, // ONESTOPBIT (win32 DCB raw 값 — _sendRawLocked 주석 참조)
          Parity: 0,
        );
      } catch (_) {
        _recoverLeakedHandle(port);
        rethrow;
      }
      if (!port.isOpened) {
        logger.d('[ComPortPrint] probeConnection: $comPort open 실패 → false');
        return false;
      }

      _assertModemLines(port);

      // open 직후 1차 안정화 후, DLE EOT 핑이 응답하면 통과 / 아니면 점진 재시도.
      // (PR800 처럼 멈춤 상태였다가 회복되는 케이스의 타이밍 편차를 재시도로 흡수.)
      // 모뎀 DSR/CTS 는 판정에 쓰지 않고 raw 비트만 진단 로깅한다.
      await Future.delayed(_settleProbe);
      for (int attempt = 1; attempt <= _probeMaxAttempts; attempt++) {
        _readModemAlive(port); // 진단 로깅(DSR/CTS) 용
        if (await _probePrinter(port)) {
          logger.d(
              '[ComPortPrint] probeConnection: $comPort alive[probe] (attempt $attempt/$_probeMaxAttempts)');
          return true;
        }
        if (attempt < _probeMaxAttempts) {
          await Future.delayed(_probeRetryInterval);
        }
      }
      logger.i('[ComPortPrint] probeConnection: $comPort 무응답 '
          '($_probeMaxAttempts회 시도, reason=$_lastFailureReason) → disconnected');
      return false;
    } catch (e) {
      logger.w('[ComPortPrint] probeConnection 예외: $e');
      return false;
    } finally {
      if (port != null) _safeClose(port);
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
