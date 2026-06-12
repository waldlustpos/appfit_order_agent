import 'dart:async';

import 'package:appfit_order_agent/core/orders/cache/order_detail_cache.dart';
import 'package:appfit_order_agent/models/order_menu_model.dart';
import 'package:appfit_order_agent/models/order_model.dart';
import 'package:appfit_order_agent/models/store_model.dart';
import 'package:appfit_order_agent/providers/order/order_cache_manager.dart';
import 'package:appfit_order_agent/providers/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// OrderCacheManager characterization 테스트.
///
/// 캐시 등록/조회/clear, fetchOrderDetail 의 캐시 우선·중복 로딩 방지·매장정보 가드,
/// getOrderDetail 의 상태 merge 규칙(updateTime isAfter)을 현재 동작 그대로 고정한다.
///
/// 만료(1h) 동작은 OrderDetailCache 가 DateTime.now() 를 직접 사용하고
/// maxCacheAge 가 상수라 시계 주입 seam 없이는 단위 테스트 불가 (blockers 참고).
/// getOrder 호출을 제어하는 fake. 나머지 멤버는 호출되지 않으므로 noSuchMethod.
class _FakeApiService implements ApiService {
  _FakeApiService(this.responder);

  final Future<OrderModel> Function(int callIndex) responder;
  int callCount = 0;
  final List<String> requestedOrderIds = [];

