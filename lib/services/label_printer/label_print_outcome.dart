/// 라벨 한 장 인쇄 시도의 결과.
///
/// bool 하나로는 "아직 프린터로 안 보냈다"와 "보냈는데 완료 응답이 없다"를
/// 구분할 수 없다. 후자에서 재시도하면 이미 펌웨어에 들어간 페이지가 한 장 더
/// 인쇄된다 — 2026-08-03 아오야마점에서 라벨이 2장 출력된 사고의 경로다
/// (하루 258장 중 2장, 0.8%).
///
/// Android 네이티브 `LabelPrinter.RESULT_*` 상수와 1:1 대응한다.
enum LabelPrintOutcome {
  /// 인쇄 완료가 확인됨.
  success,

  /// PagePrint 발사 전에 실패 — 종이가 나가지 않았으므로 재시도해도 안전.
  /// 연결 오류, 펌웨어 일시 ERROR, 용지없음 취소 등.
  retryable,

  /// PagePrint 를 발사한 뒤 완료 응답(ACK)을 못 받음.
  ///
  /// 종이가 나왔는지 확정할 수 없지만 페이지는 이미 펌웨어 소유다.
  /// **재시도하면 중복 인쇄**가 되므로 재발사 금지. 호출자는 성공으로
  /// 취급하고 별도 집계(Sentry)만 한다.
  submittedNoAck;

  /// 네이티브 반환 코드 → outcome. 알 수 없는 값은 보수적으로 [retryable].
  static LabelPrintOutcome fromNativeCode(int? code) {
    switch (code) {
      case 0:
        return LabelPrintOutcome.success;
      case 2:
        return LabelPrintOutcome.submittedNoAck;
      default:
        return LabelPrintOutcome.retryable;
    }
  }

  /// 재발사해도 안전한가. false 면 **절대 같은 페이지를 다시 보내지 말 것.**
  bool get canRetry => this == LabelPrintOutcome.retryable;

  /// 종이가 나갔다고 볼 수 있는가 (UI 표시·누락 집계용).
  bool get isPrinted => this != LabelPrintOutcome.retryable;
}
