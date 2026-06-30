import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'package:appfit_order_agent/services/log_collection/log_upload_sink.dart';
import 'package:appfit_order_agent/services/platform_service.dart';
import 'package:appfit_order_agent/services/windows_log_file_writer.dart';
import 'package:appfit_order_agent/utils/logger.dart';

/// 로그 수집 진행 단계(설정화면 진행 표시용).
enum LogCollectionStage {
  idle,
  flushing,
  collecting,
  zipping,
  uploading,
  done,
  failed,
}

/// 로그 수집/업로드 결과.
class LogCollectionOutcome {
  final bool success;
  final String? error;
  final int fileCount;
  final int zipBytes;
  final String? reference;

  const LogCollectionOutcome({
    required this.success,
    this.error,
    this.fileCount = 0,
    this.zipBytes = 0,
    this.reference,
  });
}

/// 로그 수집 오케스트레이터: flush -> 기간필터 열거 -> archive zip -> sink 업로드.
///
/// 플랫폼(Android/Windows) 분기를 여기서 흡수하고, 업로드 목적지는 [LogUploadSink]
/// 로 분리한다. 수동 버튼과 원격 명령(RemoteCommandHandler)이 동일 경로를 쓴다.
class LogCollectionService {
  final LogUploadSink sink;

  LogCollectionService(this.sink);

  static const String _filePrefix = 'appfit_';
  static const String _fileSuffix = '.txt';

  /// [from]~[to] 기간(양끝 포함, 일 단위) 로그를 수집해 zip 으로 업로드한다.
  ///
  /// 호출 직전까지의 로그를 포함하기 위해 [flushLogBuffer] 를 먼저 await 한다.
  /// [onStage] 로 진행 단계를 통지한다.
  Future<LogCollectionOutcome> collectAndUpload({
    required DateTime from,
    required DateTime to,
    required String caption,
    required String filename,
    void Function(LogCollectionStage stage)? onStage,
  }) async {
    try {
      if (!sink.isConfigured) {
        onStage?.call(LogCollectionStage.failed);
        return LogCollectionOutcome(
          success: false,
          error: '${sink.name} 업로드 설정이 없습니다.',
        );
      }

      onStage?.call(LogCollectionStage.flushing);
      await flushLogBuffer();

      onStage?.call(LogCollectionStage.collecting);
      final files = await _collectLogFiles(from: from, to: to);
      if (files.isEmpty) {
        onStage?.call(LogCollectionStage.failed);
        return const LogCollectionOutcome(
          success: false,
          error: '선택한 기간에 로그 파일이 없습니다.',
        );
      }

      onStage?.call(LogCollectionStage.zipping);
      final zip = await _zip(files);

      onStage?.call(LogCollectionStage.uploading);
      final result = await sink.upload(
        zipBytes: zip,
        filename: filename,
        caption: caption,
      );

      if (!result.success) {
        onStage?.call(LogCollectionStage.failed);
        return LogCollectionOutcome(
          success: false,
          error: result.error,
          fileCount: files.length,
          zipBytes: zip.length,
        );
      }

      onStage?.call(LogCollectionStage.done);
      logger.i(
        '[LogCollection] 업로드 완료: ${files.length}개 파일, ${zip.length} bytes (${sink.name})',
      );
      return LogCollectionOutcome(
        success: true,
        fileCount: files.length,
        zipBytes: zip.length,
        reference: result.reference,
      );
    } catch (e, s) {
      logger.e('[LogCollection] 수집/업로드 실패', error: e, stackTrace: s);
      onStage?.call(LogCollectionStage.failed);
      return LogCollectionOutcome(success: false, error: '$e');
    }
  }

  Future<List<File>> _collectLogFiles({
    required DateTime from,
    required DateTime to,
  }) async {
    if (Platform.isWindows) {
      return WindowsLogFileWriter.listLogFiles(from: from, to: to);
    }

    final dirPath = await PlatformService.getLogDirPath();
    if (dirPath == null) return const [];
    final dir = Directory(dirPath);
    if (!await dir.exists()) return const [];

    final fromDay = DateTime(from.year, from.month, from.day);
    final toDay = DateTime(to.year, to.month, to.day);
    final result = <File>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = _basename(entity.path);
      if (!name.startsWith(_filePrefix) || !name.endsWith(_fileSuffix)) {
        continue;
      }
      if (name.length < 18) continue;
      final date = _tryParseDate(name.substring(7, 17));
      if (date == null) continue;
      if (date.isBefore(fromDay) || date.isAfter(toDay)) continue;
      result.add(entity);
    }
    result.sort((a, b) => _basename(a.path).compareTo(_basename(b.path)));
    return result;
  }

  Future<Uint8List> _zip(List<File> files) async {
    final archive = Archive();
    for (final f in files) {
      final bytes = await f.readAsBytes();
      archive.add(ArchiveFile.bytes(_basename(f.path), bytes));
    }
    return ZipEncoder().encodeBytes(archive);
  }

  String _basename(String path) {
    final i = path.lastIndexOf(RegExp(r'[\\/]'));
    return i >= 0 ? path.substring(i + 1) : path;
  }

  static DateTime? _tryParseDate(String s) {
    if (s.length != 10 || s[4] != '-' || s[7] != '-') return null;
    final y = int.tryParse(s.substring(0, 4));
    final m = int.tryParse(s.substring(5, 7));
    final d = int.tryParse(s.substring(8, 10));
    if (y == null || m == null || d == null) return null;
    if (m < 1 || m > 12 || d < 1 || d > 31) return null;
    return DateTime(y, m, d);
  }
}
