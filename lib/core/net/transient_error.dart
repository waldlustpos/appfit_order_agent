import 'package:dio/dio.dart';

/// 일시적(transient) 네트워크 장애인지 판정한다.
///
/// true = 같은 요청을 다시 보내면 성공할 수도 있는 실패(타임아웃·연결 실패·5xx).
/// false = 다시 보내도 같은 결과인 실패(4xx·취소·파싱 오류 등).
///
/// 재시도 여부뿐 아니라 **"서버가 지금 응답하고 있는가"** 를 세는 건강도 판정
/// (`ApiHealth`)에도 같은 기준을 쓴다. 4xx 는 서버가 정상 응답한 것이므로
/// 네트워크 열화로 세면 안 된다.
///
/// 원래 `OrderSocketManager` 안의 static 이었다. 소켓 상세조회 말고도 쓸 곳이
/// 생겨 top-level 순수 함수로 승격했다 — `OrderSocketManager.isTransientError`
/// 는 기존 테스트를 위해 이 함수로 위임하는 별칭으로 남아 있다.
bool isTransientNetworkError(Object e) {
  if (e is! DioException) return false;
  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.connectionError:
      return true;
    default:
      final code = e.response?.statusCode;
      return code != null && code >= 500;
  }
}
