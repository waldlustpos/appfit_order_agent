// lib/exceptions/api_exceptions.dart

/// API 관련 예외의 기본 클래스
class ApiException implements Exception {
  /// 사용자에게 보여줄 수 있는 메시지 또는 내부 로깅용 메시지
  final String message;
  /// 원래 발생한 예외 객체 (선택적)
  final Object? originalException;
  /// 원래 예외의 스택 트레이스 (선택적)
  final StackTrace? originalStackTrace;

  ApiException(this.message, [this.originalException, this.originalStackTrace]);

  @override
  String toString() => message; // UI에 표시될 때 메시지만 보이도록
}

/// 네트워크 연결 또는 타임아웃 관련 예외
class NetworkException extends ApiException {
  NetworkException(String message, [Object? originalException, StackTrace? originalStackTrace])
      : super(message, originalException, originalStackTrace);
}

/// 서버가 오류 응답을 반환했을 때의 예외
class ServerException extends ApiException {
  final int? statusCode;
  ServerException(String message, {this.statusCode, Object? originalException, StackTrace? originalStackTrace})
      : super(message, originalException, originalStackTrace);
}

/// 데이터 파싱 또는 예상치 못한 데이터 형식 관련 예외
class DataParsingException extends ApiException {
  DataParsingException(String message, [Object? originalException, StackTrace? originalStackTrace])
      : super(message, originalException, originalStackTrace);
}

/// 플랫폼 채널 호출 관련 예외
class PlatformApiException extends ApiException {
  final String? code; // PlatformException code
  PlatformApiException(String message, {this.code, Object? originalException, StackTrace? originalStackTrace})
      : super(message, originalException, originalStackTrace);
}

/// API 로직 내에서 예상치 못한 오류 발생 시 예외
class UnknownApiException extends ApiException {
  UnknownApiException(String message, [Object? originalException, StackTrace? originalStackTrace])
      : super(message, originalException, originalStackTrace);
}

/// API 응답 자체는 성공했으나, 비즈니스 로직 상 실패했을 경우 (예: success: false)
class BusinessLogicException extends ApiException {
  BusinessLogicException(String message, [Object? originalException, StackTrace? originalStackTrace])
      : super(message, originalException, originalStackTrace);
}