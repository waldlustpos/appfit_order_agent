/// 주문 상태
enum OrderStatus {
  NEW, // 신규주문
  PREPARING, // 준비중 (수락됨)
  READY, // 픽업대기 (준비완료)
  DONE, // 완료 (픽업됨)
  CANCELLED, // 취소
}
