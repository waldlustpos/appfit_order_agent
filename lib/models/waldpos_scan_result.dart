/// waldpos_agent 토스프런트 스캔 결과(수동 모델, freezed 미사용).
///
/// Windows 전용: 앱 -> waldpos_agent(127.0.0.1:8888) -> VAN 모듈 -> 토스프런트
/// 경로로 바코드를 요청하고 받은 결과를 표현한다.
enum WaldposScanError {
  /// Windows 가 아닌 플랫폼에서 호출됨.
  notSupported,

  /// waldpos_agent 소켓 연결 실패(미실행 등).
  connectionFailed,

  /// 응답 시간 초과.
  timeout,

  /// 응답 CRC/형식 오류.
  crcMismatch,

  /// 단말이 스캔을 거부하거나 returnValue != 1.
  declined,

  /// 기타 오류.
  unknown,
}

class WaldposScanResult {
  final bool success;

  /// 성공 시 스캔된 바코드(응답 cardNo).
  final String barcode;

  /// 사용자 안내용 메시지(실패 사유 등).
  final String message;

  final WaldposScanError? error;

  const WaldposScanResult({
    required this.success,
    this.barcode = '',
    this.message = '',
    this.error,
  });

  factory WaldposScanResult.success(String barcode) =>
      WaldposScanResult(success: true, barcode: barcode);

  factory WaldposScanResult.failure(
    WaldposScanError error,
    String message,
  ) =>
      WaldposScanResult(success: false, error: error, message: message);

  @override
  String toString() =>
      'WaldposScanResult{success: $success, barcode: $barcode, '
      'error: $error, message: $message}';
}
