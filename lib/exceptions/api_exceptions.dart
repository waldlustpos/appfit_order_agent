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
  NetworkException(super.message,
      [super.originalException, super.originalStackTrace]);
}

/// 서버가 오류 응답을 반환했을 때의 예외
class ServerException extends ApiException {
  final int? statusCode;
  ServerException(String message,
      {this.statusCode,
      Object? originalException,
      StackTrace? originalStackTrace})
      : super(message, originalException, originalStackTrace);
}

/// 데이터 파싱 또는 예상치 못한 데이터 형식 관련 예외
class DataParsingException extends ApiException {
  DataParsingException(super.message,
      [super.originalException, super.originalStackTrace]);
}

/// 플랫폼 채널 호출 관련 예외
class PlatformApiException extends ApiException {
  final String? code; // PlatformException code
  PlatformApiException(String message,
      {this.code, Object? originalException, StackTrace? originalStackTrace})
      : super(message, originalException, originalStackTrace);
}

/// API 로직 내에서 예상치 못한 오류 발생 시 예외
class UnknownApiException extends ApiException {
  UnknownApiException(super.message,
      [super.originalException, super.originalStackTrace]);
}

/// API 응답 자체는 성공했으나, 비즈니스 로직 상 실패했을 경우 (예: success: false)
class BusinessLogicException extends ApiException {
  BusinessLogicException(super.message,
      [super.originalException, super.originalStackTrace]);
}

/// 회원 조회에서 서버가 "존재하지 않는 유저"를 돌려준 경우
/// (`GET /v0/user/profile` → HTTP 404 · `code: NOT_FOUND_USER`).
///
/// 통신 오류(타임아웃·5xx)와 **구분해서** '미가입' 흐름으로 분기하기 위한
/// 타입이다. 미가입은 장애가 아니라 정상 운영 상황이라 에러 다이얼로그를
/// 띄우지 않고, 입력한 번호 그대로 적립·쿠폰 API 를 태운다
/// (`Membership.search` 참고).
///
/// [ApiException] 을 상속하므로 이 타입을 따로 잡지 않는 호출부에서는
/// 기존과 동일하게 동작한다.
class MemberNotFoundException extends ApiException {
  MemberNotFoundException(super.message,
      [super.originalException, super.originalStackTrace]);
}
