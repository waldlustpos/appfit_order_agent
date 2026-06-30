import 'dart:typed_data';

/// 로그 zip 업로드 결과.
class LogUploadResult {
  /// 업로드 성공 여부.
  final bool success;

  /// 업로드된 파일/메시지의 외부 식별자(예: Slack file_id) 또는 다운로드 URL.
  /// 실패 시 null.
  final String? reference;

  /// 실패 사유(사용자 표시/로깅용). 성공 시 null.
  final String? error;

  const LogUploadResult({required this.success, this.reference, this.error});

  const LogUploadResult.ok({this.reference})
      : success = true,
        error = null;

  const LogUploadResult.fail(this.error)
      : success = false,
        reference = null;

  @override
  String toString() =>
      'LogUploadResult(success: $success, reference: $reference, error: $error)';
}

/// 로그 zip 을 외부로 업로드하는 sink 추상화.
///
/// 하이브리드 설계의 교체 지점이다. MVP 는 [LogUploadSink] 구현으로 Slack 직전송
/// (SlackDirectSink)을 사용하고, 향후 백엔드 멀티파트 중계(BackendRelaySink)로
/// 무중단 전환한다. 상위 [LogCollectionService] 는 zip bytes 만 넘기므로 sink
/// 교체가 수집 로직에 영향을 주지 않는다.
abstract class LogUploadSink {
  /// 사람이 읽을 sink 이름(로깅/표시용).
  String get name;

  /// sink 사용 가능 여부(토큰/채널 등 설정 충족). false 면 호출 측이 차단/안내한다.
  bool get isConfigured;

  /// [zipBytes] 를 [filename] 으로 업로드하고 [caption] 을 첨부 메시지로 단다.
  Future<LogUploadResult> upload({
    required Uint8List zipBytes,
    required String filename,
    required String caption,
  });
}
