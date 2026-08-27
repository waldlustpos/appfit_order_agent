import 'dart:io';

import 'package:appfit_order_agent/config/update_config.dart';

class WindowsUpdaterScript {
  /// bat 내부는 ASCII only (한글 금지 — cmd.exe 기본 코드페이지 충돌 방지).
  /// robocopy exit code 0-7 은 성공, 8 이상은 실패.
  ///
  /// 이 스크립트는 VBS 래퍼가 창을 숨긴 채(ShellExecute 마지막 인자 0) 실행하므로,
  /// 사용자가 진행 상황을 볼 수 없다. 따라서 어떤 경로로도 **"앱이 꺼진 채 멈춰
  /// 있는" 상태를 만들지 않는 것**이 최우선 제약이다.
  ///
  /// 견고화 포인트 (2026-08 kokonut 매장 사고 대응 이식):
  /// 1. robocopy 에 `/R:3 /W:2` 명시. 미지정 시 Windows 기본값이
  ///    `/R:1000000 /W:30` 이라 파일 락 하나에 사실상 영구 정지한다.
  /// 2. taskkill 후 고정 대기 대신 `tasklist` 폴링. `timeout` 커맨드는 숨겨진
  ///    콘솔에서 입력 리다이렉션 오류로 즉시 반환될 수 있어 신뢰할 수 없다.
  ///    대기는 `ping` 루프백으로 대체한다.
  /// 3. robocopy 실패(`:fail`) 시에도 `:launch` 로 fall-through 하여 앱을 반드시
  ///    다시 띄운다. 업데이트 실패가 영업 중단이 되면 안 된다.
  ///
  ///    **이것은 롤백이 아니다.** robocopy 는 exit code 8 이상이어도 일부 파일은
  ///    이미 복사한 뒤라, 설치 폴더에 구/신 파일이 섞여 남는다(2026-08-27 실측:
  ///    rc=11 에서 exe·app.so 는 교체되고 잠긴 파일 하나만 구버전 유지).
  ///    보장하는 것은 "앱이 다시 뜬다"까지이고, 어떤 파일이 실패했는지는 로그의
  ///    robocopy 오류 줄로만 판별할 수 있다. 깨끗한 원자적 교체가 필요하면
  ///    스테이징 후 폴더 스왑으로 바꿔야 하는데, 그건 별도 설계 변경이다.
  /// 4. 로그는 append. 회차별 기록이 남아야 사후 진단이 가능하다.
  /// 5. errorlevel 은 `RC` 변수로 즉시 복사. `if` 블록 안의 `%errorlevel%` 은
  ///    블록 진입 시점 값으로 확장되어 실제 robocopy 결과와 달라진다.
  static Future<String> generate({
    required String appDir,
    required String extractDir,
    required String exeName,
  }) async {
    // bat / 로그 모두 OTA 스테이징 폴더에 둔다. 백신 예외를 폴더 하나로 덮기
    // 위함이며, 로그가 %TEMP% 정리에 쓸려가지 않는 이점도 있다.
    final stagingPath = await UpdateConfig.ensureStagingDir();
    final batPath = '$stagingPath\\${UpdateConfig.updaterBatName}';
    final logPath = '$stagingPath\\${UpdateConfig.updaterLogName}';

    final lines = [
      '@echo off',
      'echo. >> "$logPath"',
      'echo ============================================ >> "$logPath"',
      'echo [START] %DATE% %TIME% >> "$logPath"',
      '',
      'echo Waiting for app to exit... >> "$logPath"',
      'taskkill /F /IM "$exeName" /T >nul 2>&1',
      '',
      'set WAITS=0',
      ':waitloop',
      'tasklist /FI "IMAGENAME eq $exeName" /NH 2>nul | find /I "$exeName" >nul',
      'if errorlevel 1 goto :gone',
      'set /a WAITS+=1',
      'if %WAITS% GEQ 20 goto :stillrunning',
      'ping -n 2 127.0.0.1 >nul',
      'goto :waitloop',
      '',
      ':stillrunning',
      'echo [WARN] app still running after wait budget. Proceeding anyway. >> "$logPath"',
      'goto :copy',
      '',
      ':gone',
      'echo App exited after %WAITS% polls. >> "$logPath"',
      '',
      ':copy',
      'echo Copying files... >> "$logPath"',
      'robocopy "$extractDir" "$appDir" /E /IS /IT /IM /R:3 /W:2 /NFL /NDL /NJH /NJS >> "$logPath"',
      'set RC=%ERRORLEVEL%',
      'if %RC% GEQ 8 goto :fail',
      '',
      'echo [OK] Files replaced. robocopy code: %RC% >> "$logPath"',
      'goto :launch',
      '',
      ':fail',
      'echo [FAIL] robocopy error code: %RC% >> "$logPath"',
      'echo WARNING: copy incomplete. The app folder may now hold a MIX of old >> "$logPath"',
      'echo and new files - robocopy code 8+ still means some files were copied. >> "$logPath"',
      'echo See the robocopy errors above for exactly which files failed. >> "$logPath"',
      'echo Relaunching anyway so the store is not left down. >> "$logPath"',
      '',
      ':launch',
      'echo Starting app... >> "$logPath"',
      'start "" "$appDir\\$exeName"',
      '',
      'ping -n 3 127.0.0.1 >nul',
      'rmdir /S /Q "$extractDir" >nul 2>&1',
      'echo [DONE] %DATE% %TIME% rc=%RC% >> "$logPath"',
      'del "%~f0"',
    ];

    final content = '${lines.join('\r\n')}\r\n';
    await File(batPath).writeAsBytes(content.codeUnits, flush: true);
    return batPath;
  }

  const WindowsUpdaterScript._();
}
