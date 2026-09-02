import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:appfit_order_agent/services/preference_service.dart';

part 'preference_provider.g.dart';

// PreferenceService 인스턴스를 제공하는 Provider
// PreferenceService는 앱 시작 시 초기화가 필요할 수 있으므로,
// keepAlive: true를 사용하고, 초기화 로직을 추가하는 것을 고려할 수 있습니다.
@Riverpod(keepAlive: true)
PreferenceService preferenceService(Ref ref) {
  // PreferenceService 인스턴스 생성.
  // 만약 PreferenceService.init() 같은 비동기 초기화가 필요하다면
  // FutureProvider나 AsyncNotifier를 사용하는 것이 더 적합할 수 있습니다.
  // 현재 구조에서는 생성자만 호출합니다.
  return PreferenceService();
}

// 주문내역 스크롤 설정을 위한 StateProvider
final orderHistoryScrollProvider = StateProvider<bool>((ref) {
  final preferenceService = PreferenceService();
  return preferenceService.getOrderHistoryScroll();
});

// 주문 출처별(앱/키오스크) 카드 배경색 설정 — 카드가 실시간 watch
final orderSourceColorProvider = StateProvider<bool>((ref) {
  return PreferenceService().getOrderSourceColor();
});

// 키오스크/POS 주문 노출 설정의 **reactive 사본**.
//
// 접수 화면(OrderProvider)은 유입 시점에 PreferenceService 를 직접 읽어 거르지만
// (`_shouldShowOrder`), 주문내역의 과거 날짜는 API 결과를 그대로 그리므로 설정을
// 다시 적용해야 한다. Provider 로 두는 이유는 캐시 무효화 때문이다 —
// PreferenceService 직접 읽기는 설정 변경을 통지하지 못해, 설정 화면에서 토글하고
// 돌아와도 이미 계산된 목록이 그대로 남는다. 정본은 SharedPreferences 이고 이 두
// 값은 `_saveSettings` 에서 함께 갱신한다.
final showKioskOrderProvider = StateProvider<bool>((ref) {
  return PreferenceService().getShowKioskOrder();
});

final showPosOrderProvider = StateProvider<bool>((ref) {
  return PreferenceService().getShowPosOrder();
});
