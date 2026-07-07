import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Windows 전용 로그 파일 기록.
///
/// Android `MainActivity.appendLogsToFile` / `deleteOldLogFiles`와 동일한
/// 경로(`Documents/appfit/`), 파일명(`appfit_YYYY-MM-DD.txt`), 6개월 보존
/// 정책을 Dart 단에서 그대로 재현한다.
class WindowsLogFileWriter {
  WindowsLogFileWriter._();

  static const String _logDirName = 'appfit';
  static const String _filePrefix = 'appfit_';
  static const String _fileSuffix = '.txt';

  static Future<void> _writeQueue = Future<void>.value();
  static bool _cleanupRan = false;

  /// 배치 로그를 오늘자 파일에 append. 빈 리스트는 즉시 반환.
  /// 동시 호출은 내부 Future 체인으로 직렬화한다.
  static Future<void> appendLogsToFile(List<String> logs) {
    if (logs.isEmpty) return Future<void>.value();
    final task = _writeQueue.then((_) => _doAppend(logs));
    _writeQueue = task.catchError((_) {});
    return task;
  }

  /// 큐에 남아있는 모든 쓰기 작업이 끝날 때까지 대기한다.
  ///
  /// 로그 수집(zip) 직전 호출해 버퍼링된 최신 로그가 디스크에 반영되도록 보장한다.
  /// `_writeQueue` 는 항상 catchError 로 감싸져 throw 하지 않지만, 방어적으로 try.
  static Future<void> flushPending() async {
    try {
      await _writeQueue;
    } catch (_) {}
  }

  /// 로그 디렉터리의 `appfit_YYYY-MM-DD.txt` 파일 목록을 반환한다.
  ///
  /// [from]/[to] 가 주어지면 파일명의 날짜가 해당 기간(양끝 포함, 일 단위)에
  /// 속하는 파일만 반환한다. 디렉터리가 없으면 빈 리스트. 날짜 오름차순 정렬.
  static Future<List<File>> listLogFiles({DateTime? from, DateTime? to}) async {
    final result = <File>[];
    try {
      final dir = await _resolveLogDir(create: false);
      if (dir == null || !await dir.exists()) return result;

      final fromDay =
          from == null ? null : DateTime(from.year, from.month, from.day);
      final toDay = to == null ? null : DateTime(to.year, to.month, to.day);

      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = _basename(entity.path);
        if (!name.startsWith(_filePrefix) || !name.endsWith(_fileSuffix)) {
          continue;
        }
        if (name.length < 18) continue;

        final dateStr = name.substring(7, 17); // "yyyy-MM-dd"
        final fileDate = _tryParseDate(dateStr);
        if (fileDate == null) continue;

        if (fromDay != null && fileDate.isBefore(fromDay)) continue;
        if (toDay != null && fileDate.isAfter(toDay)) continue;
        result.add(entity);
      }
    } catch (e, s) {
      developer.log(
        'WindowsLogFileWriter.listLogFiles failed',
        name: 'AppfitAgent',
        error: e,
        stackTrace: s,
      );
    }
    result.sort((a, b) => _basename(a.path).compareTo(_basename(b.path)));
    return result;
  }

  /// 6개월 이상 된 로그 파일 삭제. 앱 시작 시 1회 호출되도록 멱등 가드.
  static Future<void> deleteOldLogs() async {
    if (_cleanupRan) return;
    _cleanupRan = true;
    try {
      final dir = await _resolveLogDir(create: false);
      if (dir == null || !await dir.exists()) return;

      final now = DateTime.now();
      final cutoff = DateTime(now.year, now.month - 6, now.day);

      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = _basename(entity.path);
        if (!name.startsWith(_filePrefix) || !name.endsWith(_fileSuffix)) {
          continue;
        }
        if (name.length < 18) continue;

        final dateStr = name.substring(7, 17); // "yyyy-MM-dd"
        final fileDate = _tryParseDate(dateStr);
        if (fileDate == null) continue;

        if (fileDate.isBefore(cutoff)) {
          try {
            await entity.delete();
            await appendLogsToFile(['[SYSTEM] 오래된 로그 파일 삭제 완료: $name']);
          } catch (e) {
            await appendLogsToFile(['[SYSTEM] 오래된 로그 파일 삭제 실패: $name ($e)']);
          }
        }
      }
    } catch (e, s) {
      developer.log(
        'WindowsLogFileWriter.deleteOldLogs failed',
        name: 'AppfitAgent',
        error: e,
        stackTrace: s,
      );
    }
  }

  static Future<void> _doAppend(List<String> logs) async {
    try {
      final dir = await _resolveLogDir(create: true);
      if (dir == null) return;
      final fileName = '$_filePrefix${_today()}$_fileSuffix';
      final file = File('${dir.path}${Platform.pathSeparator}$fileName');
      // 새 파일이면 UTF-8 BOM(EF BB BF)을 1회 기입해 외부 뷰어의 인코딩
      // 오판(mojibake)을 방지한다. 동시 호출은 _writeQueue 체인으로 직렬화되어
      // "exists 체크 -> BOM 기입"이 원자적이라 BOM 이중 기입이 발생하지 않는다.
      if (!await file.exists()) {
        await file.writeAsBytes(
          const [0xEF, 0xBB, 0xBF],
          mode: FileMode.append,
          flush: true,
        );
      }
      final buf = StringBuffer();
      for (final line in logs) {
        buf
          ..write(line)
          ..write('\n');
      }
      await file.writeAsString(
        buf.toString(),
        mode: FileMode.append,
        encoding: utf8,
        flush: true,
      );
    } catch (e, s) {
      // 재귀 방지: logger.e 사용 금지. 콘솔로만.
      developer.log(
        'WindowsLogFileWriter._doAppend failed',
        name: 'AppfitAgent',
        error: e,
        stackTrace: s,
      );
    }
  }

  static Future<Directory?> _resolveLogDir({required bool create}) async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir =
          Directory('${docs.path}${Platform.pathSeparator}$_logDirName');
      if (create && !await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir;
    } catch (e, s) {
      developer.log(
        'WindowsLogFileWriter._resolveLogDir failed',
        name: 'AppfitAgent',
        error: e,
        stackTrace: s,
      );
      return null;
    }
  }

  static String _today() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
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

  static String _basename(String path) {
    final i = path.lastIndexOf(RegExp(r'[\\/]'));
    return i >= 0 ? path.substring(i + 1) : path;
  }
}
