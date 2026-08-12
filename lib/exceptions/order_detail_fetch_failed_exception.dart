// 주문 상세조회 실패 예외.
//
// 새 주문 수신(소켓/폴링)·출력 단계에서 주문 상세(getOrder/getOrderDetail) 조회가
// 서버오류(5xx)·타임아웃·네트워크 단절로 실패해 자동접수/출력이 누락될 수 있는
// 케이스. Sentry 보고 경로 (MonitoringService.captureError) 에서만 사용한다.
//
// throw 되지 않고 captureError 의 첫 번째 인자로만 쓰인다. 전용 타입을 두는 이유:
// captureError 는 exception.runtimeType 으로 5분 쿨다운 키를 만들므로
// ([monitoring_service.dart:188]), 일반 Exception 으로 보내면 라벨 누락
// (LabelPrintMissingException) 등 다른 종류 예외와 키가 충돌해 누락 보고가
// rate-limit 에 묻힌다. 상세조회 실패 사건만 별도 카운트되도록 전용 클래스로 분리.

class OrderDetailFetchFailedException implements Exception {
  OrderDetailFetchFailedException({
    required this.orderNo,
    required this.eventType,
    required this.source,
    this.lastError,
  });

  final String orderNo;
  final String eventType;

  /// 실패 발생 지점:
  /// 'socket' | 'socket_fallback' | 'receipt' | 'polling' | 'receipt_queue' | 'label_queue'
  final String source;
  final String? lastError;

  /// [source] 를 사람이 읽는 말로. 매핑에 없는 값은 원문 그대로 흘린다 —
  /// 새 source 가 추가됐을 때 조용히 '알 수 없음' 으로 뭉개지는 것보다,
  /// 낯선 원문이 제목에 보이는 편이 낫다.
  static const Map<String, String> _sourceLabels = {
    'socket': '실시간 수신',
    'socket_fallback': '실시간 수신(재시도)',
    'receipt': '영수증 출력',
    'polling': '주기 조회',
    'receipt_queue': '영수증 대기열',
    'label_queue': '라벨 대기열',
  };

  /// Sentry 이슈 제목이자 슬랙 알림 제목.
  ///
  /// 예: `주문 정보 조회 실패 — 주문 874987496599613426, 실시간 수신 중
  /// (ORDER_CREATED)`
  ///
  /// [lastError] 는 길어서 제목에서 뺀다 — 호출자가 extras 에 `lastError` 로
  /// 실어 보낸다. 제목에서 빼면서 extras 에도 없으면 진단이 사라진다.
  @override
  String toString() => '주문 정보 조회 실패 — 주문 $orderNo, '
      '${_sourceLabels[source] ?? source} 중 ($eventType)';
}
