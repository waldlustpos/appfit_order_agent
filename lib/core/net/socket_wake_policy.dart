import 'package:appfit_core/appfit_core.dart' as appfit_core;

/// HTTP 건강도가 회복됐을 때, 잠든 소켓을 깨워야 하는지 판정한다.
///
/// **왜 필요한가**: 코어 소켓은 재연결 백오프를 5회(3·6·12·24·48s = 누적 93초)
/// 소진하면 [appfit_core.ConnectionStatus.disconnected] 를 방출하고 **정지**한다.
/// 그 뒤의 복구는 오직 `connectivity_plus` 의 인터페이스 변화 이벤트에만
/// 의존하는데, 링크(wifi/ethernet)는 살아 있고 상위 경로만 죽는 장애
/// (NAT 세션 고갈·DNS 장애·업링크 포화)에서는 그 이벤트가 **오지 않는다**.
/// 결과적으로 앱 재시작 전까지 실시간 주문 수신이 영구히 멈춘다 —
/// PAIK00002(新橋店)에서 실제로 발생한 시나리오다.
///
/// 그래서 "HTTP 요청이 다시 성공하기 시작했다"는 사실 자체를 네트워크 복원
/// 신호로 삼아 소켓을 깨운다. 근본 수정(백오프 소진 후에도 상한 간격으로
/// 무한 재시도)은 코어 몫이고, 이 정책은 앱 레이어의 완화책이다.
///
/// 판정을 순수 함수로 분리한 이유는 `OrderNotifier` 전체를 기동하지 않고
/// 테스트하기 위해서다 (`isTransientNetworkError` 승격과 같은 규약).
///
/// - [status]가 `disconnected` 일 때만 깨운다. `reconnecting` 은 코어가 이미
///   백오프를 돌리는 중이라 간섭하면 오히려 방해가 된다.
/// - [isLoggedOut] 이면 절대 깨우지 않는다. `disconnected` 는 백오프 소진
///   말고도 **의도적 종료**(로그아웃·앱 종료)에서도 나오기 때문이다.
bool shouldWakeSocket({
  required appfit_core.ConnectionStatus status,
  required bool isLoggedOut,
}) {
  if (isLoggedOut) return false;
  return status == appfit_core.ConnectionStatus.disconnected;
}
