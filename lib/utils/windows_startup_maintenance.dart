import 'dart:async';
import 'dart:io';

import 'package:appfit_order_agent/config/update_config.dart';
import 'package:appfit_order_agent/services/platform_service.dart';
import 'package:appfit_order_agent/services/preference_service.dart';

/// Windows 기동 시 1회 수행하는 환경 정비 작업 모음.
///
/// per-user 설치 전환(설치 위치가 `C:\Program Files\...` 에서
/// `%LOCALAPPDATA%\Programs\...` 로 이동)에 딸린 뒤처리들이다.
/// **어느 작업도 실패가 기동을 막지 않는다.**
///
/// 자세한 배경: [docs/WINDOWS_PERUSER_INSTALL.md](../../docs/WINDOWS_PERUSER_INSTALL.md)
Future<void> runWindowsStartupMaintenance(PreferenceService prefs) async {
  if (!Platform.isWindows) return;

  await _refreshAutoStartPath(prefs);

  // Defender 점검은 powershell 프로세스를 띄우므로 기동 경로에서 기다리지
  // 않는다. 결과는 로그로만 쓰이고 앱 동작에 영향을 주지 않는다.
  unawaited(_logDefenderExclusionState(prefs));
}

/// 부팅 자동 실행 레지스트리 값의 exe 경로를 현재 위치로 갱신한다.
///
/// `launch_at_startup` 은 `HKCU\...\Run` 에 등록 시점의 exe 절대 경로를 그대로
/// 박는다. per-user 로 이관된 PC 는 그 값이 삭제된
/// `C:\Program Files\AppfitOrderAgent\...` 를 계속 가리키므로, **부팅 시 자동
/// 실행이 조용히 실패한다.** `enable()` 은 멱등이라 매번 다시 불러도 값만
/// 덮어쓴다.
Future<void> _refreshAutoStartPath(PreferenceService prefs) async {
  try {
    if (!prefs.getAutoLaunch()) return;

    await PlatformService.setAutoStartup(true);
    logToFile(
      tag: LogTag.SYSTEM,
      message: '자동 실행 등록 경로 갱신: ${Platform.resolvedExecutable}',
    );
  } catch (e, s) {
    logToFile(
      tag: LogTag.ERROR,
      message: '자동 실행 등록 경로 갱신 실패: $e\n$s',
    );
  }
}

/// 로그에 남기는 고정 접두사. 매장 로그만 받아도 그 PC 에 Defender 예외가
/// 걸려 있는지 grep 으로 판별하기 위한 것이므로 **문구를 바꾸지 말 것.**
const String _defenderLogPrefix = 'Defender 예외 점검';

/// Defender 예외 등록 상태를 확인해 로그에 1줄 남긴다.
///
/// 등록이 실패해도 앱은 아무 말 없이 잘 돈다. 2026-08 kokonut 사고에서 실제로
/// 드러난 사각지대이고, 지금은 사람이 `defender_exclusion.log` 를 열어보기
/// 전까지 무방비 상태인 줄 모른다. 이 함수가 그것을 앱 로그로 끌어낸다.
///
/// 판정은 3상태다. **조회 실패를 "미등록"으로 단정하지 않는 것이 핵심이다.**
/// `Get-MpPreference` 의 `ExclusionPath` 는 구성에 따라 비상승 프로세스에서
/// 조회가 거부되는데, 앱은 상승되지 않은 채 돌므로 이 경우가 흔하다. 거부를
/// 미등록으로 기록하면 진단이 오히려 망가진다.
Future<void> _logDefenderExclusionState(PreferenceService prefs) async {
  try {
    // 하루 1회 제한 — powershell 프로세스 기동 비용과, 부팅 자동실행 직후
    // 프린터 연결과의 자원 경합을 피한다.
    final today = DateTime.now();
    final todayKey = '${today.year.toString().padLeft(4, '0')}-'
        '${today.month.toString().padLeft(2, '0')}-'
        '${today.day.toString().padLeft(2, '0')}';
    if (prefs.getDefenderCheckDate() == todayKey) return;
    await prefs.setDefenderCheckDate(todayKey);

    final result = await Process.run('powershell', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      "(Get-MpPreference -ErrorAction Stop).ExclusionPath -join '|'",
    ]);

    if (result.exitCode != 0) {
      logToFile(
        tag: LogTag.SYSTEM,
        message: '$_defenderLogPrefix: 판정 불가 (조회 실패). '
            '${result.stderr.toString().trim()}',
      );
      return;
    }

    final registered = result.stdout
        .toString()
        .split('|')
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toList();

    if (registered.isEmpty) {
      // 진짜 예외가 하나도 없는 PC 와, 조회는 됐지만 목록이 가려진 PC 가
      // 똑같이 빈 값으로 보인다. 구분할 방법이 없으므로 단정하지 않는다.
      logToFile(
        tag: LogTag.SYSTEM,
        message: '$_defenderLogPrefix: 판정 불가 (목록이 비어 있음) '
            '${await _installerLogSummary()}',
      );
      return;
    }

    // 비상승 프로세스에서는 Defender 가 목록 대신 안내 문자열 한 줄을 돌려준다
    // ("N/A: Must be an administrator to view exclusions"). **exitCode 는 0 이고
    // 목록도 비어 있지 않다** — 그래서 위의 두 가드로는 걸러지지 않고, 정상
    // 등록된 PC 가 매일 "미등록" 으로 오보된다(2026-08-27 실측).
    //
    // 문구는 로캘에 따라 달라질 수 있으므로 문자열을 매칭하지 않고, 항목이
    // 경로 모양인지로 본다. 경로가 하나도 없으면 조회가 막힌 것이다.
    final paths = registered.where(_looksLikeWindowsPath).toList();
    if (paths.isEmpty) {
      logToFile(
        tag: LogTag.SYSTEM,
        message: '$_defenderLogPrefix: 판정 불가 (조회 권한 부족) '
            '${await _installerLogSummary()}',
      );
      return;
    }

    // 설치본이 등록하는 2경로와 같아야 한다 — `.iss` 의 `{app}` 과
    // `{localappdata}\{#MyAppDirName}`.
    final appDir = File(Platform.resolvedExecutable).parent.path;
    final stagingParent = UpdateConfig.stagingDir().parent.path;

    final missing = <String>[
      if (!_containsPath(paths, appDir)) appDir,
      if (!_containsPath(paths, stagingParent)) stagingParent,
    ];

    if (missing.isEmpty) {
      logToFile(
        tag: LogTag.SYSTEM,
        message: '$_defenderLogPrefix: 정상 (설치 폴더 + OTA 스테이징 등록됨)',
      );
      return;
    }

    logToFile(
      tag: LogTag.ERROR,
      message: '$_defenderLogPrefix: 미등록 경로 있음 -> ${missing.join(' , ')} '
          '(설치본을 다시 실행하거나 설치 폴더의 '
          'register_defender_exclusion.ps1 을 관리자 권한으로 재실행 필요)',
    );
  } catch (e, s) {
    logToFile(
      tag: LogTag.SYSTEM,
      message: '$_defenderLogPrefix: 판정 불가 (점검 실패) $e\n$s',
    );
  }
}

