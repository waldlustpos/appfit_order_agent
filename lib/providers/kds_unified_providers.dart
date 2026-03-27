import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'order_history_provider.dart';
import '../constants/app_styles.dart';
import '../utils/logger.dart';
import 'dart:async';

part 'kds_unified_providers.g.dart';

// =============================================================================
// @Riverpod 패턴으로 통합된 KDS 상태 관리
// =============================================================================

/// KDS 모드 상태 관리 (기존 kdsProvider를 @riverpod로 변환)
@Riverpod(keepAlive: true)
class KdsMode extends _$KdsMode {
  @override
  bool build() => false;

  void setKdsMode(bool isKdsMode) {
    try {
      state = isKdsMode;
      logger.d('[KdsMode] KDS 모드 변경: $isKdsMode');
    } catch (e) {
      logger.d('[KdsMode] setKdsMode 오류: $e');
    }
  }
}

/// KDS 탭 인덱스 관리 (기본값: 1 = 진행 탭)
@Riverpod(keepAlive: true)
class KdsTabIndex extends _$KdsTabIndex {
  @override
  int build() => 1;

  void updateIndex(int index) {
    if (state != index) {
      state = index;
      logger.d('KDS: 탭 인덱스 변경 - $index');
    }
  }
}

/// KDS 전용 정렬 방향 관리
@riverpod
class KdsSortDirection extends _$KdsSortDirection {
  @override
  OrderSortDirection build() => OrderSortDirection.ASC;

  void updateDirection(OrderSortDirection direction) {
    if (state != direction) {
      state = direction;
      logger.d('KDS: 정렬 방향 변경 - ${direction.name}');
    }
  }
}

/// 탭별 정렬 방향 통합 관리
@Riverpod(keepAlive: true)
class KdsTabSortDirections extends _$KdsTabSortDirections {
  @override
  Map<int, OrderSortDirection> build() => {
        0: OrderSortDirection.ASC, // 전체 탭: 오래된 주문순
        1: OrderSortDirection.ASC, // 진행 탭: 오래된 주문순
        2: OrderSortDirection.DESC, // 픽업 탭: 최신 주문순
        3: OrderSortDirection.DESC, // 완료 탭: 최신 주문순
        4: OrderSortDirection.DESC, // 취소 탭: 최신 주문순
      };

  OrderSortDirection getSortDirection(int tabIndex) {
    return state[tabIndex] ?? OrderSortDirection.ASC;
  }

  void setSortDirection(int tabIndex, OrderSortDirection direction) {
    if (state[tabIndex] != direction) {
      state = {...state, tabIndex: direction};
      logger.d('KDS: 탭 $tabIndex 정렬 변경 - ${direction.name}');
    }
  }

  void resetAllSortDirections() {
    state = {
      0: OrderSortDirection.ASC,
      1: OrderSortDirection.ASC,
      2: OrderSortDirection.DESC,
      3: OrderSortDirection.DESC,
      4: OrderSortDirection.DESC,
    };
  }
}

/// 현재 활성 탭의 정렬 방향 (계산된 값)
@riverpod
OrderSortDirection kdsCurrentSortDirection(Ref ref) {
  final tabIndex = ref.watch(kdsTabIndexProvider);
  final tabSortDirections = ref.watch(kdsTabSortDirectionsProvider.notifier);
  return tabSortDirections.getSortDirection(tabIndex);
}

/// 스크롤 컨트롤러 통합 관리
@Riverpod(keepAlive: true)
class KdsScrollControllerMap extends _$KdsScrollControllerMap {
  @override
  Map<String, ScrollController> build() {
    // Provider가 dispose될 때 모든 스크롤 컨트롤러 정리
    ref.onDispose(() {
      logger.d('KDS: KdsScrollControllerMap dispose - 모든 스크롤 컨트롤러 정리');
      for (final controller in state.values) {
        try {
          controller.dispose();
        } catch (e) {
          logger.d('KDS: 스크롤 컨트롤러 dispose 오류 무시됨: $e');
        }
      }
    });
    return {};
  }

  ScrollController getOrCreateController(String orderId) {
    if (!state.containsKey(orderId)) {
      final controller = ScrollController();
      state = {...state, orderId: controller};
      logger.d('KDS: 스크롤 컨트롤러 생성 - $orderId');
    }
    return state[orderId]!;
  }

