// fake_async 는 flutter_test 의 전이 의존성(pubspec.lock 에 이미 고정)이며,
// 새 직접 의존성 추가 없이 타이머 검증에 사용한다.
// ignore_for_file: depend_on_referenced_packages
import 'package:appfit_order_agent/models/order_menu_model.dart';
import 'package:appfit_order_agent/models/order_model.dart';
import 'package:appfit_order_agent/providers/order/order_queue_manager.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// OrderQueueManager characterization 테스트.
///
/// Buffer(1s) -> Sort(shopOrderNo) -> Emit(0.5s/0.25s throttle) 파이프라인과
/// 상태 업데이트 200ms 배치 윈도우의 "현재 동작"을 고정한다.
/// 시간 의존 로직은 fakeAsync 로 검증한다.
OrderModel _order({
  String orderNo = 'order-1',
  String shopOrderNo = '0001',
  OrderStatus status = OrderStatus.NEW,
}) {
  return OrderModel(
    orderNo: orderNo,
    shopOrderNo: shopOrderNo,
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
    updateTime: DateTime.utc(2026, 1, 1, 9),
  );
}

/// Ref 는 필드로만 보관되고 내부에서 사용되지 않으므로 빈 컨테이너의 Ref 를 주입한다.
OrderQueueManager _manager({
  required Future<void> Function(OrderModel) onSingle,
  Future<void> Function(List<OrderModel>)? onBatch,
}) {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  final provider = Provider<OrderQueueManager>(
    (ref) => OrderQueueManager(
      ref,
      onProcessSingleOrder: onSingle,
      onProcessBatchOrders: onBatch,
    ),
  );
  return container.read(provider);
}

