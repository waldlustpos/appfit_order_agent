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

  @override
  String toString() => 'LabelPrintMissingException(displayNum=$displayNum,'
      ' failed=$failedCount/$totalLabels, indices=$failedIndices)';
}
