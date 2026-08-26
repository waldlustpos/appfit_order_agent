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
        message: '$_defenderLogPrefix: 판정 불가 (목록이 비어 있음)',
      );
      return;
    }

    // 설치본이 등록하는 2경로와 같아야 한다 — `.iss` 의 `{app}` 과
    // `{localappdata}\{#MyAppDirName}`.
    final appDir = File(Platform.resolvedExecutable).parent.path;
    final stagingParent = UpdateConfig.stagingDir().parent.path;

    final missing = <String>[
      if (!_containsPath(registered, appDir)) appDir,
      if (!_containsPath(registered, stagingParent)) stagingParent,
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