/// `C:\...` 또는 UNC(`\\server\share`) 모양인지. 조회가 실제 목록을 돌려줬는지
/// 판단하는 데만 쓴다.
bool _looksLikeWindowsPath(String entry) =>
    RegExp(r'^([a-z]:\\|\\\\)').hasMatch(entry);

/// 설치본이 남긴 `defender_exclusion.log` 요약. 라이브 조회가 막혔을 때 "그때는
/// 등록됐었다"는 정황을 함께 남기기 위한 것이다.
///
/// **이것으로 "정상"이라고 단정하지 않는다** — 설치 시점 기록이라 그 뒤에 예외가
/// 지워졌을 수 있다. 날짜를 함께 남겨 사람이 판단하게 한다. 라이브 조회는 앱이
/// 상승되지 않은 채 도는 한 대부분의 PC 에서 막히므로, 이 정황이 없으면 진단이
/// 늘 "판정 불가" 한 줄로 끝나 아무 값도 주지 못한다.
Future<String> _installerLogSummary() async {
  try {
    final file = File('${File(Platform.resolvedExecutable).parent.path}'
        '\\defender_exclusion.log');
    if (!await file.exists()) return '/ 설치 기록 없음';

    // BOM 을 떼지 않으면 첫 키가 `﻿time=` 이 되어 매칭되지 않는다.
    final text = (await file.readAsString()).replaceFirst('﻿', '');

    // 키를 줄 머리에 고정하지 않는다 — 한 줄로 뭉친 로그(과거 스크립트의
    // PowerShell 우선순위 버그 산물)와 줄 단위 로그를 모두 읽기 위해서다.
    String match(RegExp re) => re.firstMatch(text)?.group(1)?.trim() ?? '';

    final when = match(RegExp(r'time=(\S+)'));
    // addError 값에는 공백이 들어갈 수 있으므로 다음 키까지로 끊는다.
    final addError =
        match(RegExp(r'addError=(.*?)(?=\s+winDefend=|[\r\n]|$)', dotAll: false));
    if (addError.isNotEmpty) {
      return '/ 설치 기록($when): 등록 실패 — $addError';
    }
    // exclusions 는 마지막 필드라 줄 끝(또는 파일 끝)까지가 값이다.
    final exclusions =
        match(RegExp(r'exclusions=([^\r\n]*)')).toLowerCase();
    final appDir = File(Platform.resolvedExecutable).parent.path;
    final stagingParent = UpdateConfig.stagingDir().parent.path;
    final covered = exclusions.contains(appDir.toLowerCase()) &&
        exclusions.contains(stagingParent.toLowerCase());
    return covered
        ? '/ 설치 기록($when): 2경로 등록됨'
        : '/ 설치 기록($when): 등록 경로 불일치';
  } catch (e) {
    return '/ 설치 기록 읽기 실패($e)';
  }
}

/// 예외 목록에 [path] 가 포함되는지 본다.
///
/// Defender 는 등록된 경로의 하위를 모두 제외하므로, 정확히 일치하지 않아도
/// 상위 폴더가 등록돼 있으면 덮인 것으로 본다. Windows 경로는 대소문자를
/// 구분하지 않으므로 호출부에서 이미 소문자로 정규화해 넘긴다.
bool _containsPath(List<String> registered, String path) {
  final target = path.toLowerCase();
  for (final entry in registered) {
    final normalized =
        entry.endsWith('\\') ? entry.substring(0, entry.length - 1) : entry;
    if (target == normalized || target.startsWith('$normalized\\')) {
      return true;
    }
  }
  return false;
}
