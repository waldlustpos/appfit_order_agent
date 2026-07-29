import 'dart:io';

/// Windows 앱 재시작용 VBS 런처 생성기.
///
/// 단일 인스턴스 뮤텍스(windows/runner/main.cpp) 때문에 앱이 자기 자신을
/// 곧바로 재실행할 수 없다. 이 스크립트가 외부 프로세스로서 구 프로세스
/// 종료를 기다렸다가 새로 띄운다.
///
/// `.bat` 이 아닌 `.vbs` 를 쓰는 이유: cmd.exe 는 OEM 코드페이지로 배치를
/// 읽어 %TEMP% 경로가 한국어 로컬 계정이면 깨질 수 있다. VBS 는 UTF-16LE
/// + BOM 으로 직접 기록해 이 문제를 피한다. 또한 파일 교체가 없는 단순
/// 재시작이라 windows_updater_script.dart 와 달리 UAC 상승(runas)이 불필요.
///
/// 템플릿 리터럴은 ASCII only (프로젝트 규칙). 런타임에 보간되는 경로만
/// 비-ASCII 일 수 있다.
class WindowsRestartScript {
  static const String vbsName = 'appfit_order_agent_restart_launcher.vbs';
  static const String logName = 'appfit_order_agent_restart.log';

  /// VBS 본문 라인 생성 (순수 함수 — 파일 IO 없음).
  static List<String> buildVbsLines({
    required String exePath,
    required String exeName,
    required String appDir,
    required String logPath,
  }) {
    return [
      'Dim sh, fso, logFile',
      'On Error Resume Next',
      'Set sh = CreateObject("WScript.Shell")',
      'Set fso = CreateObject("Scripting.FileSystemObject")',
      'Set logFile = fso.OpenTextFile("$logPath", 8, True, -1)',
      'logFile.WriteLine "[START] " & Now',
      'sh.Run "taskkill /F /IM ""$exeName""", 0, True',
      'WScript.Sleep 2000',
      'logFile.WriteLine "[LAUNCH] $exePath"',
      'sh.CurrentDirectory = "$appDir"',
      'sh.Run """$exePath""", 1, False',
      'logFile.WriteLine "[DONE] " & Now',
      'logFile.Close',
      'fso.DeleteFile WScript.ScriptFullName, True',
    ];
  }

  /// UTF-16LE + BOM 인코딩. Dart 의 String.codeUnits 는 이미 UTF-16 코드
  /// 유닛이므로 리틀엔디언으로 그대로 바이트 스왑하면 된다.
  static List<int> encodeUtf16le(String content) {
    final bytes = <int>[0xFF, 0xFE];
    for (final unit in content.codeUnits) {
      bytes.add(unit & 0xFF);
      bytes.add((unit >> 8) & 0xFF);
    }
    return bytes;
  }

  /// VBS 파일을 %TEMP% 에 기록하고 경로를 반환한다.
  static Future<String> generate({
    required String exePath,
    required String exeName,
    required String appDir,
  }) async {
    final vbsPath = '${Directory.systemTemp.path}\\$vbsName';
    final logPath = '${Directory.systemTemp.path}\\$logName';

    final lines = buildVbsLines(
      exePath: exePath,
      exeName: exeName,
      appDir: appDir,
      logPath: logPath,
    );

    final content = '${lines.join('\r\n')}\r\n';
    await File(vbsPath).writeAsBytes(encodeUtf16le(content), flush: true);
    return vbsPath;
  }

  const WindowsRestartScript._();
}