  ScrollController? getExistingController(String orderId) {
    return state[orderId];
  }

  void disposeController(String orderId) {
    final controller = state[orderId];
    if (controller != null) {
      controller.dispose();
      final newState = Map<String, ScrollController>.from(state);
      newState.remove(orderId);
      state = newState;
      logger.d('KDS: 스크롤 컨트롤러 해제 - $orderId');
    }
  }

  void disposeAllControllers() {
    for (final controller in state.values) {
      controller.dispose();
    }
    state = {};
    logger.d('KDS: 모든 스크롤 컨트롤러 해제');
  }
}

/// 스크롤 버튼 상태 관리
@riverpod
class KdsScrollButtonStates extends _$KdsScrollButtonStates {
  @override
  Map<String, ScrollButtonState> build() => {};

  void updateScrollButtons(
      String orderId, bool canScrollUp, bool canScrollDown) {
    final newState = ScrollButtonState(
      canScrollUp: canScrollUp,
      canScrollDown: canScrollDown,
    );

    // 상태가 실제로 변경된 경우에만 업데이트
    final currentState = state[orderId];
    if (currentState == null || currentState != newState) {
      state = {...state, orderId: newState};


    }
  }

  ScrollButtonState getScrollButtonState(String orderId) {
    return state[orderId] ??
        const ScrollButtonState(canScrollUp: false, canScrollDown: false);
  }

  void removeScrollButtonState(String orderId) {
    if (state.containsKey(orderId)) {
      final newState = Map<String, ScrollButtonState>.from(state);
      newState.remove(orderId);
      state = newState;
    }
  }
}

/// 체크된 아이템 상태 관리
@riverpod
class KdsCheckedItems extends _$KdsCheckedItems {
  @override
  Map<String, Set<int>> build() => {};

  void toggle(String orderId, int menuIndex, bool value) {
    final currentChecked = Set<int>.from(state[orderId] ?? {});

    if (value) {
      currentChecked.add(menuIndex);
    } else {
      currentChecked.remove(menuIndex);
    }

    state = {...state, orderId: currentChecked};
  }

  bool isChecked(String orderId, int menuIndex) {
    return state[orderId]?.contains(menuIndex) ?? false;
  }

  bool isAllChecked(String orderId, int totalMenuCount) {
    return (state[orderId]?.length ?? 0) == totalMenuCount;
  }

  void clearCheckedItems(String orderId) {
    if (state.containsKey(orderId)) {
      final newState = Map<String, Set<int>>.from(state);
      newState.remove(orderId);
      state = newState;
    }
  }
}

/// 스크롤 위치 관리
@Riverpod(keepAlive: true)
class KdsScrollPositions extends _$KdsScrollPositions {
  @override
  Map<String, double> build() => {};

  void saveScrollPosition(String orderId, double position) {
    // 1픽셀 이상 차이가 날 때만 저장 (불필요한 업데이트 방지)
    final currentPosition = state[orderId] ?? 0.0;
    if ((position - currentPosition).abs() > 1.0) {
      state = {...state, orderId: position};
      logger.d(
          'KDS: 스크롤 위치 저장 - $orderId: ${position.toStringAsFixed(1)} (이전: ${currentPosition.toStringAsFixed(1)})');
    }
  }

  double getScrollPosition(String orderId) {
    final position = state[orderId] ?? 0.0;
    logger.d('KDS: 스크롤 위치 조회 - $orderId: ${position.toStringAsFixed(1)}');
    return position;
  }

  void clearScrollPosition(String orderId) {
    if (state.containsKey(orderId)) {
      final newState = Map<String, double>.from(state);
      newState.remove(orderId);
      state = newState;
    }
  }

  void clearAllScrollPositions() {
    state = {};
  }
}

/// 카드 애니메이션 상태 관리 (개선된 버전)
@riverpod
class KdsCardAnimations extends _$KdsCardAnimations {
  final Map<String, Timer?> _animationTimers = {};

  @override
  Map<String, CardAnimationState> build() {
    // Provider가 dispose될 때 모든 Timer 정리
    ref.onDispose(() {
      logger.d('KDS: KdsCardAnimations dispose - 모든 Timer 정리');
      for (final timer in _animationTimers.values) {
        try {
          timer?.cancel();
        } catch (e) {
          logger.d('KDS: Timer cancel 오류 무시됨: $e');
        }
      }
      _animationTimers.clear();
    });
    return {};
  }

