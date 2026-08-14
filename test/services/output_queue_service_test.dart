import 'dart:async';

import 'package:appfit_order_agent/core/orders/output_service.dart';
import 'package:appfit_order_agent/models/order_menu_model.dart';
import 'package:appfit_order_agent/models/order_model.dart';
import 'package:appfit_order_agent/services/label_printer/fast_menu_policy.dart';
import 'package:appfit_order_agent/services/label_printer/label_target.dart';
import 'package:appfit_order_agent/services/output_queue_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// OutputService 를 가로채 호출 순서/횟수를 기록하는 fake.
///
/// OutputQueueService 는 ref.read(outputAppServiceProvider) 로만 출력에 접근하므로,
/// 이 provider 를 override 하면 실제 프린터 없이 enqueue 순서/멱등성을 검증할 수 있다.
/// notifyNewOrder/printOrderLabels 외 멤버는 테스트에서 호출되지 않으므로 noSuchMethod.
class _FakeOutputService implements OutputService {
  _FakeOutputService(this.events);

  /// 시간순 호출 이벤트 로그. 예: 'label:ORD1', 'receipt-start:ORD1', 'receipt-end:ORD1'
  final List<String> events;

  /// 설정하면 영수증 처리가 이 게이트가 열릴 때까지 멈춘다.
  /// 외부 영수증 프린터 오프라인(최대 137s backoff)을 실제 타이머 없이 모사한다.
  Completer<void>? receiptGate;

  @override
  Future<void> notifyNewOrder(
    OrderModel order, {
    required bool playSound,
    bool printLabel = true,
    bool forceOrderReceipt = false,
  }) async {
    events.add('receipt-start:${order.orderId}');
    final gate = receiptGate;
    if (gate != null) {
      await gate.future;
    } else {
      // microtask 경계만 두어(실제 타이머 없이) pumpEventQueue 로 소진 가능하게 한다.
      await Future<void>.microtask(() {});
    }
    events.add('receipt-end:${order.orderId}');
  }

  // 라벨 큐는 2단계다 — 준비(상세조회·타깃 분할) 뒤에 타깃별 인쇄 큐로 간다.
  // 기본은 타깃 하나라 종전과 같은 단일 큐 동작이 재현된다.

  /// 이 주문이 쓸 타깃. 테스트가 갈아끼워 분할 동작을 만든다.
  Set<LabelTarget> targets = {LabelTarget.primary};

  /// 타깃 id → 열릴 때까지 인쇄를 막는 게이트. 프린터 보류를 모사한다.
  final Map<String, Completer<void>> targetGates = {};

  /// `주문:타깃` 형식 인쇄 기록. [events] 는 기존 단언이 쓰므로 형식을 바꾸지 않고
  /// 타깃 정보는 여기에 따로 남긴다.
  final List<String> targetEvents = [];

  void block(LabelTarget target) => targetGates[target.id] = Completer<void>();

  void release(LabelTarget target) => targetGates.remove(target.id)?.complete();

  @override
  Future<OrderModel?> prepareOrderForLabels(OrderModel order) async => order;

  @override
  Future<Set<LabelTarget>> targetsForOrder(OrderModel order,
          {bool isReprint = false}) async =>
      targets;

