import 'dart:io';

import 'package:appfit_order_agent/services/windows_restart_script.dart';
import 'package:appfit_order_agent/utils/logger.dart';

/// Windows 앱 재시작 오케스트레이터.
///
/// 단일 인스턴스 뮤텍스(windows/runner/main.cpp) 때문에 앱이 자기 자신을
/// 곧바로 재실행할 수 없다 — 구 프로세스가 살아있는 동안 새 프로세스는
/// 뮤텍스 충돌로 즉시 종료된다. 외부 VBS 런처(WindowsRestartScript)가
/// 구 프로세스 소멸을 기다렸다가 새로 띄운다.
///
/// prepare -> onBeforeExit -> launch -> exitProcess 순서를 엄격히 지킨다.
/// prepare 또는 launch 가 실패하면 exitProcess 는 절대 호출하지 않는다 —
/// "앱만 꺼지고 다시 안 켜짐" 최악 시나리오를 막기 위함.
class WindowsRestartService {
  WindowsRestartService({
    Future<String> Function(String exePath, String exeName, String appDir)?
        generateScript,
    Future<bool> Function(String executable, List<String> args)? startDetached,
    String Function()? resolveExecutable,
    void Function()? exitProcess,
    Duration onBeforeExitTimeout = const Duration(seconds: 5),
  })  : _generateScript = generateScript ?? _defaultGenerateScript,
        _startDetached = startDetached ?? _defaultStartDetached,
        _resolveExecutable =
            resolveExecutable ?? (() => Platform.resolvedExecutable),
        _exitProcess = exitProcess ?? (() => exit(0)),
        _onBeforeExitTimeout = onBeforeExitTimeout;

  static final WindowsRestartService instance = WindowsRestartService();

  final Future<String> Function(String exePath, String exeName, String appDir)
      _generateScript;
  final Future<bool> Function(String executable, List<String> args)
      _startDetached;
  final String Function() _resolveExecutable;
  final void Function() _exitProcess;
  final Duration _onBeforeExitTimeout;

  /// 스크립트 생성 + 존재 검증까지만 수행한다. 실패 시 null — 이 시점에는
  /// 아무 것도 바뀌지 않았으므로 호출 측은 안전하게 중단할 수 있다.
  Future<String?> prepare() async {
    try {
      final exePath = _resolveExecutable();
      final exeFile = File(exePath);
      if (!exeFile.existsSync()) {
        logger.w('[WindowsRestartService] 실행 파일을 찾을 수 없음: $exePath');
        return null;
      }
      final exeName = exeFile.uri.pathSegments.last;
      final appDir = exeFile.parent.path;

      final scriptPath = await _generateScript(exePath, exeName, appDir);
      final scriptFile = File(scriptPath);
      if (!scriptFile.existsSync() || scriptFile.lengthSync() == 0) {
        logger.w('[WindowsRestartService] 재시작 스크립트 생성 실패: $scriptPath');
        return null;
      }
      return scriptPath;
    } catch (e, s) {
      logger.e('[WindowsRestartService] 재시작 준비 실패', error: e, stackTrace: s);
      return null;
    }
  }

  /// wscript.exe 로 detached 실행. 실패 시 cmd 폴백(ping 지연 관용구 — wscript 가
  /// 차단된 환경에서만 타는 최후 수단이라 콘솔이 잠깐 깜빡일 수 있다).
  Future<bool> launch(String scriptPath) async {
    try {
      if (await _startDetached('wscript.exe', [scriptPath])) {
        return true;
      }
    } catch (e, s) {
      logger.w('[WindowsRestartService] wscript 실행 실패, cmd 폴백 시도',
          error: e, stackTrace: s);
    }

    try {
      final exePath = _resolveExecutable();
      return await _startDetached('cmd.exe', [
        '/c',
        'ping -n 4 127.0.0.1 >nul & start "" "$exePath"',
      ]);
    } catch (e, s) {
      logger.e('[WindowsRestartService] cmd 폴백도 실패', error: e, stackTrace: s);
      return false;
    }
  }

  /// prepare -> onBeforeExit -> launch -> exitProcess 순서를 고정한다.
  /// false 반환 = 재시작하지 않았고 프로세스는 계속 살아있다(호출 측 안내용).
  Future<bool> restart({
    required Future<void> Function() onBeforeExit,
  }) async {
    final scriptPath = await prepare();
    if (scriptPath == null) return false;

    try {
      await onBeforeExit().timeout(_onBeforeExitTimeout);
    } catch (e, s) {
      logger.w('[WindowsRestartService] 재시작 전 정리 실패/타임아웃(진행)',
          error: e, stackTrace: s);
    }

    final launched = await launch(scriptPath);
    if (!launched) {
      logger.e('[WindowsRestartService] 재시작 스크립트 실행 실패 — 앱 유지');
      return false;
    }

    logger.i('[WindowsRestartService] 재시작 스크립트 실행 완료 — 앱 종료');
    _exitProcess();
    return true;
  }

  static Future<String> _defaultGenerateScript(
      String exePath, String exeName, String appDir) {
    return WindowsRestartScript.generate(
      exePath: exePath,
      exeName: exeName,
      appDir: appDir,
    );
  }

  static Future<bool> _defaultStartDetached(
      String executable, List<String> args) async {
    try {
      await Process.start(
        executable,
        args,
        mode: ProcessStartMode.detached,
        runInShell: false,
      );
      return true;
    } on ProcessException {
      return false;
    }
  }
}
