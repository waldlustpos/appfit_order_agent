// lib/exceptions/api_error_mapper.dart
//
// API 예외(DioException 및 일반 Exception)를 사용자 친화적 [ApiException]으로
// 변환하는 단일 진입점.
//
// 정책:
//  - 서버가 서버별 로케일에 맞는 message 를 내려준다는 전제 하에, 서버
//    응답 body 의 `message` 를 언어 검사 없이 그대로 노출한다(빈 값/과도한
//    길이만 방어). raw DioException.toString() 의 긴 영문 노출을 막는 게 목적.
//  - 서버 응답 body 가 없는 경우(네트워크/타임아웃/status only)에만 앱 로케일
//    i18n 폴백 메시지를 사용한다.
//  - 원본(code/status/원본 message)은 Sentry breadcrumb 으로 보존하고,
//    다이얼로그에는 친화 메시지만 노출한다.

import 'package:dio/dio.dart';
import 'package:appfit_core/appfit_core.dart'; // MonitoringService
import 'package:appfit_order_agent/exceptions/api_exceptions.dart';
import 'package:appfit_order_agent/i18n/strings.g.dart'; // t (폴백 i18n)

/// 서버 message 를 사용자에게 그대로 노출해도 되는지 최소 sanity 체크.
///
/// 언어 검사는 하지 않는다 — 서버가 서버별 로케일에 맞는 message 를 준다는
/// 전제. raw dump/빈 값만 걸러낸다.
bool _isUsableServerMessage(String? m) {
  if (m == null) return false;
  final s = m.trim();
  return s.isNotEmpty && s.length <= 200;
}

/// HTTP status code 기반 폴백 메시지.
String _fallbackForStatus(int? status) {
  if (status == null) return t.common.api_error.generic;
  if (status == 401 || status == 403) return t.common.api_error.auth;
  if (status == 404) return t.common.api_error.not_found;
  if (status >= 500) return t.common.api_error.server;
  return t.common.api_error.generic;
}

/// DioException 유형(네트워크/타임아웃) 기반 폴백 메시지.
/// 해당 유형이 아니면 null(→ status 폴백으로 진행).
String? _fallbackForDioType(DioExceptionType type) {
  switch (type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return t.common.api_error.timeout;
    case DioExceptionType.connectionError:
      return t.common.api_error.network;
    default:
      return null;
  }
}

/// 모든 예외를 친화 [ApiException] 으로 변환한다.
///
/// 우선순위: 서버 message → DioType 폴백 → status 폴백 → generic.
///
/// [context] 는 "프로젝트 정보 조회" 같은 호출 맥락으로, breadcrumb 에만
/// 기록된다(사용자 노출 메시지에는 포함하지 않음).
ApiException mapDioErrorToApiException(
  Object error,
  StackTrace stackTrace, {
  String? context,
}) {
  // 이미 변환된 ApiException 은 그대로 통과 (이중 매핑 방지 — 멱등)
  if (error is ApiException) return error;

  if (error is DioException) {
    final data = error.response?.data;
    final status = error.response?.statusCode;

    String? serverCode;
    String? serverMessage;
    if (data is Map) {
      serverCode = data['code']?.toString();
      serverMessage = data['message']?.toString();
    }

    final String friendly = _isUsableServerMessage(serverMessage)
        ? serverMessage!.trim()
        : (_fallbackForDioType(error.type) ?? _fallbackForStatus(status));

    MonitoringService.instance.addBreadcrumb(
      'API 오류${context != null ? ' ($context)' : ''}: $friendly',
      category: 'api',
      data: {
        'context': context,
        'status_code': status,
        'server_code': serverCode,
        'server_message': serverMessage,
        'dio_type': error.type.name,
        'friendly_message': friendly,
      },
    );

    return ApiException(friendly, error, stackTrace);
  }

  // DioException 이 아닌 일반 예외
  MonitoringService.instance.addBreadcrumb(
    'API 오류${context != null ? ' ($context)' : ''}: $error',
    category: 'api',
    data: {
      'context': context,
      'runtime_type': error.runtimeType.toString(),
    },
  );
  return ApiException(t.common.api_error.generic, error, stackTrace);
}
