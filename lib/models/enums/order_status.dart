/// 주문 상태
enum OrderStatus {
  NEW, // 신규주문
  PREPARING, // 준비중 (수락됨)
  READY, // 픽업대기 (준비완료)
  DONE, // 완료 (픽업됨)
  CANCELLED, // 취소
  NOT_PICKED_UP, // 미픽업 (고객이 찾아가지 않아 종결) — 취소와 구분된다
}

/// 미픽업 주문의 **조회 응답 상태 문자열**.
///
/// 요청 어휘인 action(`OrderAction.NO_SHOW`)과는 별개 축이다 — 서버가 둘을 다른
/// 단어로 쓰는 전례가 있다(`ACCEPT`→`ACCEPTED`). action 은 `NO_SHOW` 로
/// **확정**됐고, 조회 응답 status 가 같은 단어인지는 **스테이징 실측 대기**다.
///
/// 확정되면 이 상수와 [kNotPickedUpServerAliases] 만 고치면 된다.
/// `ApiService._mapAppFitOrderStatus` 는 [kServerOrderStatus] 를 조회할 뿐이라
/// 손댈 일이 없다. 상세는 docs/ORDER_NOT_PICKED_UP.md.
const String kNotPickedUpServerStatus = 'NO_SHOW';

/// 실측 전 방어 별칭. 매핑표에 없는 값은 CANCELLED 로 떨어지므로, 응답 status 가
/// action 과 다른 단어면 **미픽업 주문이 화면에 '취소' 로 보이는 무증상 실패**가
/// 된다. 그 사고는 화면만 봐서는 알 수 없다.
///
/// **스테이징 실측 후 원소 1개로 줄일 것.** 판정은 화면이 아니라 로그로 한다 —
/// 별칭이 먹으면 화면은 정상으로 보이고, 미매핑일 때만
/// `알 수 없는 주문 상태` 경고가 뜬다.
const Set<String> kNotPickedUpServerAliases = <String>{
  kNotPickedUpServerStatus,
  'NOT_PICKED_UP',
};

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
  // 미픽업 — 정본 + 실측 전 방어 별칭([kNotPickedUpServerAliases] 와 같은 집합).
  // const 유지를 위해 펼치지 않고 직접 나열한다.
  'NO_SHOW': OrderStatus.NOT_PICKED_UP,
  'NOT_PICKED_UP': OrderStatus.NOT_PICKED_UP,
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
      OrderStatus.NOT_PICKED_UP => kNotPickedUpServerStatus,
    };

/// 상태 진행도(단조 격자). NEW < PREPARING < READY < DONE.
/// 터미널 상태([kTerminalStatusPriority])는 진행도 비교에서 제외한다.
const Map<OrderStatus, int> kOrderStatusProgress = <OrderStatus, int>{
  OrderStatus.NEW: 0,
  OrderStatus.PREPARING: 1,
  OrderStatus.READY: 2,
  OrderStatus.DONE: 3,
};

/// 진행도 격자 **밖**의 종결 상태. 앞에 올수록 강하다.
///
/// 격자에 넣지 않는 것이 핵심이다 — 넣으면 `kOrderStatusProgress[s] ?? 0` 폴백에
/// 걸려 NEW 급으로 취급되고, 서버가 stale READY 를 돌려줄 때마다 종결된 주문이
/// **폴링 주기마다 되살아난다**.
///
/// CANCELLED 가 NOT_PICKED_UP 보다 강한 근거:
/// - 취소는 환불/결제취소를 수반하고 취소 영수증 발행 트리거다. 취소를 미픽업으로
///   가리면 금전 사실이 화면·영수증에서 사라진다. 반대는 오해를 낳을 뿐 금전
///   사실은 보존된다 — 비대칭 손실.
/// - 미픽업 처리 후 클레임으로 환불(NOT_PICKED_UP → CANCELLED)은 현실적이지만
///   역방향은 성립하지 않는다.
const List<OrderStatus> kTerminalStatusPriority = <OrderStatus>[
  OrderStatus.CANCELLED,
  OrderStatus.NOT_PICKED_UP,
];

/// 서버 응답과 로컬 상태를 병합할 때 다운그레이드(예: PREPARING→NEW)를 막기 위한 헬퍼.
///
/// 서버 PUT 직후 GET 응답이 구버전을 돌려주는 타이밍에서, 로컬이 이미
/// 더 진행된 상태라면 서버의 구버전 상태로 덮어쓰지 않는다.
/// 터미널 상태는 어느 한쪽에만 있어도 우선하며, 둘 다 터미널이면
/// [kTerminalStatusPriority] 순서로 이긴다.
///
/// **교환법칙을 만족해야 한다** — 이 함수는 `refreshOrders` 에서 `(local, server)`
/// 로, `OrderSocketManager` 에서 `(order.status, eventStatus)` 로 불린다. 인자
/// 순서에 결과가 의존하면 폴링과 소켓이 서로를 덮어쓰며 화면이 깜빡인다.
///
/// 순수 함수(ref/state 비의존) — 상태 단조성 불변식의 단일 정의 지점.
OrderStatus resolveMergedStatus(OrderStatus local, OrderStatus server) {
  for (final terminal in kTerminalStatusPriority) {
    if (local == terminal || server == terminal) return terminal;
  }
  final lo = kOrderStatusProgress[local] ?? 0;
  final so = kOrderStatusProgress[server] ?? 0;
  return lo > so ? local : server;
}
