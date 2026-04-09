import 'dart:convert';

import 'package:appfit_core/appfit_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:appfit_order_agent/utils/logger.dart';
import '../services/platform_service.dart';

// ServerConfig URL 변경을 추적하는 provider
final serverUrlProvider = StateProvider<String>((ref) => AppFitConfig.baseUrl);

/// Custom Transformer to handle non-standard Content-Type like "application/json;"
class CustomTransformer extends BackgroundTransformer {
  @override
  Future<dynamic> transformResponse(
      RequestOptions options, ResponseBody response) async {
    // Check if the expected response type is JSON
    if (options.responseType == ResponseType.json) {
      // Get the content type from response headers (case-insensitive lookup)
      final contentTypeHeader = response.headers['content-type']?.first;

      // Check for the non-standard content type
      if (contentTypeHeader != null &&
          contentTypeHeader.trim().startsWith('application/json;')) {
        logger.d(
            '[CustomTransformer] Detected non-standard Content-Type: $contentTypeHeader');
        // Manually parse the JSON string
        // The response data might be bytes, so we decode it to UTF8 string first
        final responseData = await utf8.decodeStream(response.stream);
        try {
          // Parse the string as JSON
          final decoded = jsonDecode(responseData);
          logger.d('[CustomTransformer] Manually parsed JSON response.');
          return decoded;
        } catch (e, s) {
          logger.e('[CustomTransformer] Failed to manually parse JSON',
              error: e, stackTrace: s);
          // If parsing fails, throw an error or let default handling proceed
          // Depending on desired behavior. Here we rethrow to signal failure.
          throw DioException(
            requestOptions: options,
            response: Response(
              requestOptions: options,
              data: responseData, // Include original data in error
              statusCode: response.statusCode,
              headers: Headers.fromMap(response.headers),
            ),
            error: FormatException(
                'Failed to parse JSON with non-standard Content-Type: $contentTypeHeader',
                e),
            type: DioExceptionType.badResponse,
          );
        }
      } else {
        logger.d(
            '[CustomTransformer] Standard Content-Type detected or not JSON, delegating to default transformer.');
      }
    }
    // If not the specific non-standard JSON type, use the default transformer
    return super.transformResponse(options, response);
  }
}

/// Dio instance provider
/// Configures Dio with base options and adds the custom log interceptor.
final dioProvider = Provider<Dio>((ref) {
  // Watch serverUrlProvider to recreate Dio when URL changes
  final serverUrl = ref.watch(serverUrlProvider);

  final dio = Dio(
    BaseOptions(
      baseUrl: serverUrl.endsWith('/') ? serverUrl : '$serverUrl/',
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ),
  );

  // Apply the Custom Transformer
  dio.transformer = CustomTransformer();

  // Add Custom Log Interceptor
  dio.interceptors.add(CustomLogInterceptor(ref: ref));

  return dio;
});

/// Custom Dio Interceptor for Logging
/// Logs requests, responses, and errors.
/// Truncates long data logs.
class CustomLogInterceptor extends Interceptor {
  final Ref ref; // Assuming Ref is needed, otherwise remove

  CustomLogInterceptor({required this.ref});

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    logger.i('[요청] ${options.method} ${options.uri}');
    if (options.headers.isNotEmpty) {
      logger.d('Headers: ${options.headers}');
    }
    if (options.data != null) {
      // Log data carefully, potentially truncating large bodies
      logger.d('Data: ${_truncateData(options.data)}');
    }
    super.onRequest(options, handler);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    logger.i(
        '[응답] ${response.statusCode} ${response.requestOptions.method} ${response.requestOptions.uri}');
    // Log response data carefully
    logger.d('Response Data: ${_truncateData(response.data)}');
    super.onResponse(response, handler);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    logger.e(
        '[ERR] ${err.response?.statusCode ?? '?'} ${err.requestOptions.method} ${err.requestOptions.uri}');
    if (err.response != null) {
      logger.e('Error Response: ${_truncateData(err.response?.data)}');
    } else {
      logger.e('Error Message: ${err.message}');
    }
    // Log to file as well - Call as top-level function
    logToFile(
        tag: LogTag.ERROR,
        message:
            'DioError: ${err.message}, Path: ${err.requestOptions.path}, Response: ${_truncateData(err.response?.data)}');

    super.onError(err, handler);
  }

  // Helper to truncate data for logging
  String _truncateData(dynamic data, {int maxLength = 1000}) {
    if (data == null) return '<null>';
    String dataString;
    if (data is Map || data is List) {
      try {
        dataString = jsonEncode(data);
      } catch (e, s) {
        dataString = data.toString();
      }
    } else {
      dataString = data.toString();
    }

    if (dataString.length > maxLength) {
      return '${dataString.substring(0, maxLength)}... (truncated)';
    }
    return dataString;
  }
}