void main() {
  group('compareByShopOrderNo — 정렬 비교자 (현재 동작 고정)', () {
    test('숫자 shopOrderNo 는 수치 오름차순 (사전식 아님: "2" < "0010")', () {
      final a = _order(orderNo: 'a', shopOrderNo: '2');
      final b = _order(orderNo: 'b', shopOrderNo: '0010');
      // 사전식이면 '0010' < '2' 이지만, 현재는 int.parse 수치 비교.
      expect(OrderQueueManager.compareByShopOrderNo(a, b), lessThan(0));
      expect(OrderQueueManager.compareByShopOrderNo(b, a), greaterThan(0));
    });

    test('동일 숫자값(패딩만 다름)은 0 (동순위)', () {
      final a = _order(orderNo: 'a', shopOrderNo: '0007');
      final b = _order(orderNo: 'b', shopOrderNo: '7');
      expect(OrderQueueManager.compareByShopOrderNo(a, b), 0);
    });

    test('양쪽 다 비숫자이면 orderId 사전식 fallback', () {
      final a = _order(orderNo: 'AAA', shopOrderNo: 'X-1');
      final b = _order(orderNo: 'BBB', shopOrderNo: 'W-2');
      // shopOrderNo 기준이면 W-2 < X-1 이지만, parse 실패 → orderId 비교.
      expect(OrderQueueManager.compareByShopOrderNo(a, b), lessThan(0));
    });

    test('현재 동작 고정(버그 의심): 한쪽만 비숫자여도 해당 쌍 전체가 orderId fallback', () {
      // a.shopOrderNo 는 숫자지만 b 가 비숫자면 int.parse(b) 에서 throw →
      // 쌍 전체가 orderId 비교로 떨어진다. 숫자/비숫자 혼재 리스트에서는
      // 비교자가 비추이적(non-transitive)이 될 수 있는 현재 동작.
      final numeric = _order(orderNo: 'ZZZ', shopOrderNo: '1');
      final alpha = _order(orderNo: 'AAA', shopOrderNo: 'NOPE');
      expect(OrderQueueManager.compareByShopOrderNo(numeric, alpha),
          greaterThan(0)); // 'ZZZ' > 'AAA'
    });

    test('sortByShopOrderNo 는 리스트를 in-place 로 낮은 주문번호 순 정렬', () {
      final orders = [
        _order(orderNo: 'c', shopOrderNo: '0003'),
        _order(orderNo: 'a', shopOrderNo: '0001'),
        _order(orderNo: 'b', shopOrderNo: '0002'),
      ];
      OrderQueueManager.sortByShopOrderNo(orders);
      expect(
          orders.map((o) => o.shopOrderNo).toList(), ['0001', '0002', '0003']);
    });
  });

  group('NEW 주문 버퍼링(1s) → 정렬 방출(0.5s 간격)', () {
    test('버퍼 윈도우(1000ms) 경과 전에는 방출되지 않음', () {
      fakeAsync((async) {
        final processed = <String>[];
        final m = _manager(onSingle: (o) async => processed.add(o.orderNo));
        m.queueOrder(_order(orderNo: 'a'));
        async.elapse(const Duration(milliseconds: 999));
        expect(processed, isEmpty);
        expect(m.hasPending, isTrue);
        m.dispose();
      });
    });

    test('1000ms 경과 시 첫 주문 즉시 방출', () {
      fakeAsync((async) {
        final processed = <String>[];
        final m = _manager(onSingle: (o) async => processed.add(o.orderNo));
        m.queueOrder(_order(orderNo: 'a'));
        async.elapse(const Duration(milliseconds: 1000));
        expect(processed, ['a']);
        expect(m.hasPending, isFalse);
        m.dispose();
      });
    });

    test('윈도우 내 3건 → shopOrderNo 오름차순으로 500ms 간격 방출', () {
      fakeAsync((async) {
        final processed = <String>[];
        final m = _manager(onSingle: (o) async => processed.add(o.shopOrderNo));
        m.queueOrder(_order(orderNo: 'c', shopOrderNo: '0003'));
        m.queueOrder(_order(orderNo: 'a', shopOrderNo: '0001'));
        m.queueOrder(_order(orderNo: 'b', shopOrderNo: '0002'));

        async.elapse(const Duration(milliseconds: 1000));
        expect(processed, ['0001']); // flush 직후 첫 건 즉시
        async.elapse(const Duration(milliseconds: 500));
        expect(processed, ['0001', '0002']);
        async.elapse(const Duration(milliseconds: 500));
        expect(processed, ['0001', '0002', '0003']);
        m.dispose();
      });
    });

    test('동일 orderId NEW 중복 enqueue 는 무시', () {
      fakeAsync((async) {
        final processed = <String>[];
        final m = _manager(onSingle: (o) async => processed.add(o.orderNo));
        m.queueOrder(_order(orderNo: 'a'));
        m.queueOrder(_order(orderNo: 'a'));
        async.elapse(const Duration(seconds: 10));
        expect(processed, ['a']);
        m.dispose();
      });
    });

    test('대량(>20건) 인입 시 큐 잔량 20건 초과 동안 250ms 단축 간격', () {
      fakeAsync((async) {
        final processed = <String>[];
        final m = _manager(onSingle: (o) async => processed.add(o.orderNo));
        for (var i = 1; i <= 22; i++) {
          m.queueOrder(_order(
              orderNo: 'o$i', shopOrderNo: i.toString().padLeft(4, '0')));
        }
        async.elapse(const Duration(milliseconds: 1000));
        expect(processed.length, 1); // flush 직후 1건 (잔량 21 > 20 → 250ms 예약)
        async.elapse(const Duration(milliseconds: 250));
        expect(processed.length, 2); // 잔량 20 → 이후 500ms 간격으로 복귀
        async.elapse(const Duration(milliseconds: 250));
        expect(processed.length, 2);
        async.elapse(const Duration(milliseconds: 250));
        expect(processed.length, 3);
        // 전체 드레인 확인
        async.elapse(const Duration(seconds: 30));
        expect(processed.length, 22);
        m.dispose();
      });
    });

    test('onProcessSingleOrder 가 throw 해도 다음 방출은 계속 진행', () {
      fakeAsync((async) {
        final processed = <String>[];
        final m = _manager(onSingle: (o) async {
          if (o.orderNo == 'boom') throw StateError('처리 실패');
          processed.add(o.orderNo);
        });
        m.queueOrder(_order(orderNo: 'boom', shopOrderNo: '0001'));
        m.queueOrder(_order(orderNo: 'ok', shopOrderNo: '0002'));
        async.elapse(const Duration(seconds: 5));
        expect(processed, ['ok']);
        m.dispose();
      });
    });
  });

  group('상태 업데이트(non-NEW) 200ms 배치', () {
    test('배치 콜백 있으면 200ms 윈도우로 묶어 1회 호출 (단건 콜백 미호출)', () {
      fakeAsync((async) {
        final processed = <String>[];
        final batches = <List<String>>[];
        final m = _manager(
          onSingle: (o) async => processed.add(o.orderNo),
          onBatch: (list) async =>
              batches.add(list.map((o) => o.orderNo).toList()),
        );
        m.queueOrder(_order(orderNo: 'a', status: OrderStatus.DONE));
        m.queueOrder(_order(orderNo: 'b', status: OrderStatus.READY));
        m.queueOrder(_order(orderNo: 'c', status: OrderStatus.CANCELLED));

        async.elapse(const Duration(milliseconds: 199));
        expect(batches, isEmpty);
        async.elapse(const Duration(milliseconds: 1));
        expect(batches, [
          ['a', 'b', 'c'] // 정렬 없이 인입 순서 유지
        ]);
        expect(processed, isEmpty);
        m.dispose();
      });
    });

    test('윈도우 flush 후 새 상태 업데이트는 다음 배치로 분리', () {
      fakeAsync((async) {
        final batches = <List<String>>[];
        final m = _manager(
          onSingle: (_) async {},
          onBatch: (list) async =>
              batches.add(list.map((o) => o.orderNo).toList()),
        );
        m.queueOrder(_order(orderNo: 'a', status: OrderStatus.DONE));
        async.elapse(const Duration(milliseconds: 200));
        m.queueOrder(_order(orderNo: 'b', status: OrderStatus.DONE));
        async.elapse(const Duration(milliseconds: 200));
        expect(batches, [
          ['a'],
          ['b'],
        ]);
        m.dispose();
      });
    });

    test('배치 콜백 없으면(null) 즉시 단건 처리 (타이머 없음)', () {
      fakeAsync((async) {
        final processed = <String>[];
        final m = _manager(onSingle: (o) async => processed.add(o.orderNo));
        m.queueOrder(_order(orderNo: 'a', status: OrderStatus.DONE));
        // elapse 없이 동기 호출됨
        expect(processed, ['a']);
        m.dispose();
      });
    });
  });

  group('현재 동작 고정(버그 의심) — 크로스 스테이지 orderId 중복 차단', () {
    test('NEW 가 버퍼 대기 중이면 동일 주문의 상태 업데이트(DONE)가 중복으로 무시됨', () {
      fakeAsync((async) {
        final processed = <String>[];
        final batches = <List<String>>[];
        final m = _manager(
          onSingle: (o) async => processed.add('${o.orderNo}:${o.status.name}'),
          onBatch: (list) async => batches
              .add(list.map((o) => '${o.orderNo}:${o.status.name}').toList()),
        );
        m.queueOrder(_order(orderNo: 'a', status: OrderStatus.NEW));
        // 버퍼 윈도우(1s) 내 동일 orderId 의 DONE 인입 → 현재는 drop.
        m.queueOrder(_order(orderNo: 'a', status: OrderStatus.DONE));

        async.elapse(const Duration(seconds: 5));
        expect(processed, ['a:NEW']);
        expect(batches, isEmpty); // DONE 업데이트가 유실되는 현재 동작
        m.dispose();
      });
    });

    test('상태 업데이트가 배치 대기 중이면 동일 주문의 NEW 인입이 무시됨', () {
      fakeAsync((async) {
        final processed = <String>[];
        final batches = <List<String>>[];
        final m = _manager(
          onSingle: (o) async => processed.add('${o.orderNo}:${o.status.name}'),
          onBatch: (list) async => batches
              .add(list.map((o) => '${o.orderNo}:${o.status.name}').toList()),
        );
        m.queueOrder(_order(orderNo: 'a', status: OrderStatus.DONE));
        m.queueOrder(_order(orderNo: 'a', status: OrderStatus.NEW));

        async.elapse(const Duration(seconds: 5));
        expect(batches, [
          ['a:DONE']
        ]);
        expect(processed, isEmpty); // NEW 가 유실되는 현재 동작
        m.dispose();
      });
    });
  });

  group('hasPending / clearQueues', () {
    test('초기 상태는 pending 없음', () {
      final m = _manager(onSingle: (_) async {});
      expect(m.hasPending, isFalse);
    });

    test('clearQueues 는 대기 중 주문과 타이머를 모두 제거 (이후 방출 없음)', () {
      fakeAsync((async) {
        final processed = <String>[];
        final batches = <int>[];
        final m = _manager(
          onSingle: (o) async => processed.add(o.orderNo),
          onBatch: (list) async => batches.add(list.length),
        );
        m.queueOrder(_order(orderNo: 'a', status: OrderStatus.NEW));
        m.queueOrder(_order(orderNo: 'b', status: OrderStatus.DONE));
        expect(m.hasPending, isTrue);

        m.clearQueues();
        expect(m.hasPending, isFalse);

        async.elapse(const Duration(seconds: 10));
        expect(processed, isEmpty);
        expect(batches, isEmpty);
      });
    });
  });
}
