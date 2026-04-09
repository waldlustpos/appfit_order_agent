import 'package:intl/intl.dart';
import 'logger.dart';

/// `int`, `String`, `null` 등 다양한 형식의 타임스탬프를 [DateTime]으로 변환.
/// 여러 모델의 fromJson에서 중복 사용되던 로직을 통합.
DateTime parseTimestamp(dynamic timestamp, {String? context}) {
  if (timestamp == null) {
    logger.w('${context ?? 'parseTimestamp'}: Timestamp is null, returning current date.');
    return DateTime.now();
  }
  try {
    if (timestamp is int) {
      return DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    } else if (timestamp is String) {
      final intTimestamp = int.tryParse(timestamp);
      if (intTimestamp != null) {
        return DateTime.fromMillisecondsSinceEpoch(intTimestamp * 1000);
      } else {
        try {
          return DateFormat('yyyy-MM-dd HH:mm:ss').parse(timestamp);
        } catch (e, s) {
          logger.e('${context ?? 'parseTimestamp'}: Failed to parse date string "$timestamp".',
              error: e);
          return DateTime.now();
        }
      }
    }
  } catch (e, s) {
    logger.e('${context ?? 'parseTimestamp'}: Unexpected error.',
        error: e, stackTrace: s);
  }
  return DateTime.now();
}

/// 안전한 정수 파싱. null, int, String 타입을 처리.
int parseIntSafe(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

/// 오늘 날짜를 'yyyy-MM-dd' 형식 문자열로 반환.
/// `DateTime.now().toString().substring(0, 10)` 패턴을 대체.
String todayDateString() => DateFormat('yyyy-MM-dd').format(DateTime.now());
