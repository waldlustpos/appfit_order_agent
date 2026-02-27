import 'dart:async';
import 'dart:convert'; // JsonEncoder 사용 위해 추가
import 'dart:developer' as developer;
import 'package:logger/logger.dart';
import 'package:flutter/foundation.dart'; // kReleaseMode 사용 위해 추가
import 'package:kokonut_order_agent/services/platform_service.dart'; // PlatformService import

/// 전역으로 사용할 Logger 인스턴스
final logger = Logger(
  // 로그 레벨 필터 설정 (릴리즈 모드에서는 info 이상만 출력)
  level: kReleaseMode ? Level.info : Level.debug,
  // PrettyPrinter 대신 CustomLogPrinter와 CustomLogOutput 사용
  printer: CustomLogPrinter(), // 프린터는 포맷팅 담당
  output: CustomLogOutput(), // 출력은 콘솔 및 파일 로깅 담당
);

/// 로그 포맷팅을 담당하는 프린터 (PrettyPrinter 기능 일부 또는 단순화)
class CustomLogPrinter extends LogPrinter {
  static final levelPrefixes = {
    Level.trace: '[T]',
    Level.debug: '[D]',
    Level.info: '[I]',
    Level.warning: '[W]',
    Level.error: '[E]',
    Level.fatal: '[F]',
  };

  @override
  List<String> log(LogEvent event) {
    var messageStr = _stringifyMessage(event.message);
    var errorStr = event.error != null ? "\nError: ${event.error}" : "";
    var stackTraceStr =
        event.stackTrace != null ? "\nStackTrace: ${event.stackTrace}" : "";
    var levelString = levelPrefixes[event.level] ?? '[?]';

    // 최종 로그 문자열 생성 (시간은 CustomLogOutput에서 추가)
    final logString = "$levelString $messageStr$errorStr$stackTraceStr";
    return [logString]; // 포맷된 문자열 리스트 반환
  }

  String _stringifyMessage(dynamic message) {
    if (message is Function) {
      return message().toString();
    } else if (message is Map || message is Iterable) {
      try {
        // 간단한 JSON 변환 시도
        var encoder = const JsonEncoder(); // 들여쓰기 없이 한 줄로
        return encoder.convert(message);
      } catch (e) {
        return message.toString();
      }
    } else {
      return message.toString();
    }
  }
}

/// 로그 출력을 담당 (콘솔 및 네이티브 파일 로깅)
class CustomLogOutput extends LogOutput {
  final List<String> _buffer = [];
  Timer? _flushTimer;
  static const int _maxBufferSize = 30;
  static const Duration _flushInterval = Duration(seconds: 2);

  @override
  void output(OutputEvent event) {
    final now = DateTime.now();
    final timeStr =
        "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}.${now.millisecond.toString().padLeft(3, '0')}";

    for (var line in event.lines) {
      // 1. 콘솔 출력 (developer.log 사용) - 필터링 없이 모두 출력
      developer.log(
        line,
        name: 'AppfitAgent',
        level: _getLogLevelInt(event.level),
        time: now,
      );

      // 2. 파일 기록 필터링 (Whitelist 방식)
      bool shouldLogToFile = false;

      // 에러 및 경고는 무조건 기록
      if (event.level.index >= Level.warning.index) {
        shouldLogToFile = true;
      }
      // UI 액션 기록
      else if (line.contains('[UI_ACTION]')) {
        shouldLogToFile = true;
      }
      // 시스템 이벤트 (앱 시작/종료, 권한 등)
      else if (line.contains('[SYSTEM]')) {
        shouldLogToFile = true;
      }
      // 플랫폼 이벤트 (프린트, USB 등 하드웨어)
      else if (line.contains('[PLATFORM]')) {
        shouldLogToFile = true;
      }
      // 웹소켓 연결/해제 이벤트
      else if (line.contains('[WEBSOCKET]')) {
        shouldLogToFile = true;
      }
      // 라이프사이클 이벤트 (로그인/로그아웃 등)
      else if (line.contains('[LIFECYCLE]')) {
        shouldLogToFile = true;
      }

      // API 관련: 에러만 기록 (정상 요청/응답은 파일 기록에서 제외)
      else if (line.contains('[API]') &&
          (line.contains('ERROR') ||
              line.contains('실패') ||
              line.contains('오류'))) {
        shouldLogToFile = true;
      }

      // 불필요한 상세 로그 제외 (위에서 shouldLogToFile이 true여도 제외)
      if (shouldLogToFile) {
        if (line.contains('[SecureStorage]') ||
            line.contains('[OutputQueue]') ||
            line.contains('[OverlayService]') ||
            line.contains('스크롤') ||
            line.contains('[refreshOrders]')) {
          shouldLogToFile = false;
        }
      }

      if (shouldLogToFile) {
        final bufferedLine = "[$timeStr] $line";
        _buffer.add(bufferedLine);
      }
    }

    // 버퍼가 꽉 찼으면 즉시 플러시
    if (_buffer.length >= _maxBufferSize) {
      _flush();
    } else {
      // 타이머 설정 (이미 있으면 유지, 없으면 시작)
      _flushTimer ??= Timer(_flushInterval, _flush);
    }
  }

  void _flush() {
    _flushTimer?.cancel();
    _flushTimer = null;

    if (_buffer.isEmpty) return;

    final logsToSend = List<String>.from(_buffer);
    _buffer.clear();

    // 네이티브 배치 로깅 호출 (비동기로 실행하여 UI 블로킹 방지)
    PlatformService.logBatchToFile(logsToSend);
  }

  // developer.log 레벨 변환 함수
  int _getLogLevelInt(Level level) {
    switch (level) {
      case Level.trace:
        return 500;
      case Level.debug:
        return 700;
      case Level.info:
        return 800;
      case Level.warning:
        return 900;
      case Level.error:
        return 1000;
      case Level.fatal:
        return 1200;
      default:
        return 0;
    }
  }
}
