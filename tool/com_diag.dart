// COM 포트 실기 검증 보조 도구 (개발용, 앱 코드와 무관).
//
//   dart run tool/com_diag.dart list
//   dart run tool/com_diag.dart probe COM3 [baud]      -- DLE EOT 1 생존 핑
//   dart run tool/com_diag.dart hold  COM3 [baud] [초]  -- 포트를 배타 점유
//
// hold 는 매장 PC 에서 다른 POS / 배달 프로그램이 COM 포트를 선점한 상황을
// 재현한다 (serial_port_win32 의 open 은 CreateFile share-mode 0 = 배타).
import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:serial_port_win32/serial_port_win32.dart';
import 'package:win32/win32.dart';

const List<int> _dleEot1 = [0x10, 0x04, 0x01];

void _primeDcb(SerialPort port) {
  port.dcb.ref
    ..DCBlength = sizeOf<DCB>()
    ..bitfield = 0x0001 | 0x0010 | 0x1000
    ..XonLim = 2048
    ..XoffLim = 512
    ..XonChar = 0x11
    ..XoffChar = 0x13
    ..ErrorChar = 0
    ..EofChar = 0
    ..EvtChar = 0;
}

SerialPort _open(String comPort, int baud) {
  final port = SerialPort(comPort, openNow: false);
  _primeDcb(port);
  port.openWithSettings(
    BaudRate: baud,
    ByteSize: 8,
    StopBits: 0,
    Parity: 0,
  );
  return port;
}

Future<bool> _probe(SerialPort port) async {
  final handle = port.handler;
  if (handle == null) return false;
  EscapeCommFunction(handle, 5); // SETDTR
  EscapeCommFunction(handle, 3); // SETRTS
  PurgeComm(handle, PURGE_RXCLEAR);
  try {
    port.writeBytesFromUint8List(Uint8List.fromList(_dleEot1), timeout: 200);
  } catch (e) {
    stdout.writeln('  probe write threw: $e');
    return false;
  }
  final errors = calloc<Uint32>();
  final status = calloc<COMSTAT>();
  try {
    final deadline = DateTime.now().add(const Duration(milliseconds: 300));
    while (DateTime.now().isBefore(deadline)) {
      final ok = ClearCommError(handle, errors, status);
      if (ok != 0 && status.ref.cbInQue > 0) {
        stdout.writeln('  RX ${status.ref.cbInQue} bytes');
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    return false;
  } finally {
    calloc.free(errors);
    calloc.free(status);
  }
}

void _modem(SerialPort port) {
  final handle = port.handler;
  if (handle == null) return;
  final stat = calloc<Uint32>();
  try {
    final ok = GetCommModemStatus(handle, stat);
    if (ok == 0) {
      stdout.writeln('  modem: GetCommModemStatus 실패');
      return;
    }
    final b = stat.value;
    stdout.writeln('  modem 0x${b.toRadixString(16).padLeft(2, '0')} '
        'CTS=${b & 0x10 != 0} DSR=${b & 0x20 != 0} '
        'RING=${b & 0x40 != 0} RLSD=${b & 0x80 != 0}');
  } finally {
    calloc.free(stat);
  }
}

Future<void> main(List<String> args) async {
  final cmd = args.isEmpty ? 'list' : args[0];
  final comPort = args.length > 1 ? args[1] : 'COM3';
  final baud = args.length > 2 ? int.parse(args[2]) : 115200;

  stdout.writeln('가용 포트: ${SerialPort.getAvailablePorts()}');
  if (cmd == 'list') return;

  if (cmd == 'probe') {
    SerialPort? port;
    try {
      port = _open(comPort, baud);
      stdout.writeln('$comPort @ $baud open=${port.isOpened}');
      _modem(port);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      for (var i = 1; i <= 5; i++) {
        final alive = await _probe(port);
        stdout.writeln('  probe $i/5 -> $alive');
        if (alive) break;
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    } catch (e) {
      stdout.writeln('open 실패: $e');
    } finally {
      try {
        port?.close();
      } catch (_) {}
    }
    return;
  }

  if (cmd == 'hold') {
    final seconds = args.length > 3 ? int.parse(args[3]) : 30;
    SerialPort? port;
    try {
      port = _open(comPort, baud);
      stdout.writeln('HOLDING $comPort @ $baud (${seconds}s) '
          'open=${port.isOpened}');
      await Future<void>.delayed(Duration(seconds: seconds));
    } catch (e) {
      stdout.writeln('hold open 실패: $e');
    } finally {
      try {
        port?.close();
      } catch (_) {}
      stdout.writeln('RELEASED $comPort');
    }
    return;
  }

  stdout.writeln('알 수 없는 명령: $cmd');
}
