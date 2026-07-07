import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'package:appfit_order_agent/config/app_env.dart';
import 'package:appfit_order_agent/services/log_collection/log_upload_sink.dart';
import 'package:appfit_order_agent/utils/logger.dart';

/// Slack 파일 업로드(3-step) sink. 구 `files.upload`(2025-11 폐기) 대체.
///
/// 1) `files.getUploadURLExternal` -> upload_url + file_id
/// 2) upload_url 에 zip 바이트 POST (octet-stream, **토큰 불필요** pre-signed)
/// 3) `files.completeUploadExternal` -> 채널 공유 + initial_comment(caption)
///
/// 대상 호스트가 slack.com 이라 appfit_core Dio(인증/Project 헤더)를 거치지 않고
/// 별도 [http.Client] 를 사용한다. 모든 응답은 HTTP 200 이어도 body 의 `ok`
/// 필드로 성공을 판정하며, 429 는 Retry-After 를 존중해 1회 재시도한다.
class SlackDirectSink implements LogUploadSink {
  final String _botToken;
  final String _channelId;
  final http.Client _client;

  SlackDirectSink({
    String? botToken,
    String? channelId,
    http.Client? client,
  })  : _botToken = botToken ?? AppEnv.slackBotToken,
        _channelId = channelId ?? AppEnv.slackChannelId,
        _client = client ?? http.Client();

  static final Uri _getUploadUrl =
      Uri.parse('https://slack.com/api/files.getUploadURLExternal');
  static final Uri _completeUrl =
      Uri.parse('https://slack.com/api/files.completeUploadExternal');

  @override
  String get name => 'Slack';

  @override
  bool get isConfigured => _botToken.isNotEmpty && _channelId.isNotEmpty;

  @override
  Future<LogUploadResult> upload({
    required Uint8List zipBytes,
    required String filename,
    required String caption,
  }) async {
    if (!isConfigured) {
      return const LogUploadResult.fail('Slack 토큰/채널이 설정되지 않았습니다.');
    }
    try {
      // Step 1: 업로드 URL + file_id 발급.
      final urlRes = await _postForm(_getUploadUrl, {
        'filename': filename,
        'length': zipBytes.length.toString(),
      });
      final urlJson = _decode(urlRes.body);
      if (urlJson['ok'] != true) {
        return LogUploadResult.fail(
            'getUploadURLExternal 실패: ${urlJson['error'] ?? 'HTTP ${urlRes.statusCode}'}');
      }
      final uploadUrl = urlJson['upload_url'] as String?;
      final fileId = urlJson['file_id'] as String?;
      if (uploadUrl == null || fileId == null) {
        return const LogUploadResult.fail(
            'getUploadURLExternal 응답에 upload_url/file_id 가 없습니다.');
      }

      // Step 2: pre-signed URL 에 바이트 업로드 (Authorization 헤더 금지).
      final putRes = await _client.post(
        Uri.parse(uploadUrl),
        headers: const {'Content-Type': 'application/octet-stream'},
        body: zipBytes,
      );
      if (putRes.statusCode < 200 || putRes.statusCode >= 300) {
        return LogUploadResult.fail(
            '업로드 URL POST 실패: HTTP ${putRes.statusCode}');
      }

      // Step 3: 채널 공유 + 캡션.
      final completeRes = await _postForm(_completeUrl, {
        'files': jsonEncode([
          {'id': fileId, 'title': filename},
        ]),
        'channel_id': _channelId,
        'initial_comment': caption,
      });
      final completeJson = _decode(completeRes.body);
      if (completeJson['ok'] != true) {
        return LogUploadResult.fail(
            'completeUploadExternal 실패: ${completeJson['error'] ?? 'HTTP ${completeRes.statusCode}'}');
      }

      logger.i('[LogUpload] Slack 업로드 성공: $filename ($fileId)');
      return LogUploadResult.ok(reference: fileId);
    } catch (e, s) {
      logger.e('[LogUpload] Slack 업로드 예외', error: e, stackTrace: s);
      return LogUploadResult.fail('Slack 업로드 예외: $e');
    }
  }

  /// 토큰 헤더가 필요한 Slack web API 폼 POST. 429 시 Retry-After 만큼 대기 후 1회 재시도.
  Future<http.Response> _postForm(Uri uri, Map<String, String> body) async {
    final headers = {
      'Authorization': 'Bearer $_botToken',
      'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8',
    };
    var res = await _client.post(uri, headers: headers, body: body);
    if (res.statusCode == 429) {
      final retryAfter = int.tryParse(res.headers['retry-after'] ?? '') ?? 1;
      await Future<void>.delayed(Duration(seconds: retryAfter.clamp(1, 30)));
      res = await _client.post(uri, headers: headers, body: body);
    }
    return res;
  }

  Map<String, dynamic> _decode(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }
}
