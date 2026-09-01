/// 주문 상태
enum OrderStatus {
  NEW, // 신규주문
  PREPARING, // 준비중 (수락됨)
  READY, // 픽업대기 (준비완료)
  DONE, // 완료 (픽업됨)
  CANCELLED, // 취소
}

/// 서버 주문 상태 문자열 → [OrderStatus]. **앱 전역 단일 매핑표.**
///
/// 프로덕션 파서([ApiService._mapAppFitOrderStatus])와 테스트용 파서
/// ([OrderModel.fromJson] 의 `parseStatus`)가 **둘 다 이 표만 본다**. 과거에는
/// 두 파서가 각자 switch 를 들고 있어서 한쪽만 갱신되는 사고가 있었다 —
/// `PICKUP_REQUESTED` 가 테스트 파서에만 있고 프로덕션 파서에는 없었다.
///
/// 여기 없는 값은 호출부가 CANCELLED 로 폴백하고 경고를 남긴다. 즉 **표에서
/// 빠진 상태는 화면에 '취소' 로 보인다** — 새 상태를 추가할 땐 여기가 먼저다.
///
/// 숫자 코드(`2003`/`2007`/…)는 구 시스템(kokonut) 어휘라 제거했다. 서버로
/// 나가지도, 프린터가 읽지도, 분기 조건이 되지도 않는 데드 웨이트였다.
const Map<String, OrderStatus> kServerOrderStatus = <String, OrderStatus>{
  'PENDING': OrderStatus.NEW,
  'NEW': OrderStatus.NEW,
  'ACCEPTED': OrderStatus.PREPARING,
  'PREPARING': OrderStatus.PREPARING,
  'READY': OrderStatus.READY,
  'PICKUP_REQUESTED': OrderStatus.READY,
  'DONE': OrderStatus.DONE,
  'COMPLETED': OrderStatus.DONE,
  'CANCELED': OrderStatus.CANCELLED,
  'CANCELLED': OrderStatus.CANCELLED,
  'FAILED': OrderStatus.CANCELLED,
};

/// 로컬 전이 후 `OrderModel.orderStatus`(서버 원문 상태 문자열)에 채울 대표값.
///
/// 폴링·소켓이 서버 원문을 실어주는 필드에 로컬 전이가 끼어들 때 쓴다.
/// [kServerOrderStatus] 의 역방향이되 별칭이 여럿인 상태는 대표값 하나만 낸다.
String orderStatusToServer(OrderStatus status) => switch (status) {
      OrderStatus.NEW => 'NEW',
      OrderStatus.PREPARING => 'PREPARING',
      OrderStatus.READY => 'READY',
      OrderStatus.DONE => 'DONE',
      OrderStatus.CANCELLED => 'CANCELLED',
    };

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
