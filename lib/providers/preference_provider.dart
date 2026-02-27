import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/preference_service.dart';

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
