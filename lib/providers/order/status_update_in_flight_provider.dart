import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'status_update_in_flight_provider.g.dart';

/// 주문별 상태변경(PUT) in-flight 집합.
///
/// 원래 `OrderNotifier` 의 private `Set<String>` 이었는데 provider 로 승격했다.
/// 이유(2026-08-08 에뮬레이터 실검증에서 발견된 버그): KDS 카드는
/// `isDetailLoaded`/`kdsOrderType` 에 따라 서브트리를 통째로 교체하므로, 진행
/// 중에 버튼 위젯의 State 가 재생성되면 로컬 busy 플래그가 리셋돼 재탭이
/// 관통했다. **UI 의 busy 표시가 State 수명과 무관하려면 진실이 위젯 밖에
/// 있어야 한다** — 그 진실이 이 provider 다.
///
/// - 쓰기: `OrderNotifier.updateOrderStatus` 만 (진입 [tryAcquire] / 종료 [release])
/// - 읽기: KDS 카드 버튼이 주문별 `contains` 를 select 해 `externalBusy` 로 사용
@Riverpod(keepAlive: true)
class StatusUpdateInFlight extends _$StatusUpdateInFlight {
  @override
  Set<String> build() => const <String>{};

  /// 진입 시도. 이미 진행 중이면 false (호출부는 중복 요청을 거절해야 한다).
  ///
  /// contains+add 가 동기 한 틱 안에서 일어나므로 레이스는 없다.
  bool tryAcquire(String orderId) {
    if (state.contains(orderId)) return false;
    state = {...state, orderId};
    return true;
  }

  /// 종료(성공/실패/예외 공통). 반드시 finally 에서 호출된다.
  void release(String orderId) {
    if (!state.contains(orderId)) return;
    state = <String>{...state}..remove(orderId);
  }
}
