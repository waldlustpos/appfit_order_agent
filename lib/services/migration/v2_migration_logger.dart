import 'package:appfit_order_agent/utils/logger.dart';
import 'package:appfit_order_agent/services/platform_service.dart';

/// V2 → AppFit 마이그레이션 전용 로거
///
/// 마이그레이션 과정의 모든 단계를 기록하고,
/// 완료 시 일괄 파일 기록을 수행합니다.
class V2MigrationLogger {
  static final List<String> _logs = [];

  static void log(String message) {
    final entry = '[MIGRATION] $message';
    _logs.add(entry);
    logger.i(entry);
  }

  static void warn(String message) {
    final entry = '[MIGRATION][WARN] $message';
    _logs.add(entry);
    logger.w(entry);
  }

  static void error(String message, [Object? error]) {
    final entry = '[MIGRATION][ERROR] $message${error != null ? ' | $error' : ''}';
    _logs.add(entry);
    logger.e(entry, error: error);
  }

  /// 전체 마이그레이션 로그를 문자열로 반환
  static String getSummary() {
    return _logs.join('\n');
  }

  /// 축적된 로그를 네이티브 파일로 일괄 기록 후 버퍼 초기화
  static Future<void> flush() async {
    if (_logs.isEmpty) return;
    try {
      await logBatchToFile(messages: List.from(_logs));
    } catch (e, s) {
      logger.e('[MIGRATION] 로그 파일 기록 실패: $e');
    }
    _logs.clear();
  }
}
