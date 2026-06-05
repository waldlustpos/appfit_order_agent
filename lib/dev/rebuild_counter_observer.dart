import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:appfit_order_agent/providers/order/order_computed_providers.dart';
import 'package:appfit_order_agent/providers/order/order_provider.dart';
import 'package:appfit_order_agent/utils/logger.dart';

/// [DEV ONLY] 리빌드 카운트 검증용 Riverpod 옵저버.
///
/// 핫패스(WebSocket → OrderProvider → 파생 provider → 카드) 의 **provider 재계산
/// 횟수**(원인 층)를 콘솔 로그로 흘려보낸다. 위젯 build() 횟수(결과 층)는 DevTools
/// "Track Widget Builds"(Widget Rebuild Stats) 로 별도 확인한다.
///
/// 사용: `main.dart` 의 `ProviderScope(observers: kDebugMode ? [RebuildCounterObserver()] : const [])`.
/// **release 영향 없음**(kDebugMode 가드). 검증이 끝나면 wiring 을 제거해도 된다.
///
/// 로그 읽는 법:
/// - `[REBUILD][update] kdsTabOrdersProvider #N` → 탭 필터/정렬 묶음이 N번째 재계산.
/// - `[REBUILD][add]    orderByIdProvider(<id>)` → 해당 주문 카드가 처음 mount(family 신규).
/// - `[REBUILD][update] orderByIdProvider(<id>)` → 그 카드의 주문 데이터가 바뀜(상태 변경 등).
///   → **새 주문 1건이 들어와도 기존 카드 id 들은 update 가 찍히지 않아야** 정상(family 디커플링).
///
/// `#N` 은 앱 시작 이후 누적값이다. 새 주문 도착의 영향을 보려면 도착 전/후의 증가분(delta)을 본다.
class RebuildCounterObserver extends ProviderObserver {
  RebuildCounterObserver();

  final Map<String, int> _updateCounts = <String, int>{};

  /// watchlist 에 없는 provider 는 `null` 을 돌려 로그에서 제외한다(노이즈 제어).
  String? _label(ProviderBase<Object?> provider) {
    if (identical(provider, orderProvider)) return 'orderProvider';
    if (identical(provider, ordersByIdProvider)) return 'ordersByIdProvider';
    if (identical(provider, kdsTabOrdersProvider)) {
      return 'kdsTabOrdersProvider';
    }
    if (identical(provider, orderStatusOrdersProvider)) {
      return 'orderStatusOrdersProvider';
    }
    if (identical(provider, kdsHistoryAllOrdersProvider)) {
      return 'kdsHistoryAllOrdersProvider';
    }
    if (provider.from == orderByIdProvider) {
      return 'orderByIdProvider(${provider.argument})';
    }
    return null;
  }

  @override
  void didAddProvider(
    ProviderBase<Object?> provider,
    Object? value,
    ProviderContainer container,
  ) {
    final label = _label(provider);
    if (label == null) return;
    // family(카드) 신규 mount 만 add 로 의미가 있음. 단발 provider 의 최초 add 는 생략.
    if (provider.from == orderByIdProvider) {
      logger.d('[REBUILD][add]    $label  (card mount)');
    }
  }

  @override
  void didUpdateProvider(
    ProviderBase<Object?> provider,
    Object? previousValue,
    Object? newValue,
    ProviderContainer container,
  ) {
    final label = _label(provider);
    if (label == null) return;
    final n = (_updateCounts[label] ?? 0) + 1;
    _updateCounts[label] = n;
    logger.d('[REBUILD][update] $label  #$n');
  }
}
