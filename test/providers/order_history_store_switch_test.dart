import 'package:appfit_order_agent/models/order_menu_model.dart';
import 'package:appfit_order_agent/models/order_model.dart';
import 'package:appfit_order_agent/models/store_model.dart';
import 'package:appfit_order_agent/providers/providers.dart';
import 'package:appfit_order_agent/utils/model_parse_utils.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// orderHistoryProvider 의 매장 전환 안전성 회귀 테스트.
///
/// 증상: KDS 모드에서 [로그인 → 과거 날짜 조회 → 로그아웃 → 다른 매장 로그인 → 전체 탭]
/// 이면 달력 옆 "조회: N건" 이 이전 매장 수치로 남았다. 원인은
///  (1) orderHistoryProvider 가 keepAlive 라 로그아웃해도 이전 매장 결과를 보유하고,
///  (2) 그 provider 가 selectedDateProvider(autoDispose)를 watch 해 선택 날짜까지
///      살아남으며(= 재로그인 후에도 isToday=false 로 건수 위젯이 보임),
///  (3) 조기 반환 캐시 키가 날짜뿐이라 매장이 바뀌어도 이전 목록을 그대로 돌려준 것.
/// 아래 테스트는 (1)(3) 을 고정한다.

class _FakeApiService implements ApiService {
  /// 요청된 (storeId, date) 기록.
  final List<String> orderRequests = [];

  /// storeId → 반환할 주문 건수.
  final Map<String, int> countByStore;

  _FakeApiService(this.countByStore);

  @override
  Future<List<OrderModel>> getOrders(
    String storeId, {
    String? startDate,
    String? endDate,
    OrderStatus? orderStatus,
  }) async {
    orderRequests.add('$storeId/$startDate');
    final count = countByStore[storeId] ?? 0;
    return List.generate(
        count, (i) => _order(orderNo: '$storeId-$i', storeId: storeId));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeStore extends Store {
  _FakeStore(this._initial);

  final StoreModel? _initial;

  @override
  Future<StoreModel?> build() async => _initial;

  void settle(StoreModel? model) => state = AsyncData(model);
}

OrderModel _order({required String orderNo, required String storeId}) {
  return OrderModel(
    orderNo: orderNo,
    shopOrderNo: '0001',
    orderStatus: OrderStatus.DONE.name,
    orderedAt: DateTime.utc(2026, 1, 1, 9, 0),
    totalAmount: 9000,
    status: OrderStatus.DONE,
    storeId: storeId,
    userId: 'user-1',
    ordererName: '홍길동',
    orderCount: '1',
    paymentAmount: 9000,
    discountAmount: 0,
    paymentType: 'CARD',
    paymentCode: 'CARD',
    menus: const <OrderMenuModel>[],
    orderType: 'T',
    kdsOrderType: 1,
    kioskId: 'kiosk-1',
    updateTime: DateTime.utc(2026, 1, 1, 9, 0),
  );
}

StoreModel _store(String id) =>
    StoreModel(storeId: id, name: '테스트매장', isOpen: true);

({ProviderContainer container, _FakeApiService api, _FakeStore store}) _build(
  StoreModel? initial,
  Map<String, int> countByStore,
) {
  final api = _FakeApiService(countByStore);
  final store = _FakeStore(initial);
  final container = ProviderContainer(overrides: [
    apiServiceProvider.overrideWithValue(api),
    storeProvider.overrideWith(() => store),
  ]);
  addTearDown(container.dispose);
  return (container: container, api: api, store: store);
}

void main() {
  const pastDate = '2026-07-20';

  test('로그아웃 정리(invalidate)는 이전 매장의 조회 결과를 남기지 않는다', () async {
    final b = _build(_store('PAIK00001'), {'PAIK00001': 5, 'TPCP00001': 2});
    await b.container.read(storeProvider.future);

    // 1) PAIK 로 과거 날짜 조회 → 5건
    b.container.read(selectedDateProvider.notifier).updateDate(pastDate);
    expect((await b.container.read(orderHistoryProvider.future)).length, 5);

    // 2) 로그아웃 정리 (home_screen._handleLogout 과 동일 순서)
    b.store.settle(_store('TPCP00001'));
    b.container.invalidate(selectedDateProvider);
    b.container.invalidate(orderHistoryProvider);

    // 3) 선택 날짜는 오늘로 복귀 → KDS 건수 위젯 자체가 숨는다
    expect(b.container.read(selectedDateProvider), todayDateString());

    // 4) 재조회는 새 매장으로만, 결과도 새 매장 것
    final after = await b.container.read(orderHistoryProvider.future);
    expect(after.length, 2);
    expect(b.api.orderRequests.last.startsWith('TPCP00001'), isTrue);
  });

  test('매장이 바뀌면 같은 날짜여도 캐시를 재사용하지 않는다', () async {
    final b = _build(_store('PAIK00001'), {'PAIK00001': 5, 'TPCP00001': 2});
    await b.container.read(storeProvider.future);

    b.container.read(selectedDateProvider.notifier).updateDate(pastDate);
    expect((await b.container.read(orderHistoryProvider.future)).length, 5);
    expect(b.api.orderRequests, ['PAIK00001/$pastDate']);

    // 매장만 바뀐 상태에서 provider 를 다시 살린다(로그아웃 정리 누락 상황 가정).
    b.store.settle(_store('TPCP00001'));
    b.container.invalidate(orderHistoryProvider);
    final after = await b.container.read(orderHistoryProvider.future);

    expect(after.length, 2, reason: '이전 매장(PAIK) 캐시를 반환하면 안 됨');
    expect(b.api.orderRequests, ['PAIK00001/$pastDate', 'TPCP00001/$pastDate']);
  });

  test('같은 매장·같은 날짜는 캐시 재사용(불필요한 재조회 없음)', () async {
    final b = _build(_store('PAIK00001'), {'PAIK00001': 5});
    await b.container.read(storeProvider.future);

    b.container.read(selectedDateProvider.notifier).updateDate(pastDate);
    await b.container.read(orderHistoryProvider.future);
    expect(b.api.orderRequests.length, 1);

    // 구독만 다시 붙는 경우 재조회하지 않는다.
    await b.container.read(orderHistoryProvider.future);
    expect(b.api.orderRequests.length, 1);
  });
}