  @override
  Future<OrderModel> getOrder(String orderId, {String? storeId}) {
    requestedOrderIds.add(orderId);
    final i = callCount++;
    return responder(i);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// storeProvider 오버라이드용 fake notifier. build 만 대체한다.
class _FakeStore extends Store {
  _FakeStore(this._model);

  final StoreModel? _model;

  @override
  Future<StoreModel?> build() async => _model;
}

StoreModel _store({String storeId = 'store-1'}) =>
    StoreModel(storeId: storeId, name: '테스트매장', isOpen: true);

OrderModel _order({
  String orderNo = 'order-1',
  OrderStatus status = OrderStatus.PREPARING,
  DateTime? updateTime,
}) {
  return OrderModel(
    orderNo: orderNo,
    shopOrderNo: '0001',
    orderStatus: status.name,
    orderedAt: DateTime.utc(2026, 1, 1, 9),
    totalAmount: 9000,
    status: status,
    storeId: 'store-1',
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
    updateTime: updateTime ?? DateTime.utc(2026, 1, 1, 9),
  );
}

({
  OrderCacheManager manager,
  OrderDetailCache cache,
  ProviderContainer container,
}) _build({
  _FakeApiService? api,
  StoreModel? store,
}) {
  final cache = OrderDetailCache();
  final container = ProviderContainer(overrides: [
    if (api != null) apiServiceProvider.overrideWithValue(api),
    storeProvider.overrideWith(() => _FakeStore(store)),
  ]);
  addTearDown(container.dispose);
  final provider =
      Provider<OrderCacheManager>((ref) => OrderCacheManager(ref, cache));
  return (
    manager: container.read(provider),
    cache: cache,
    container: container,
  );
}

void main() {
  group('캐시 등록/조회 위임 (getCachedOrderDetail / hasDetailCache)', () {
    test('미등록 orderId → null / false', () {
      final b = _build();
      expect(b.manager.getCachedOrderDetail('none'), isNull);
      expect(b.manager.hasDetailCache('none'), isFalse);
    });

    test('캐시에 put 된 주문은 조회/존재 확인 가능', () {
      final b = _build();
      final order = _order(orderNo: 'order-1');
      b.cache.put('order-1', order);
      expect(b.manager.getCachedOrderDetail('order-1'), equals(order));
      expect(b.manager.hasDetailCache('order-1'), isTrue);
    });

    test('cache.clear 후 모든 조회 miss', () {
      final b = _build();
      b.cache.put('order-1', _order());
      b.cache.clear();
      expect(b.manager.hasDetailCache('order-1'), isFalse);
      expect(b.cache.size, 0);
    });

    test('cleanupExpiredEntries 는 만료되지 않은 항목을 제거하지 않음', () {
      // 만료 양성 케이스(1h 경과)는 DateTime.now() 직접 사용 + 상수 TTL 로
      // 시계 주입 없이는 검증 불가. 음성 케이스만 고정한다.
      final b = _build();
      b.cache.put('order-1', _order());
      b.manager.cleanupExpiredEntries();
      expect(b.manager.hasDetailCache('order-1'), isTrue);
    });
  });

  group('updateOrderInCache', () {
    test('캐시 히트 시 status/orderStatus 갱신 + updateTime 은 now 로 교체', () {
      final b = _build();
      final before = DateTime.now();
      b.cache.put(
          'order-1',
          _order(
              status: OrderStatus.PREPARING,
              updateTime: DateTime.utc(2026, 1, 1, 9)));

      b.manager.updateOrderInCache('order-1', OrderStatus.READY, '2009');

      final updated = b.manager.getCachedOrderDetail('order-1')!;
      expect(updated.status, OrderStatus.READY);
      expect(updated.orderStatus, '2009');
      expect(updated.updateTime.isBefore(before), isFalse); // now 로 교체됨
    });

    test('캐시 미스 시 no-op (크래시 없음, 새 항목 생성 안 함)', () {
      final b = _build();
      b.manager.updateOrderInCache('ghost', OrderStatus.READY, '2009');
      expect(b.manager.hasDetailCache('ghost'), isFalse);
    });
  });

  group('fetchOrderDetail', () {
    test('캐시 히트 시 API 호출 없이 캐시 반환', () async {
      final api = _FakeApiService((_) async => _order(orderNo: 'api'));
      final b = _build(api: api, store: _store());
      final cached = _order(orderNo: 'order-1');
      b.cache.put('order-1', cached);

      final result = await b.manager.fetchOrderDetail('order-1');
      expect(result, equals(cached));
      expect(api.callCount, 0);
    });

    test('매장 정보가 AsyncData(null) 이면 null 반환, API 미호출', () async {
      final api = _FakeApiService((_) async => _order());
      final b = _build(api: api, store: null);
      await b.container.read(storeProvider.future); // AsyncData(null) 로 settle

      final result = await b.manager.fetchOrderDetail('order-1');
      expect(result, isNull);
      expect(api.callCount, 0);
      // 로딩 플래그도 해제되어 재시도 가능해야 함
      expect(b.manager.isOrderDetailLoading('order-1'), isFalse);
    });

    test('storeProvider 가 아직 로딩 중(hasValue=false)이어도 null 반환', () async {
      final api = _FakeApiService((_) async => _order());
      final b = _build(api: api, store: _store());
      // storeProvider.future 를 기다리지 않고 즉시 호출 → AsyncLoading 상태
      final result = await b.manager.fetchOrderDetail('order-1');
      expect(result, isNull);
      expect(api.callCount, 0);
    });

    test('캐시 미스 + 매장 정보 존재 → API 1회 호출 후 캐시에 저장', () async {
      final apiOrder = _order(orderNo: 'order-1');
      final api = _FakeApiService((_) async => apiOrder);
      final b = _build(api: api, store: _store(storeId: 'store-9'));
      await b.container.read(storeProvider.future);

      final result = await b.manager.fetchOrderDetail('order-1');
      expect(result, equals(apiOrder));
      expect(api.callCount, 1);
      expect(b.manager.hasDetailCache('order-1'), isTrue);

      // 두 번째 호출은 캐시 히트 → API 추가 호출 없음
      final second = await b.manager.fetchOrderDetail('order-1');
      expect(second, equals(apiOrder));
      expect(api.callCount, 1);
    });

    test('API 예외 시 throw 하지 않고 null 반환 (현재 동작 고정) + 로딩 플래그 해제', () async {
      final api = _FakeApiService((_) async => throw Exception('서버 오류'));
      final b = _build(api: api, store: _store());
      await b.container.read(storeProvider.future);

      final result = await b.manager.fetchOrderDetail('order-1');
      expect(result, isNull);
      expect(b.manager.hasDetailCache('order-1'), isFalse);
      expect(b.manager.isOrderDetailLoading('order-1'), isFalse);
    });

    test('로딩 중 동일 orderId 재진입 → 즉시 null 반환 (중복 API 호출 방지)', () async {
      final gate = Completer<OrderModel>();
      final api = _FakeApiService((_) => gate.future);
      final b = _build(api: api, store: _store());
      await b.container.read(storeProvider.future);

      final first = b.manager.fetchOrderDetail('order-1'); // 미완료 상태로 보류
      // API 진입까지 마이크로태스크 양보
      await Future<void>.delayed(Duration.zero);
      expect(b.manager.isOrderDetailLoading('order-1'), isTrue);

      final second = await b.manager.fetchOrderDetail('order-1');
      expect(second, isNull); // 현재 동작: 결과 공유가 아니라 null 반환
      expect(api.callCount, 1);

      gate.complete(_order(orderNo: 'order-1'));
      final firstResult = await first;
      expect(firstResult!.orderNo, 'order-1');
      expect(b.manager.isOrderDetailLoading('order-1'), isFalse);
    });
  });

  group('getOrderDetail — 캐시/상태 목록 merge 규칙', () {
    test('캐시 히트 + 상태 목록의 updateTime 이 더 최신이면 status 만 merge 해 반환', () async {
      final b = _build(api: _FakeApiService((_) async => _order()));
      final cached = _order(
        orderNo: 'order-1',
        status: OrderStatus.PREPARING,
        updateTime: DateTime.utc(2026, 1, 1, 9),
      );
      b.cache.put('order-1', cached);
      final newer = _order(
        orderNo: 'order-1',
        status: OrderStatus.READY,
        updateTime: DateTime.utc(2026, 1, 1, 10),
      );

      final result =
          await b.manager.getOrderDetail('order-1', 'store-1', [newer]);
      expect(result.status, OrderStatus.READY);
      expect(result.orderStatus, OrderStatus.READY.name);
      expect(result.updateTime, DateTime.utc(2026, 1, 1, 10));
      // 캐시 자체는 갱신되지 않는 현재 동작
      expect(b.manager.getCachedOrderDetail('order-1')!.status,
          OrderStatus.PREPARING);
    });

    test('캐시 히트 + 상태 목록 updateTime 이 같거나 과거면 캐시 그대로 반환 (isAfter 엄격 비교)',
        () async {
      final b = _build(api: _FakeApiService((_) async => _order()));
      final cached = _order(
        orderNo: 'order-1',
        status: OrderStatus.PREPARING,
        updateTime: DateTime.utc(2026, 1, 1, 10),
      );
      b.cache.put('order-1', cached);
      final sameTime = _order(
        orderNo: 'order-1',
        status: OrderStatus.READY,
        updateTime: DateTime.utc(2026, 1, 1, 10), // 동일 시각 → merge 안 함
      );

      final result =
          await b.manager.getOrderDetail('order-1', 'store-1', [sameTime]);
      expect(result, equals(cached));
      expect(result.status, OrderStatus.PREPARING);
    });

    test('캐시 미스 → API 호출 + 캐시 저장 후 반환', () async {
      final apiOrder = _order(orderNo: 'order-1');
      final api = _FakeApiService((_) async => apiOrder);
      final b = _build(api: api);

      final result =
          await b.manager.getOrderDetail('order-1', 'store-1', const []);
      expect(result, equals(apiOrder));
      expect(api.callCount, 1);
      expect(api.requestedOrderIds, ['order-1']);
      expect(b.manager.hasDetailCache('order-1'), isTrue);
    });

    test('캐시 미스 + 상태 목록이 더 최신이면 merge 된 값을 반환하되 캐시에는 API 원본 저장', () async {
      final apiOrder = _order(
        orderNo: 'order-1',
        status: OrderStatus.PREPARING,
        updateTime: DateTime.utc(2026, 1, 1, 9),
      );
      final api = _FakeApiService((_) async => apiOrder);
      final b = _build(api: api);
      final newer = _order(
        orderNo: 'order-1',
        status: OrderStatus.DONE,
        updateTime: DateTime.utc(2026, 1, 1, 11),
      );

      final result =
          await b.manager.getOrderDetail('order-1', 'store-1', [newer]);
      expect(result.status, OrderStatus.DONE);
      expect(result.updateTime, DateTime.utc(2026, 1, 1, 11));
      // 현재 동작 고정: 캐시에는 merge 전 API 원본이 저장됨
      expect(b.manager.getCachedOrderDetail('order-1')!.status,
          OrderStatus.PREPARING);
    });

    test('API 실패 시 rethrow (fetchOrderDetail 과 달리 null 삼킴 없음)', () async {
      final api = _FakeApiService((_) async => throw StateError('서버 오류'));
      final b = _build(api: api);

      await expectLater(
        b.manager.getOrderDetail('order-1', 'store-1', const []),
        throwsA(isA<StateError>()),
      );
      expect(b.manager.hasDetailCache('order-1'), isFalse);
    });
  });
}
