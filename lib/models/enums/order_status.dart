/// 주문 상태
enum OrderStatus {
  NEW, // 신규주문
  PREPARING, // 준비중 (수락됨)
  READY, // 픽업대기 (준비완료)
  DONE, // 완료 (픽업됨)
  CANCELLED, // 취소
}

/// 상태 진행도(단조 격자). NEW < PREPARING < READY < DONE.
/// CANCELLED 는 진행도 비교에서 제외(터미널 분기로 별도 처리).
const Map<OrderStatus, int> kOrderStatusProgress = <OrderStatus, int>{
  OrderStatus.NEW: 0,
  OrderStatus.PREPARING: 1,
  OrderStatus.READY: 2,
  OrderStatus.DONE: 3,
};

/// 서버 응답과 로컬 상태를 병합할 때 다운그레이드(예: PREPARING→NEW)를 막기 위한 헬퍼.
///
/// 서버 PUT 직후 GET 응답이 구버전을 돌려주는 타이밍에서, 로컬이 이미
/// 더 진행된 상태라면 서버의 구버전 상태로 덮어쓰지 않는다.
/// CANCELLED 는 터미널 상태이므로 어느 한쪽이라도 CANCELLED 이면 우선한다.
///
/// 순수 함수(ref/state 비의존) — 상태 단조성 불변식의 단일 정의 지점.
OrderStatus resolveMergedStatus(OrderStatus local, OrderStatus server) {
  if (server == OrderStatus.CANCELLED || local == OrderStatus.CANCELLED) {
    return OrderStatus.CANCELLED;
  }
  final lo = kOrderStatusProgress[local] ?? 0;
  final so = kOrderStatusProgress[server] ?? 0;
  return lo > so ? local : server;
}
