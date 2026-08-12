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

  /// Sentry 이슈 제목이자 슬랙 알림 제목.
  ///
  /// 예: `라벨 프린터 응답 없음 — 주문 0624번 1/2장째, 1차 시도
  /// (인쇄된 것으로 간주)`
  ///
  /// "인쇄된 것으로 간주"를 제목에 박아 둔다 — 이 이벤트를 처음 보는 사람은
  /// 라벨이 안 나온 [LabelPrintMissingException] 과 헷갈리고, 재출력을
  /// 안내했다가 중복 인쇄를 만든다(2026-08-03 아오야마점에서 실제로 그랬다).
  @override
  String toString() => '라벨 프린터 응답 없음 — 주문 $displayNum번 '
      '$labelIndex/$totalLabels장째, $attempt차 시도 (인쇄된 것으로 간주)';
}