  @override
  Future<void> printOrderLabels(OrderModel order,
      {bool isReprint = false, LabelTarget? onlyTarget}) async {
    events.add('label:${order.orderId}${isReprint ? ':reprint' : ''}');
    targetEvents.add('${order.orderId}:${onlyTarget?.id ?? '-'}');
    final gate = targetGates[onlyTarget?.id];
    if (gate != null) await gate.future;
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

OrderModel _order(String orderId, {List<OrderMenuModel> menus = const []}) {
  return OrderModel(
    orderNo: orderId,
    shopOrderNo: '0001',
    orderStatus: OrderStatus.PREPARING.name,
    orderedAt: DateTime.utc(2026, 1, 1, 9, 0),
    totalAmount: 9000,
    status: OrderStatus.PREPARING,
    storeId: 'store-1',
    userId: 'user-1',
    ordererName: '홍길동',
    orderCount: '2',
    paymentAmount: 9000,
    discountAmount: 0,
    paymentType: 'CARD',
    paymentCode: 'CARD',
    menus: menus,
    orderType: 'T',
    kdsOrderType: 1,
    kioskId: 'kiosk-1',
    updateTime: DateTime.utc(2026, 1, 1, 9, 0),
  );
}

/// 지정된 상품 [fastIds] 를 빠른 메뉴로 보는 정책 (모드 2 = 주문 간 추월 허용).
FastMenuPolicy _priorityPolicy(Set<String> fastIds) => FastMenuPolicy(
      mode: FastMenuMode.acrossOrders,
      showMarker: false,
      fastIds: fastIds,
    );

void main() {
  late List<String> events;
  late _FakeOutputService fake;
  late ProviderContainer container;
  late OutputQueueService service;

  /// [policy] 를 주입한 컨테이너/서비스로 갈아끼운다.
  /// 기본은 [FastMenuPolicy.disabled] — 우선순위 기능이 꺼진 종전 동작.
  void buildWith(FastMenuPolicy policy) {
    container.dispose();
    container = ProviderContainer(overrides: [
      outputAppServiceProvider.overrideWithValue(fake),
      fastMenuPolicyProvider.overrideWithValue(policy),
    ]);
    service = container.read(outputQueueServiceProvider);
  }

  setUp(() {
    events = <String>[];
    fake = _FakeOutputService(events);
    container = ProviderContainer(overrides: [
      outputAppServiceProvider.overrideWithValue(fake),
      // 실제 정책은 PreferenceService(SharedPreferences)를 읽으므로 테스트에서는
      // 명시 주입한다. 기본은 '꺼짐' — 아래 대부분의 테스트가 고정하는 종전 동작.
      fastMenuPolicyProvider.overrideWithValue(FastMenuPolicy.disabled),
    ]);
    // outputQueueServiceProvider 가 내부에서 Ref 를 주입해 OutputQueueService 를
    // 생성한다. 이 서비스가 ref.read(outputAppServiceProvider) 로 fake 를 집어든다.
    service = container.read(outputQueueServiceProvider);
  });

  tearDown(() => container.dispose());

  group('OutputQueueService — I5 라벨 enqueue 가 영수증 await 보다 먼저', () {
    test('NewOrderJob: 영수증이 끝나지 않아도 라벨은 나간다', () async {
      // 영수증을 열리지 않는 게이트로 막는다 = 외부 프린터 오프라인(backoff) 상황.
      //
      // ★ "라벨 이벤트가 영수증 이벤트보다 먼저 기록되는가" 로 검사하지 말 것.
      //   그건 두 경로의 microtask 홉 수를 비교하는 것이라, 라벨 쪽에 준비 단계가
      //   한 겹 붙기만 해도 불변식이 멀쩡한데 깨진다(실제로 2단계 파이프라인
      //   도입 때 그렇게 깨졌다). 불변식은 "영수증 완료를 기다리지 않는다" 이므로
      //   영수증을 영원히 막아 두고 라벨이 나오는지를 본다.
      final gate = Completer<void>();
      fake.receiptGate = gate;

      service.add(_order('ORD1'));
      await pumpEventQueue(times: 200);

      expect(events, contains('receipt-start:ORD1'));
      expect(events, isNot(contains('receipt-end:ORD1')),
          reason: '게이트를 안 열었으므로 영수증은 아직 진행 중이어야 한다');
      expect(events, contains('label:ORD1'),
          reason: '라벨이 영수증 await 에 묶이면 영수증 오프라인 시 137s 동안 라벨이 안 나온다');

      gate.complete();
      await pumpEventQueue(times: 200);
      expect(events, contains('receipt-end:ORD1'));
    });

    test('printLabel: false 면 라벨을 enqueue 하지 않는다 (KDS READY 등)', () async {
      service.add(_order('ORD2'), printLabel: false);
      await pumpEventQueue(times: 200);

      expect(events.where((e) => e.startsWith('label:')), isEmpty);
      expect(events, contains('receipt-end:ORD2'));
    });
  });

  group('OutputQueueService — I4 출력 멱등성 (이중 트리거 차단)', () {
    test('동일 orderId add() 2회 → 영수증·라벨 각 1회만', () async {
      // WebSocket + 폴링이 같은 주문을 동시에 트리거하는 상황.
      service.add(_order('ORD3'));
      service.add(_order('ORD3'));
      await pumpEventQueue(times: 200);

      expect(events.where((e) => e == 'receipt-start:ORD3').length, 1);
      expect(events.where((e) => e == 'label:ORD3').length, 1);
    });

    test('addLabelOnly 동일 orderId 2회 → 라벨 1회만', () async {
      service.addLabelOnly(_order('ORD4'));
      service.addLabelOnly(_order('ORD4'));
      await pumpEventQueue(times: 200);

      expect(events.where((e) => e == 'label:ORD4').length, 1);
    });

    test('addReprint 동일 orderId 2회 → 재출력 라벨 1회만', () async {
      service.addReprint(_order('ORD5'));
      service.addReprint(_order('ORD5'));
      await pumpEventQueue(times: 200);

      expect(events.where((e) => e == 'label:ORD5:reprint').length, 1);
    });

    test('영수증 완료 후 같은 orderId 재 add() 는 다시 출력된다 (in-flight 해제 확인)', () async {
      service.add(_order('ORD6'));
      await pumpEventQueue(times: 200);
      expect(events.where((e) => e == 'receipt-start:ORD6').length, 1);

      // 첫 출력이 끝나 in-flight 에서 빠진 뒤의 재요청은 정상 출력되어야 한다.
      service.add(_order('ORD6'));
      await pumpEventQueue(times: 200);
      expect(events.where((e) => e == 'receipt-start:ORD6').length, 2);
    });
  });

  group('OutputQueueService — 빠른 메뉴 우선 출력', () {
    /// 라벨 큐가 선두 작업을 처리하는 동안 후속 3건을 한 번에 투입한다.
    /// 첫 건은 즉시 꺼내져 처리 중이므로 추월 대상이 아니다 — 이게 "이미
    /// 프린터로 나간 라벨은 추월 불가" 라는 실제 제약과 같은 구조다.
    List<String> labelEvents() =>
        events.where((e) => e.startsWith('label:')).toList();

    test('전량 빠른 메뉴 주문이 대기 중인 일반 주문을 추월한다', () async {
      buildWith(_priorityPolicy({'AMERICANO'}));

      service.addLabelOnly(_order('SLOW1', menus: [_menu('WAFFLE')]));
      service.addLabelOnly(_order('SLOW2', menus: [_menu('WAFFLE')]));
      service.addLabelOnly(_order('FAST1', menus: [_menu('AMERICANO')]));
      await pumpEventQueue(times: 200);

      // SLOW1 은 이미 처리에 들어가 추월 불가. FAST1 이 SLOW2 를 앞질러야 한다.
      expect(labelEvents(), ['label:SLOW1', 'label:FAST1', 'label:SLOW2']);
    });

    test('혼합 주문(빠른 + 느린 메뉴)은 추월하지 않는다', () async {
      buildWith(_priorityPolicy({'AMERICANO'}));

      service.addLabelOnly(_order('SLOW1', menus: [_menu('WAFFLE')]));
      service.addLabelOnly(_order('SLOW2', menus: [_menu('WAFFLE')]));
      service.addLabelOnly(
          _order('MIXED', menus: [_menu('AMERICANO'), _menu('WAFFLE')]));
      await pumpEventQueue(times: 200);

      expect(labelEvents(), ['label:SLOW1', 'label:SLOW2', 'label:MIXED']);
    });

    test('굶주림 가드 — 같은 일반 주문이 maxSkips(3) 를 넘겨 밀리지 않는다', () async {
      buildWith(_priorityPolicy({'AMERICANO'}));

      service.addLabelOnly(_order('HEAD', menus: [_menu('WAFFLE')]));
      service.addLabelOnly(_order('SLOW', menus: [_menu('WAFFLE')]));
      for (var i = 1; i <= 4; i++) {
        service.addLabelOnly(_order('FAST$i', menus: [_menu('AMERICANO')]));
      }
      await pumpEventQueue(times: 400);

      // HEAD 는 처리 중이라 무관. SLOW 는 3회까지만 추월당하고 4번째 FAST 앞에 선다.
      expect(labelEvents(), [
        'label:HEAD',
        'label:FAST1',
        'label:FAST2',
        'label:FAST3',
        'label:SLOW',
        'label:FAST4',
      ]);
    });

    test('재출력은 우선순위와 무관하게 FIFO 를 지킨다', () async {
      buildWith(_priorityPolicy({'AMERICANO'}));

      service.addLabelOnly(_order('HEAD', menus: [_menu('WAFFLE')]));
      // 운영자가 방금 누른 재출력. 뒤에 온 빠른 주문에게 밀리면 안 된다.
      service.addReprint(_order('REPRINT', menus: [_menu('AMERICANO')]));
      service.addLabelOnly(_order('FAST1', menus: [_menu('AMERICANO')]));
      await pumpEventQueue(times: 200);

      expect(labelEvents(),
          ['label:HEAD', 'label:REPRINT:reprint', 'label:FAST1']);
    });

    test('기능이 꺼져 있으면(mode=0) 종전 FIFO 그대로', () async {
      // setUp 기본값이 FastMenuPolicy.disabled.
      service.addLabelOnly(_order('SLOW1', menus: [_menu('WAFFLE')]));
      service.addLabelOnly(_order('SLOW2', menus: [_menu('WAFFLE')]));
      service.addLabelOnly(_order('FAST1', menus: [_menu('AMERICANO')]));
      await pumpEventQueue(times: 200);

      expect(labelEvents(), ['label:SLOW1', 'label:SLOW2', 'label:FAST1']);
    });
  });

  group('OutputQueueService — 타깃별 큐 격리', () {
    /// 프린터가 여러 대일 때, 한 대에서 라벨을 안 떼면 펌웨어가 다음 장을 보류한다.
    /// 큐가 하나면 그 대기가 다른 프린터로 갈 라벨까지 막는다 — 구역을 나눈 의미가
    /// 사라진다. 이 그룹이 고정하는 것이 그 성질이다.
    test('한 타깃이 막혀도 다른 타깃은 계속 나간다', () async {
      fake.targets = {LabelTarget.primary, LabelTarget.zone2};
      fake.block(LabelTarget.primary);

      service.addLabelOnly(_order('A'));
      service.addLabelOnly(_order('B'));
      await pumpEventQueue(times: 200);

      // zone2 는 두 주문을 모두 끝냈어야 한다.
      expect(fake.targetEvents, containsAll(['A:zone2', 'B:zone2']));
      // primary 는 A 에서 막혀 있고 B 는 그 뒤에서 대기 — 큐가 직렬이므로 정상.
      expect(fake.targetEvents, contains('A:primary'));
      expect(fake.targetEvents, isNot(contains('B:primary')),
          reason: '막힌 타깃의 큐는 순서대로 대기해야 한다');

      fake.release(LabelTarget.primary);
      await pumpEventQueue(times: 200);
      expect(fake.targetEvents, contains('B:primary'));
    });

    test('타깃 하나가 아직 인쇄 중이면 같은 주문의 재투입은 무시된다', () async {
      // 중복 방지를 타깃 작업 하나가 끝날 때마다 풀면, 아직 다른 타깃이 인쇄 중인
      // 주문이 다시 큐에 들어온다 — 그게 곧 중복 인쇄다.
      fake.targets = {LabelTarget.primary, LabelTarget.zone2};
      fake.block(LabelTarget.primary);

      service.addLabelOnly(_order('X'));
      await pumpEventQueue(times: 200);
      expect(fake.targetEvents.where((e) => e == 'X:zone2').length, 1);

      // zone2 는 이미 끝났지만 primary 가 진행 중 → 재투입은 먹히면 안 된다.
      service.addLabelOnly(_order('X'));
      await pumpEventQueue(times: 200);
      expect(fake.targetEvents.where((e) => e == 'X:zone2').length, 1,
          reason: '다른 타깃이 인쇄 중인데 중복 방지가 풀리면 라벨이 두 번 나온다');

      fake.release(LabelTarget.primary);
      await pumpEventQueue(times: 200);

      // 모든 타깃이 끝났으니 이제는 재투입이 정상 동작해야 한다.
      service.addLabelOnly(_order('X'));
      await pumpEventQueue(times: 200);
      expect(fake.targetEvents.where((e) => e == 'X:zone2').length, 2,
          reason: '전부 끝났는데도 안 풀리면 그 주문은 영영 재출력할 수 없다');
    });

    test('타깃이 하나면 큐도 하나 — 종전과 동일 동작', () async {
      service.addLabelOnly(_order('SOLO'));
      await pumpEventQueue(times: 200);
      expect(fake.targetEvents, ['SOLO:primary']);
    });
  });
}
