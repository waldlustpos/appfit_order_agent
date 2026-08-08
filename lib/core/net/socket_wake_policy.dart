import 'package:appfit_core/appfit_core.dart' as appfit_core;

/// HTTP 건강도가 회복됐을 때, 잠든 소켓을 깨워야 하는지 판정한다.
///
/// **왜 필요한가**: 코어 소켓은 빠른 재연결 5회(3·6·12·24·48s = 누적 93초)가
/// 실패하면 [appfit_core.ConnectionStatus.disconnected] 를 방출하고 **5분 간격
/// 느린 재시도**로 넘어간다(코어 v1.2.0). 복구 자체는 코어가 보장하므로 이
/// 정책이 줄이는 것은 **다음 시도까지 최대 5분인 대기**다. 링크(wifi/ethernet)는
/// 살아 있고 상위 경로만 죽는 장애(NAT 세션 고갈·DNS 장애·업링크 포화)에서는
/// `connectivity_plus` 이벤트가 오지 않아 코어가 스스로 대기를 앞당길 수단이
/// 없다 — "HTTP 요청이 다시 성공하기 시작했다"가 앱만 아는 복원 신호다.
///
/// 코어 v1.2.0 이전에는 5회 소진 후 **완전히 정지**했고, 복구가 오직
/// `connectivity_plus` 이벤트에만 달려 있어 앱 재시작 전까지 실시간 주문 수신이
/// 영구히 멈췄다 — PAIK00002(新橋店)에서 실제로 발생한 시나리오이며, 이 정책은
/// 원래 그 영구 침묵의 탈출구로 만들어졌다가 지금은 단축 경로가 됐다.
///
/// 판정을 순수 함수로 분리한 이유는 `OrderNotifier` 전체를 기동하지 않고
/// 테스트하기 위해서다 (`isTransientNetworkError` 승격과 같은 규약).
///
/// - [status]가 `disconnected` 일 때만 깨운다. `reconnecting` 은 코어가 빠른
///   백오프를 돌리는 중(최대 48초 대기)이라 간섭할 이득이 없다.
/// - [isLoggedOut] 이면 절대 깨우지 않는다. `disconnected` 는 느린 재시도 진입
///   말고도 **의도적 종료**(로그아웃·앱 종료)에서도 나오기 때문이다.
bool shouldWakeSocket({
  required appfit_core.ConnectionStatus status,
  required bool isLoggedOut,
}) {
  if (isLoggedOut) return false;
  return status == appfit_core.ConnectionStatus.disconnected;
}
