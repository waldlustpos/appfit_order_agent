import 'dart:io';

import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../config/update_config.dart';
import '../models/update_info.dart';
import 'platform_service.dart';
import 'windows_updater_script.dart';

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
        message:
            '업데이트 체크: current=$currentVersion, latest=$latestVersion',
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
      final dir = await getTemporaryDirectory();
      _zipPath = '${dir.path}\\${UpdateConfig.zipFileName}';
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

      final tempDir = Directory.systemTemp.path;
      final extractDir = '$tempDir\\${UpdateConfig.extractDirName}';

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

      final vbsPath =
          '${Directory.systemTemp.path}\\${UpdateConfig.updaterVbsName}';
      // Program Files 설치 시 robocopy 가 관리자 권한을 요구하므로
      // Shell.Application.ShellExecute("runas") 로 UAC 상승 실행한다.
      // LocalAppData 설치라도 runas 는 정상 동작한다.
      await File(vbsPath).writeAsString(
        'Set UAC = CreateObject("Shell.Application")\r\n'
        'UAC.ShellExecute "cmd.exe", "/c ""$batPath""", "", "runas", 0\r\n',
        flush: true,
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

      exit(0);
    } catch (e, s) {
      logToFile(
        tag: LogTag.ERROR,
        message: '업데이트 설치 실패: $e\n$s',
      );
      onError(e.toString());
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
