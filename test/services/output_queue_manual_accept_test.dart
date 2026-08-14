import 'dart:async';

import 'package:appfit_order_agent/core/orders/output_service.dart';
import 'package:appfit_order_agent/models/order_menu_model.dart';
import 'package:appfit_order_agent/models/order_model.dart';
import 'package:appfit_order_agent/services/label_printer/fast_menu_policy.dart';
import 'package:appfit_order_agent/services/label_printer/label_target.dart';
import 'package:appfit_order_agent/services/output_queue_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 수동 접수(주문 상세 [주문 접수] 버튼) 경로 = `OutputQueueService.add()`.
///
/// 기존 우선순위 테스트는 전부 `addLabelOnly()`(라벨 큐 직행)를 썼는데, 수동 접수는
/// **영수증 큐를 한 번 거쳐** `_NewOrderLabelTail` 이 enqueue 된다. 즉 라벨 tail 은
/// 영수증 큐가 드레인되는 속도에 맞춰 **하나씩** 들어온다 — 여러 건이 동시에
/// 대기열에 있다고 가정한 기존 테스트와 타이밍이 다르다.
///
/// 실기기 조건을 모사한다: 라벨은 느리다(떼기 대기로 막힘), 영수증은 빠르다.
class _SlowLabelFake implements OutputService {
  _SlowLabelFake(this.events);

  final List<String> events;

  /// 라벨 1장이 걸려 있는 게이트. 완료시켜야 다음 라벨로 넘어간다.
  Completer<void>? _gate;

  /// 현재 처리 중인 라벨을 끝낸다 (= 사용자가 라벨을 뗌).
  void releaseOne() {
    final g = _gate;
    _gate = null;
    if (g != null && !g.isCompleted) g.complete();
  }

  @override
  Future<void> notifyNewOrder(
    OrderModel order, {
    required bool playSound,
    bool printLabel = true,
    bool forceOrderReceipt = false,
  }) async {
    // 영수증은 빠르게 끝난다 — 라벨 tail 들이 곧바로 라벨 큐에 쌓이도록.
    await Future<void>.microtask(() {});
  }

  @override
  // 라벨 큐 2단계 중 준비 단계는 통과만 시킨다 — 이 테스트가 보는 것은 인쇄가
  // 막혀 있을 때의 큐 거동이라, 타깃 하나로 종전과 같은 단일 큐를 재현한다.
  @override
  Future<OrderModel?> prepareOrderForLabels(OrderModel order) async => order;

  @override
  Future<Set<LabelTarget>> targetsForOrder(OrderModel order,
          {bool isReprint = false}) async =>
      {LabelTarget.primary};

