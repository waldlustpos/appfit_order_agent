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

  @override
  String toString() => 'OrderDetailFetchFailedException(orderNo=$orderNo,'
      ' eventType=$eventType, source=$source, lastError=$lastError)';
}
