/// `PUT /v0/order/{orderNo}` 의 `action` 값. **요청 어휘**이며, 조회 응답의
/// 상태 문자열([kServerOrderStatus])과는 별개 축이다 — 서버가 둘을 다른 단어로
/// 쓴다(`ACCEPT`→`ACCEPTED`, `PICKUP_REQUEST`→`PICKUP_REQUESTED`,
/// `REJECT`→`CANCELED`). 두 어휘에 같은 상수를 겸용하면 안 된다.
enum OrderAction {
  ACCEPT,
  PICKUP_REQUEST,
  DONE,
  REJECT,

  /// 미픽업 처리. 서버 허용 선행 상태는 NEW·PREPARING·READY (DONE 은 거부).
  /// 고객 알림과 외부 소켓 이벤트를 **발행하지 않는다** —
  /// 타 기기는 폴링으로만 따라잡는다(docs/ORDER_NOT_PICKED_UP.md §5).
  NO_SHOW,
}