  void startNewOrderBorderAnimation(String orderId) {
    // 기존 타이머가 있으면 취소
    _animationTimers[orderId]?.cancel();

    // 애니메이션 시작
    state = {
      ...state,
      orderId: const CardAnimationState(
        isAnimating: true,
        borderColor: AppStyles.kMainColor,
      )
    };

    // 1.5초 후 페이드아웃
    _animationTimers[orderId] = Timer(const Duration(milliseconds: 1500), () {
      if (state.containsKey(orderId)) {
        state = {
          ...state,
          orderId: state[orderId]!.copyWith(
            borderColor: Colors.transparent,
            isAnimating: false,
          )
        };

        // 100ms 후 완전 제거
        _animationTimers[orderId] =
            Timer(const Duration(milliseconds: 100), () {
          _removeAnimation(orderId);
        });
      }
    });
  }

  void startStatusChangeAnimation(String orderId) {
    // 기존 타이머가 있으면 취소
    _animationTimers[orderId]?.cancel();

    // 애니메이션 시작
    state = {
      ...state,
      orderId: const CardAnimationState(
        isAnimating: true,
        borderColor: AppStyles.kMainColor,
      )
    };

    // 1초 후 페이드아웃 (상태 변경은 짧게)
    _animationTimers[orderId] = Timer(const Duration(milliseconds: 1000), () {
      if (state.containsKey(orderId)) {
        state = {
          ...state,
          orderId: state[orderId]!.copyWith(
            borderColor: Colors.transparent,
            isAnimating: false,
          )
        };

        // 100ms 후 완전 제거
        _animationTimers[orderId] =
            Timer(const Duration(milliseconds: 100), () {
          _removeAnimation(orderId);
        });
      }
    });
  }

  void _removeAnimation(String orderId) {
    _animationTimers[orderId]?.cancel();
    _animationTimers.remove(orderId);

    if (state.containsKey(orderId)) {
      final newState = Map<String, CardAnimationState>.from(state);
      newState.remove(orderId);
      state = newState;
    }
  }

  CardAnimationState getAnimationState(String orderId) {
    return state[orderId] ?? const CardAnimationState();
  }

  void clearAnimation(String orderId) {
    _removeAnimation(orderId);
  }

  void clearAllAnimations() {
    // 모든 타이머 취소
    for (final timer in _animationTimers.values) {
      timer?.cancel();
    }
    _animationTimers.clear();
    state = {};
  }

  // @riverpod에서는 자동으로 dispose 처리됨
  // dispose가 필요한 경우 ref.onDispose 사용
}

// =============================================================================
// 데이터 클래스들 (기존과 동일)
// =============================================================================

class ScrollButtonState {
  final bool canScrollUp;
  final bool canScrollDown;

  const ScrollButtonState({
    required this.canScrollUp,
    required this.canScrollDown,
  });

  ScrollButtonState copyWith({bool? canScrollUp, bool? canScrollDown}) {
    return ScrollButtonState(
      canScrollUp: canScrollUp ?? this.canScrollUp,
      canScrollDown: canScrollDown ?? this.canScrollDown,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ScrollButtonState &&
        other.canScrollUp == canScrollUp &&
        other.canScrollDown == canScrollDown;
  }

  @override
  int get hashCode => canScrollUp.hashCode ^ canScrollDown.hashCode;
}

class CardAnimationState {
  final bool isAnimating;
  final double opacity;
  final Color borderColor;

  const CardAnimationState({
    this.isAnimating = false,
    this.opacity = 1.0,
    this.borderColor = Colors.transparent,
  });

  CardAnimationState copyWith({
    bool? isAnimating,
    double? opacity,
    Color? borderColor,
  }) {
    return CardAnimationState(
      isAnimating: isAnimating ?? this.isAnimating,
      opacity: opacity ?? this.opacity,
      borderColor: borderColor ?? this.borderColor,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CardAnimationState &&
        other.isAnimating == isAnimating &&
        other.opacity == opacity &&
        other.borderColor == borderColor;
  }

  @override
  int get hashCode =>
      isAnimating.hashCode ^ opacity.hashCode ^ borderColor.hashCode;
}
