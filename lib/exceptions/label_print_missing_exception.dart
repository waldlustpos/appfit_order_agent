// 라벨 출력 누락 예외.
//
// 한 주문 안에서 N장 중 일부 라벨이 인쇄에 실패해 운영자 [라벨 재출력]
// 으로 복구가 필요한 케이스. Sentry 보고 경로 (MonitoringService.captureError)
// 에서 사용.

class LabelPrintMissingException implements Exception {
  LabelPrintMissingException({
    required this.orderNo,
    required this.displayNum,
    required this.failedCount,
    required this.totalLabels,
    required this.failedIndices,
  });

  final String orderNo;
  final String displayNum;
  final int failedCount;
  final int totalLabels;
  final List<int> failedIndices;

  /// Sentry 이슈 제목이자 슬랙 알림 제목.
  ///
  /// 예: `라벨 출력 안 됨 — 주문 0916번, 1장 중 1장 실패 (재출력 필요)`
  ///
  /// `failedIndices` 는 제목에서 뺀다 — 이미 captureError 의 extras
  /// (`failedIndices`)에 실려 있고, 제목에 넣으면 14장짜리 주문에서 한 줄을
  /// 다 잡아먹는다.
  @override
  String toString() => '라벨 출력 안 됨 — 주문 $displayNum번, '
      '$totalLabels장 중 $failedCount장 실패 (재출력 필요)';
}
