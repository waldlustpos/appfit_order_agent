import 'dart:typed_data';

import 'package:appfit_order_agent/services/log_collection/log_upload_sink.dart';

/// 향후 appfit 백엔드 멀티파트 중계 sink (스캐폴딩, 미구현).
///
/// 백엔드 업로드 엔드포인트 + Slack 연동이 준비되면 appfit_core Dio 의 `FormData`
/// 멀티파트로 업로드하도록 구현한다. (Dio 인터셉터가 FormData 사용 시 Content-Type
/// 을 multipart 로 자동 덮어쓰므로 인터셉터 우회 없이 가능 — "모든 REST 는
/// appfit_core Dio 경유" 규칙 충족.) 토큰이 클라이언트에 노출되지 않는 최종형.
class BackendRelaySink implements LogUploadSink {
  @override
  String get name => 'Backend';

  @override
  bool get isConfigured => false;

  @override
  Future<LogUploadResult> upload({
    required Uint8List zipBytes,
    required String filename,
    required String caption,
  }) async {
    return const LogUploadResult.fail(
        'BackendRelaySink 미구현 (백엔드 업로드 엔드포인트 준비 후 활성화).');
  }
}
