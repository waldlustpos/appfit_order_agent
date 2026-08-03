// 라벨 인쇄 완료 응답(ACK) 미수신 예외.
//
// PagePrint 를 펌웨어로 보낸 뒤 CP_Pos_QueryPrintResult 가 timeout 한 케이스.
// 라벨은 실제로 출력됐을 가능성이 높지만 확정할 수 없고, 페이지가 이미 펌웨어
// 소유라 재발사하면 같은 라벨이 2장 인쇄된다. 따라서 재시도하지 않고 성공으로
// 취급하되, 이 예외로 발생 빈도만 집계한다.
//
// 배경: 2026-08-03 아오야마점(REXOD RXLA-561)에서 라벨 258장 중 2장(0.8%)이
// 이 경로로 timeout 했고, 당시 재시도 로직이 중복 인쇄를 만들었다.
//
// 전용 타입인 이유: MonitoringService.captureError 가 exception.runtimeType 으로
// 5분 쿨다운 키를 만들기 때문에, 일반 Exception 으로 보내면 다른 종류 예외와
// 키가 충돌해 누락된다. (LabelPrintMissingException 과 동일한 이유)

class LabelAckTimeoutException implements Exception {
  LabelAckTimeoutException({
    required this.orderNo,
    required this.displayNum,
    required this.labelIndex,
    required this.totalLabels,
    required this.attempt,
  });

  final String orderNo;
  final String displayNum;
  final int labelIndex;
  final int totalLabels;

  /// 몇 번째 시도에서 발생했는지 (1 = 첫 시도, 2 = 재시도).
  final int attempt;

  @override
  String toString() => 'LabelAckTimeoutException(displayNum=$displayNum,'
      ' label=$labelIndex/$totalLabels, attempt=$attempt)';
}
