import 'dart:io';

import 'package:appfit_order_agent/config/update_config.dart';

class WindowsUpdaterScript {
  /// bat 내부는 ASCII only (한글 금지 — cmd.exe 기본 코드페이지 충돌 방지).
  /// robocopy exit code 0-7 은 성공, 8 이상은 실패.
  static Future<String> generate({
    required String appDir,
    required String extractDir,
    required String exeName,
  }) async {
    final batPath =
        '${Directory.systemTemp.path}\\${UpdateConfig.updaterBatName}';
    final logPath =
        '${Directory.systemTemp.path}\\${UpdateConfig.updaterLogName}';

    final lines = [
      '@echo off',
      'echo [START] %DATE% %TIME% > "$logPath"',
      '',
      'echo Killing remaining processes... >> "$logPath"',
      'taskkill /F /IM "$exeName" /T >nul 2>&1',
      'timeout /t 2 /nobreak >nul',
      '',
      'echo Copying files... >> "$logPath"',
      'robocopy "$extractDir" "$appDir" /E /IS /IT /IM /NFL /NDL /NJH /NJS >> "$logPath"',
      '',
      'if %errorlevel% geq 8 (',
      '  echo [FAIL] robocopy error code: %errorlevel% >> "$logPath"',
      '  exit /b 1',
      ')',
      '',
      'echo [OK] Files replaced. >> "$logPath"',
      'echo Starting app... >> "$logPath"',
      'start "" "$appDir\\$exeName"',
      '',
      'timeout /t 2 /nobreak >nul',
      'rmdir /S /Q "$extractDir" >nul 2>&1',
      'echo [DONE] %DATE% %TIME% >> "$logPath"',
      'del "%~f0"',
    ];

    final content = '${lines.join('\r\n')}\r\n';
    await File(batPath).writeAsBytes(content.codeUnits, flush: true);
    return batPath;
  }

  const WindowsUpdaterScript._();
}
