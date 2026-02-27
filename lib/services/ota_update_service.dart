import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:app_installer/app_installer.dart';
import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:dio/dio.dart';
import '../utils/logger.dart';

// ---------------------------------------------------------------------------
// 업데이트 정보 모델
// ---------------------------------------------------------------------------
class UpdateInfo {
  final int currentVersion;
  final int latestVersion;
  final String downloadUrl;
  final bool hasUpdate;

  const UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.downloadUrl,
    required this.hasUpdate,
  });

  @override
  String toString() =>
      'UpdateInfo(current=$currentVersion, latest=$latestVersion, hasUpdate=$hasUpdate)';
}

// ---------------------------------------------------------------------------
// OTA 이벤트 (common_dialog.dart 호환)
// ---------------------------------------------------------------------------
enum OtaStatusType { idle, downloading, readyToInstall, installing, error }

// ---------------------------------------------------------------------------
// OtaUpdateService (싱글톤)
// ---------------------------------------------------------------------------
class OtaUpdateService {
  static final OtaUpdateService _instance = OtaUpdateService._internal();
  factory OtaUpdateService() => _instance;
  OtaUpdateService._internal();

  static const String _versionUrl =
      'http://waldpay.kokonutstamp2.com/kokonut_version.json';
  static const String _apkUrl =
      'http://waldpay.kokonutstamp2.com/appfit_order_agent.apk';
  static const String _apkFilename = 'appfit_order_agent.apk';

  bool _isInitialized = false;
  Timer? _pollingTimer;
  String? _taskId;
  String? _apkPath;
  OtaStatusType _status = OtaStatusType.idle;
  double _progress = 0.0;

  // 상태 변경 콜백 (common_dialog에서 등록)
  Function(OtaStatusType status, double progress)? _onStatusChanged;
  Function(String error)? _onError;
  VoidCallback? _onDone;

  // -------------------------------------------------------------------------
  // 초기화
  // -------------------------------------------------------------------------
  Future<void> initialize() async {
    if (_isInitialized) return;
    await FlutterDownloader.initialize(debug: false, ignoreSsl: true);
    _isInitialized = true;
    logger.i('OtaUpdateService 초기화 완료');
  }

  // -------------------------------------------------------------------------
  // 버전 체크 (HTTP GET)
  // -------------------------------------------------------------------------
  Future<UpdateInfo?> checkForUpdate() async {
    try {
      if (!_isInitialized) await initialize();

      final packageInfo = await PackageInfo.fromPlatform();
      final current = int.tryParse(packageInfo.buildNumber) ?? 0;

      final dio = Dio();
      final response = await dio.get(_versionUrl);
      final server = (response.data['version'] as num).toInt();

      logger.i('OTA 버전 체크: 현재=$current, 서버=$server');

      return UpdateInfo(
        currentVersion: current,
        latestVersion: server,
        downloadUrl: _apkUrl,
        hasUpdate: server > current,
      );
    } catch (e, s) {
      logger.e('OTA 버전 체크 실패', error: e, stackTrace: s);
      return null;
    }
  }

  // -------------------------------------------------------------------------
  // 다운로드 실행 (콜백 방식 - common_dialog 호환)
  // -------------------------------------------------------------------------
  Future<void> executeUpdate({
    required String downloadUrl,
    required String destinationFilename,
    required Function(dynamic event) onEvent,
    required VoidCallback onDone,
    required Function(String error) onError,
  }) async {
    try {
      if (!_isInitialized) await initialize();

      final dir = await getApplicationSupportDirectory();
      _apkPath = '${dir.path}/$_apkFilename';

      // 기존 파일 삭제
      final file = File(_apkPath!);
      if (await file.exists()) await file.delete();

      _status = OtaStatusType.downloading;
      _progress = 0.0;

      _onStatusChanged = (status, progress) {
        onEvent(OtaDownloadEvent(status: status, progress: progress));
      };
      _onDone = onDone;
      _onError = onError;

      _taskId = await FlutterDownloader.enqueue(
        url: _apkUrl,
        savedDir: dir.path,
        fileName: _apkFilename,
        showNotification: true,
        openFileFromNotification: false,
      );

      logger.i('OTA 다운로드 시작: taskId=$_taskId');
      _startPolling(onDone: onDone, onError: onError, onEvent: onEvent);
    } catch (e, s) {
      logger.e('OTA executeUpdate 실패', error: e, stackTrace: s);
      onError(e.toString());
    }
  }

  // -------------------------------------------------------------------------
  // 0.5초 폴링
  // -------------------------------------------------------------------------
  void _startPolling({
    required Function(dynamic event) onEvent,
    required VoidCallback onDone,
    required Function(String error) onError,
  }) {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) async {
        if (_taskId == null) return;
        try {
          final tasks = await FlutterDownloader.loadTasksWithRawQuery(
            query: 'SELECT * FROM task WHERE task_id="$_taskId"',
          );
          if (tasks == null || tasks.isEmpty) return;

          final task = tasks.first;
          final progress = task.progress.clamp(0, 100) / 100.0;
          _progress = progress;

          onEvent(OtaDownloadEvent(
            status: OtaStatusType.downloading,
            progress: progress,
          ));

          if (task.status == DownloadTaskStatus.complete) {
            _pollingTimer?.cancel();
            _status = OtaStatusType.readyToInstall;
            logger.i('OTA 다운로드 완료 → readyToInstall');
            onEvent(OtaDownloadEvent(
              status: OtaStatusType.readyToInstall,
              progress: 1.0,
            ));
            // 다운로드 완료 → 설치 자동 실행
            await install(onDone: onDone, onError: onError);
          } else if (task.status == DownloadTaskStatus.failed ||
              task.status == DownloadTaskStatus.canceled) {
            _pollingTimer?.cancel();
            _status = OtaStatusType.error;
            onError('다운로드 실패 (status: ${task.status})');
          }
        } catch (e) {
          logger.e('OTA 폴링 오류: $e');
        }
      },
    );
  }

  // -------------------------------------------------------------------------
  // 설치
  // -------------------------------------------------------------------------
  Future<void> install({
    VoidCallback? onDone,
    Function(String error)? onError,
  }) async {
    if (_apkPath == null) return;
    _status = OtaStatusType.installing;
    logger.i('OTA 설치 시작: $_apkPath');
    try {
      await AppInstaller.installApk(_apkPath!);
      onDone?.call();
    } catch (e) {
      logger.e('OTA 설치 실패: $e');
      onError?.call(e.toString());
    }
  }

  // -------------------------------------------------------------------------
  // 취소
  // -------------------------------------------------------------------------
  void cancelUpdate() {
    _pollingTimer?.cancel();
    if (_taskId != null) {
      FlutterDownloader.cancel(taskId: _taskId!);
    }
    _taskId = null;
    _apkPath = null;
    _status = OtaStatusType.idle;
    _progress = 0.0;
    _onStatusChanged = null;
    _onDone = null;
    _onError = null;
    logger.i('OTA 업데이트 취소됨');
  }

  void dispose() {
    cancelUpdate();
  }
}

// ---------------------------------------------------------------------------
// 이벤트 클래스 (common_dialog에서 instanceof 체크용)
// ---------------------------------------------------------------------------
class OtaDownloadEvent {
  final OtaStatusType status;
  final double progress;

  const OtaDownloadEvent({required this.status, required this.progress});
}