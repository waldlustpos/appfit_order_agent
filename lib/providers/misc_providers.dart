import 'dart:async'; // For Timer

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:appfit_order_agent/providers/order/order_provider.dart';
import 'package:appfit_order_agent/services/print_service.dart';
import 'package:appfit_order_agent/utils/logger.dart';
import 'package:appfit_order_agent/utils/model_parse_utils.dart';

// 여러 화면에서 공유하는 소규모 전역 프로바이더/상태/확장 모음.
// providers.dart 는 export 전용 barrel 로 유지하고, 인라인 정의는 여기에 둔다.
part 'misc_providers.g.dart';

@Riverpod(keepAlive: true)
PrintService printService(Ref ref) {
  return PrintService(ref);
}

// State provider for selected date
@riverpod
class SelectedDate extends _$SelectedDate {
  @override
  String build() {
    return todayDateString();
  }

  void updateDate(String newDate) {
    state = newDate;
  }
}

// Home Screen Tab Index Provider
final homeTabIndexProvider = StateProvider<int>((ref) => 0);

// Blink State Provider - 주문 알림 점멸 상태 관리
final blinkStateProvider =
    StateNotifierProvider<BlinkStateNotifier, BlinkState>((ref) {
  return BlinkStateNotifier(ref);
});

// Blink State 클래스
class BlinkState {
  final bool isBlinking;
  final int activeOrderCount;
  final bool stopBlinking;

  BlinkState({
    this.isBlinking = false,
    this.activeOrderCount = 0,
    this.stopBlinking = false,
  });

  BlinkState copyWith({
    bool? isBlinking,
    int? activeOrderCount,
    bool? stopBlinking,
  }) {
    return BlinkState(
      isBlinking: isBlinking ?? this.isBlinking,
      activeOrderCount: activeOrderCount ?? this.activeOrderCount,
      stopBlinking: stopBlinking ?? this.stopBlinking,
    );
  }
}

// Blink State Notifier
class BlinkStateNotifier extends StateNotifier<BlinkState> {
  final Ref ref;
  Timer? _blinkTimer;

  BlinkStateNotifier(this.ref) : super(BlinkState()) {
    _setupBlinkTimer();
    _listenToOrderCount();
  }

  void _setupBlinkTimer() {
    _blinkTimer?.cancel();
    _blinkTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (state.activeOrderCount > 0 && !state.stopBlinking) {
        state = state.copyWith(isBlinking: !state.isBlinking);
      } else if (state.isBlinking) {
        state = state.copyWith(isBlinking: false);
      }
    });
  }

  void _listenToOrderCount() {
    // orderProvider의 activeOrderCount를 구독하여 자동 동기화
    ref.listen<int>(
      orderProvider.select((s) => s.activeOrderCount),
      (previous, next) {
        logger.d('[BlinkStateNotifier] 주문 카운트 변경 감지: $previous -> $next');
        state = state.copyWith(activeOrderCount: next);

        if (next == 0) {
          stopBlinking();
        } else if ((previous ?? 0) < next) {
          // 신규 주문이 추가된 경우 (카운트 증가) 점멸 중지 상태 해제
          resetStopBlinking();
        }
      },
      fireImmediately: true,
    );
  }

  void stopBlinking() {
    state = state.copyWith(isBlinking: false, stopBlinking: true);
  }

  void startBlinking() {
    state = state.copyWith(isBlinking: true, stopBlinking: false);
  }

  void updateActiveOrderCount(int count) {
    state = state.copyWith(activeOrderCount: count);
  }

  void resetStopBlinking() {
    state = state.copyWith(stopBlinking: false);
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    super.dispose();
  }
}

// --- Helper Extensions --- (선택사항: 날짜 비교 로직)
// 예: DateTime 클래스 확장하여 날짜 비교 단순화
extension DateOnlyCompare on DateTime {
  bool isSameDate(DateTime other) {
    return year == other.year && month == other.month && day == other.day;
  }
}
