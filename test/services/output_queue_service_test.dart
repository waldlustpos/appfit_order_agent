import 'package:appfit_order_agent/core/orders/output_service.dart';
import 'package:appfit_order_agent/models/order_menu_model.dart';
import 'package:appfit_order_agent/models/order_model.dart';
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

  @override
  Future<void> notifyNewOrder(
    OrderModel order, {
    required bool playSound,
    bool printLabel = true,
    bool forceOrderReceipt = false,
  }) async {
    events.add('receipt-start:${order.orderId}');
    // microtask 경계만 두어(실제 타이머 없이) pumpEventQueue 로 소진 가능하게 한다.
    await Future<void>.microtask(() {});
    events.add('receipt-end:${order.orderId}');
  }

  @override
  Future<void> printOrderLabels(OrderModel order, {bool isReprint = false}) async {
    events.add('label:${order.orderId}${isReprint ? ':reprint' : ''}');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

OrderModel _order(String orderId) {
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
    menus: const <OrderMenuModel>[],
    orderType: 'T',
    kdsOrderType: 1,
    kioskId: 'kiosk-1',
    updateTime: DateTime.utc(2026, 1, 1, 9, 0),
  );
}

void main() {
  late List<String> events;
  late _FakeOutputService fake;
  late ProviderContainer container;
  late OutputQueueService service;

  setUp(() {
    events = <String>[];
    fake = _FakeOutputService(events);
    container = ProviderContainer(overrides: [
      outputAppServiceProvider.overrideWithValue(fake),
    ]);
    // outputQueueServiceProvider 가 내부에서 Ref 를 주입해 OutputQueueService 를
    // 생성한다. 이 서비스가 ref.read(outputAppServiceProvider) 로 fake 를 집어든다.
    service = container.read(outputQueueServiceProvider);
  });

  tearDown(() => container.dispose());

  group('OutputQueueService — I5 라벨 enqueue 가 영수증 await 보다 먼저', () {
    test('NewOrderJob: 라벨이 영수증 완료 이전에 enqueue·실행된다', () async {
      service.add(_order('ORD1'));

      // 영수증 worker 가 receipt-start 후 30ms 대기하는 동안, 라벨 큐는
      // 독립 worker 라 label 을 먼저 실행해야 한다 (137s backoff 격리의 핵심).
      await pumpEventQueue(times: 200);

      expect(events, contains('label:ORD1'));
      expect(events, contains('receipt-end:ORD1'));

      final labelIdx = events.indexOf('label:ORD1');
      final receiptEndIdx = events.indexOf('receipt-end:ORD1');
      // 라벨이 영수증 await(완료) 보다 먼저 기록되어야 함 = 두 큐가 진짜 병렬.
      expect(labelIdx, lessThan(receiptEndIdx),
          reason: '라벨이 영수증 await 에 묶이면 영수증 오프라인 시 137s 동안 라벨이 안 나온다');
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
}