  @override
  Future<void> printOrderLabels(OrderModel order,
      {bool isReprint = false, LabelTarget? onlyTarget}) async {
    events.add('label:${order.orderId}${isReprint ? ':reprint' : ''}');
    final gate = Completer<void>();
    _gate = gate;
    await gate.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

OrderMenuModel _menu(String shopItemId) => OrderMenuModel(
      orderNo: 'ord',
      shopItemId: shopItemId,
      qty: 1,
      itemName: shopItemId,
      itemPrice: 1000,
      totalAmount: 1000,
      discPrc: 0,
      vatPrc: 0,
      options: const [],
    );

OrderModel _order(String orderId, {required List<OrderMenuModel> menus}) =>
    OrderModel(
      orderNo: orderId,
      shopOrderNo: '0001',
      orderStatus: OrderStatus.PREPARING.name,
      orderedAt: DateTime.utc(2026, 1, 1, 9),
      totalAmount: 1000,
      status: OrderStatus.PREPARING,
      storeId: 'store-1',
      userId: 'user-1',
      ordererName: '홍길동',
      orderCount: '1',
      paymentAmount: 1000,
      discountAmount: 0,
      paymentType: 'CARD',
      paymentCode: 'CARD',
      menus: menus,
      orderType: 'T',
      kdsOrderType: 1,
      kioskId: 'kiosk-1',
      updateTime: DateTime.utc(2026, 1, 1, 9),
    );

OrderModel _fast(String id) => _order(id, menus: [_menu('AMERICANO')]);
OrderModel _slow(String id) => _order(id, menus: [_menu('WAFFLE')]);

void main() {
  late List<String> events;
  late _SlowLabelFake fake;
  late ProviderContainer container;
  late OutputQueueService service;

  setUp(() {
    events = <String>[];
    fake = _SlowLabelFake(events);
    container = ProviderContainer(overrides: [
      outputAppServiceProvider.overrideWithValue(fake),
      fastMenuPolicyProvider.overrideWithValue(const FastMenuPolicy(
        mode: FastMenuMode.acrossOrders,
        showMarker: false,
        fastIds: {'AMERICANO', '저렴이'},
      )),
    ]);
    service = container.read(outputQueueServiceProvider);
  });

  tearDown(() => container.dispose());

  /// 접수 1건 + 큐가 안정될 때까지 대기 (tail 이 라벨 큐에 도달하도록).
  Future<void> accept(OrderModel order) async {
    service.add(order, playSound: false);
    await pumpEventQueue(times: 50);
  }

  /// 라벨 [n] 장을 순서대로 뗀다.
  Future<void> tear(int n) async {
    for (var i = 0; i < n; i++) {
      fake.releaseOne();
      await pumpEventQueue(times: 50);
    }
  }

  test('시나리오 B — 굶주림 가드: 느린 주문이 3회까지만 추월당한다', () async {
    await accept(_slow('WAFFLE_A')); // 선두 — 즉시 dispatch 되어 떼기 대기
    await accept(_slow('WAFFLE_B')); // 대기열
    for (var i = 1; i <= 4; i++) {
      await accept(_fast('AME$i'));
    }

    await tear(6);

    expect(events, [
      'label:WAFFLE_A',
      'label:AME1',
      'label:AME2',
      'label:AME3',
      'label:WAFFLE_B',
      'label:AME4',
    ]);
  });

  test('시나리오 C — 재출력 면역: 재출력 뒤 빠른 주문도 반드시 나온다', () async {
    await accept(_slow('WAFFLE_A')); // 떼기 대기 중

    service.addReprint(_slow('REPRINT_X'));
    await pumpEventQueue(times: 50);

    await accept(_fast('AME1'));

    await tear(3);

    expect(events, [
      'label:WAFFLE_A',
      'label:REPRINT_X:reprint',
      'label:AME1',
    ]);
  });

  test('느린 주문이 빠른 주문보다 늦게 큐에 들어오면 그 앞의 빠른 주문은 추월로 세지 않는다', () async {
    // 현장에서 "3회 한도가 안 먹고 4개가 연속 나왔다" 로 보고된 상황의 정체.
    //
    // 추월 횟수는 **대기열에 들어온 시점부터** 센다. 자기보다 먼저 큐에 있던
    // 빠른 주문은 추월이 아니라 그냥 FIFO 선착순이다. 따라서 느린 주문이
    // 빠른 주문 1건 뒤에 도착하면, 그 1건 + 한도 3건 = 빠른 주문 4건이
    // 연속으로 나온 뒤에야 느린 주문 차례가 온다. 가드는 정상 동작한 것이다.
    await accept(_slow('WAFFLE_A')); // 선두 — 떼기 대기
    await accept(_fast('AME1')); // 와플B 보다 먼저 큐에 진입
    await accept(_slow('WAFFLE_B'));
    for (var i = 2; i <= 4; i++) {
      await accept(_fast('AME$i'));
    }

    await tear(6);

    expect(events, [
      'label:WAFFLE_A',
      'label:AME1', // 추월 아님 — WAFFLE_B 보다 먼저 와 있었음
      'label:AME2', // 추월 1
      'label:AME3', // 추월 2
      'label:AME4', // 추월 3 → 한도 도달
      'label:WAFFLE_B',
    ]);
  });

  test('혼합 주문이 섞여 밀려들어올 때 — 전량 빠른 주문만 추월한다', () async {
    // 현장 질문: 대부분의 주문에 저렴이가 섞여 있으면 어떻게 되나?
    // 답: `isFastOrder` 는 `menus.every(isFast)` 라 **한 개라도 다른 메뉴가
    // 섞이면 추월 대상이 아니다**. 저렴이가 4개 들었어도 마찬가지.
    await accept(_order('주문1', menus: [_menu('저렴이'), _menu('히비')]));
    await accept(_order('주문2', menus: [_menu('저렴이'), _menu('마카롱')]));
    await accept(_order('주문3', menus: [_menu('저렴이'), _menu('초코라떼')]));
    await accept(_order('주문4', menus: [_menu('저렴이')])); // 전량 빠름
    await accept(_order('주문5', menus: [_menu('말차라떼')]));

    await tear(5);

    // 주문1 은 이미 처리 중이라 추월 불가. 주문4 만 주문2·3 을 앞지른다.
    // 주문5 는 주문4 가 이미 들어온 뒤라 그 뒤에 붙는다.
    expect(events, [
      'label:주문1',
      'label:주문4',
      'label:주문2',
      'label:주문3',
      'label:주문5',
    ]);
  });

  test('시나리오 A — 추월: 빠른 주문이 대기 중인 느린 주문을 앞선다', () async {
    await accept(_slow('WAFFLE_A'));
    await accept(_slow('WAFFLE_B'));
    await accept(_fast('AME1'));

    await tear(3);

    expect(events, [
      'label:WAFFLE_A',
      'label:AME1',
      'label:WAFFLE_B',
    ]);
  });
}
