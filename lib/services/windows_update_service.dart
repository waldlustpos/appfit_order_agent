import 'dart:io';

import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:appfit_order_agent/config/update_config.dart';
import 'package:appfit_order_agent/models/update_info.dart';
import 'package:appfit_order_agent/services/platform_service.dart';
import 'package:appfit_order_agent/services/windows_updater_script.dart';
import 'package:appfit_order_agent/utils/logger.dart';

/// Windows 전용 OTA 자동업데이트 서비스.
///
/// did 프로젝트의 WindowsUpdateManager 패턴을 이식.
/// Android 등 타 플랫폼에서는 모든 메서드가 no-op / null 반환.
class WindowsUpdateService {
  static final WindowsUpdateService _instance =
      WindowsUpdateService._internal();
  factory WindowsUpdateService() => _instance;
  WindowsUpdateService._internal();

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: UpdateConfig.connectTimeout,
      receiveTimeout: UpdateConfig.downloadReceiveTimeout,
    ),
  );

  CancelToken? _cancelToken;
  String? _zipPath;

  Future<UpdateInfo?> checkForUpdate() async {
    if (!Platform.isWindows) return null;

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = int.tryParse(packageInfo.buildNumber) ?? 0;

      final response = await _dio.get<Map<String, dynamic>>(
        UpdateConfig.versionUrl,
        options: Options(receiveTimeout: UpdateConfig.checkReceiveTimeout),
      );
      final data = response.data;
      if (data == null || data['version'] == null) return null;

      final latestVersion = (data['version'] as num).toInt();

      logToFile(
        tag: LogTag.SYSTEM,
        message: '업데이트 체크: current=$currentVersion, latest=$latestVersion',
      );

      return UpdateInfo(
        currentVersion: currentVersion,
        latestVersion: latestVersion,
        downloadUrl: UpdateConfig.downloadUrl,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        // 서버에 버전 파일 미업로드 — 업데이트 없음으로 간주
        logToFile(tag: LogTag.SYSTEM, message: '업데이트 파일 없음(404) — skip');
        return null;
      }
      logToFile(tag: LogTag.ERROR, message: '업데이트 체크 실패: $e');
      return null;
    } catch (e, s) {
      logToFile(tag: LogTag.ERROR, message: '업데이트 체크 실패: $e\n$s');
      return null;
    }
  }

  Future<void> downloadUpdate({
    required void Function(UpdateStatus status, double progress) onStatus,
    required void Function(String error) onError,
  }) async {
    if (!Platform.isWindows) return;

    try {
      // %TEMP% 가 아니라 앱 소유 스테이징 폴더. ZIP·압축해제본·bat·vbs·로그를
      // 한 폴더로 모아야 Defender 예외 1개가 OTA 전 경로를 덮는다.
      final stagingPath = await UpdateConfig.ensureStagingDir();
      _zipPath = '$stagingPath\\${UpdateConfig.zipFileName}';
      _cancelToken = CancelToken();

      onStatus(UpdateStatus.downloading, 0.0);

      await _dio.download(
        UpdateConfig.downloadUrl,
        _zipPath!,
        cancelToken: _cancelToken,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            onStatus(UpdateStatus.downloading, received / total);
          }
        },
      );

      onStatus(UpdateStatus.readyToInstall, 1.0);
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) return;
      logToFile(
        tag: LogTag.ERROR,
        message: '업데이트 다운로드 실패(Dio): ${e.message}',
      );
      onError(e.message ?? e.toString());
    } catch (e, s) {
      logToFile(
        tag: LogTag.ERROR,
        message: '업데이트 다운로드 실패: $e\n$s',
      );
      onError(e.toString());
    }
  }

  /// ZIP 압축 해제 → updater.bat 생성 → VBS 래퍼로 숨김 실행 → 앱 종료.
  /// 성공 시 이 함수는 반환하지 않는다 (exit(0)).
  Future<void> install({
    required void Function(String error) onError,
  }) async {
    if (!Platform.isWindows) return;
    if (_zipPath == null) {
      onError('다운로드된 파일이 없습니다.');
      return;
    }

    try {
      final exePath = Platform.resolvedExecutable;
      final appDir = File(exePath).parent.path;
      final exeName = File(exePath).uri.pathSegments.last;

      final stagingPath = await UpdateConfig.ensureStagingDir();
      final extractDir = '$stagingPath\\${UpdateConfig.extractDirName}';

      final extractDirObj = Directory(extractDir);
      if (extractDirObj.existsSync()) {
        extractDirObj.deleteSync(recursive: true);
      }

      final psResult = await Process.run('powershell', [
        '-NonInteractive',
        '-Command',
        'Expand-Archive -Path "$_zipPath" -DestinationPath "$extractDir" -Force',
      ]);

      if (psResult.exitCode != 0) {
        throw Exception('ZIP 압축 해제 실패: ${psResult.stderr}');
      }

      final extractSource = _resolveExtractSource(extractDir);

      final batPath = await WindowsUpdaterScript.generate(
        appDir: appDir,
        extractDir: extractSource,
        exeName: exeName,
      );

      // 설치 위치에 따라 상승 여부를 런타임에 결정한다.
      //
      // per-user 전환 이후 설치본은 %LOCALAPPDATA%\Programs 에 들어가 robocopy
      // 에 관리자 권한이 필요 없다. 하지만 그 이전 버전으로 설치된 매장은
      // 여전히 C:\Program Files 에 있고, 거기서 runas 를 빼면 robocopy 가 권한
      // 부족으로 실패한다. bat 이 :fail -> :launch 로 구버전을 다시 띄우므로
      // 앱은 살아 있지만 **버전이 영원히 멈춘 채 아무도 모르는** 상태가 된다.
      // 그래서 두 경우를 모두 지원한다.
      final needsElevation = !await _isDirectoryWritable(appDir);
      final verb = needsElevation ? 'runas' : '';

      final vbsPath = '$stagingPath\\${UpdateConfig.updaterVbsName}';
      // 창 숨김(ShellExecute 마지막 인자 0)이 목적이므로 상승이 불필요한
      // 경우에도 VBS 래퍼는 그대로 쓴다. verb 가 빈 문자열이면 기본 동사
      // ("open")로 실행되어 UAC 프롬프트가 뜨지 않는다.
      await File(vbsPath).writeAsString(
        'Set UAC = CreateObject("Shell.Application")\r\n'
        'UAC.ShellExecute "cmd.exe", "/c ""$batPath""", "", "$verb", 0\r\n',
        flush: true,
      );

      // 매장 로그만 받아도 그 PC 가 per-user 로 이관됐는지 판별할 수 있어야
      // 한다. 상승 경로를 탔다면 아직 Program Files 설치본이다.
      logToFile(
        tag: LogTag.SYSTEM,
        message: '업데이트 설치 위치: $appDir '
            '(관리자 권한 ${needsElevation ? '필요 — UAC 프롬프트 발생' : '불필요'})',
      );

      await Process.start(
        'wscript.exe',
        [vbsPath],
        mode: ProcessStartMode.detached,
        runInShell: false,
      );

      logToFile(
        tag: LogTag.SYSTEM,
        message: '업데이트 설치 스크립트 실행 완료 — 앱 종료',
      );

      // 파일 기록은 버퍼(30줄/2초)를 거치므로 flush 없이 exit(0) 하면 이 함수가
      // 남긴 로그가 통째로 사라진다. 하필 그 안에 상승 경로 판정 결과가 있어
      // **매장 로그로 이관 여부를 판별한다는 목적 자체가 무효화된다.**
      // (2026-08-27 실기 검증에서 실제로 유실을 확인하고 추가.)
      await flushLogBuffer();

      exit(0);
    } catch (e, s) {
      logToFile(
        tag: LogTag.ERROR,
        message: '업데이트 설치 실패: $e\n$s',
      );
      onError(e.toString());
    }
  }

  /// [dir] 에 실제로 파일을 만들어 보고 쓰기 가능 여부를 판정한다.
  ///
  /// **경로 문자열로 "Program Files 인가"를 보지 않는다.** 설치 경로는 설치
  /// 마법사에서 바꿀 수 있고, 같은 경로라도 ACL 이 다를 수 있다. 또 앱이 이미
  /// 상승된 컨텍스트로 떠 있으면(직전 업데이트가 상승 실행으로 재기동한 경우)
  /// Program Files 라도 쓰기가 되는데, 그때는 자식 프로세스도 상승 상태를
  /// 물려받으므로 runas 없이 실행해도 결과가 같다.
  ///
  /// 판정 실패(권한 없음/경로 없음 등)는 모두 "쓰기 불가"로 본다. 잘못
  /// 판정했을 때의 손해가 UAC 프롬프트 1회로 그치는 쪽이 안전하다.
  Future<bool> _isDirectoryWritable(String dir) async {
    final probe = File(
      '$dir\\.write_probe_${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      await probe.writeAsString('probe', flush: true);
      return true;
    } catch (_) {
      return false;
    } finally {
      try {
        if (probe.existsSync()) {
          probe.deleteSync();
        }
      } catch (_) {
        // 정리 실패는 무시. 다음 업데이트에서 덮어써도 무해한 빈 파일이다.
      }
    }
  }

  /// ZIP 압축 결과가 단일 하위 폴더를 포함하는 경우 그 폴더를 소스로 사용.
  String _resolveExtractSource(String extractDir) {
    final entries = Directory(extractDir).listSync();
    if (entries.length == 1 && entries.first is Directory) {
      return entries.first.path;
    }
    return extractDir;
  }

  void cancelUpdate() {
    _cancelToken?.cancel('사용자 취소');
    _cancelToken = null;
    _zipPath = null;
  }
}
