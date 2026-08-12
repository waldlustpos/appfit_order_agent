import 'package:appfit_order_agent/exceptions/order_detail_fetch_failed_exception.dart';
import 'package:appfit_order_agent/models/order_menu_model.dart';
import 'package:appfit_order_agent/models/order_model.dart';
import 'package:appfit_order_agent/providers/order/order_socket_manager.dart';
import 'package:appfit_order_agent/providers/providers.dart';
import 'package:appfit_order_agent/services/api_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// getOrder 호출 횟수와 시나리오(성공/실패)를 제어하는 fake.
/// ApiService 의 나머지 멤버는 테스트에서 호출되지 않으므로 noSuchMethod.
class _FakeApiService implements ApiService {
  _FakeApiService(this.responder);

  /// (callIndex) -> OrderModel 반환 또는 throw.
  final Future<OrderModel> Function(int callIndex) responder;
  int callCount = 0;

  @override
  Future<OrderModel> getOrder(String orderId, {String? storeId}) {
    final i = callCount++;
    return responder(i);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

OrderModel _order(String orderId) => OrderModel(
      orderNo: orderId,
      shopOrderNo: '0001',
      orderStatus: OrderStatus.NEW.name,
      orderedAt: DateTime.utc(2026, 1, 1, 9),
      totalAmount: 9000,
      status: OrderStatus.NEW,
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

DioException _dioStatus(int code) => DioException(
      requestOptions: RequestOptions(path: '/orders/1'),
      type: DioExceptionType.badResponse,
      response: Response(
        requestOptions: RequestOptions(path: '/orders/1'),
        statusCode: code,
      ),
    );

DioException _dioType(DioExceptionType type) => DioException(
      requestOptions: RequestOptions(path: '/orders/1'),
      type: type,
    );

void main() {
  group('OrderSocketManager.isTransientError', () {
    test('5xx 는 transient', () {
      expect(OrderSocketManager.isTransientError(_dioStatus(500)), isTrue);
      expect(OrderSocketManager.isTransientError(_dioStatus(503)), isTrue);
    });

    test('4xx 는 non-transient (재시도해도 동일 실패)', () {
      expect(OrderSocketManager.isTransientError(_dioStatus(400)), isFalse);
      expect(OrderSocketManager.isTransientError(_dioStatus(401)), isFalse);
      expect(OrderSocketManager.isTransientError(_dioStatus(404)), isFalse);
    });

    test('타임아웃/연결오류는 transient', () {
      expect(
          OrderSocketManager.isTransientError(
              _dioType(DioExceptionType.connectionTimeout)),
          isTrue);
      expect(
          OrderSocketManager.isTransientError(
              _dioType(DioExceptionType.receiveTimeout)),
          isTrue);
      expect(
          OrderSocketManager.isTransientError(
              _dioType(DioExceptionType.sendTimeout)),
          isTrue);
      expect(
          OrderSocketManager.isTransientError(
              _dioType(DioExceptionType.connectionError)),
          isTrue);
    });

    test('Dio 가 아닌 예외는 non-transient', () {
      expect(OrderSocketManager.isTransientError(const FormatException()),
          isFalse);
      expect(OrderSocketManager.isTransientError(StateError('x')), isFalse);
    });
  });

  group('OrderSocketManager.fetchOrderDetailWithRetry', () {
    OrderSocketManager build(_FakeApiService api) {
      final container = ProviderContainer(overrides: [
        apiServiceProvider.overrideWithValue(api),
      ]);
      addTearDown(container.dispose);
      final managerProvider =
          Provider<OrderSocketManager>((ref) => OrderSocketManager(ref));
      final manager = container.read(managerProvider);
      // 테스트 속도를 위해 backoff 를 0 으로 단축.
      manager.detailFetchBackoffs = const [
        Duration.zero,
        Duration.zero,
        Duration.zero,
      ];
      return manager;
    }

    test('5xx 1회 후 성공하면 재시도하여 성공 반환', () async {
      final api = _FakeApiService((i) async {
        if (i == 0) throw _dioStatus(503);
        return _order('1');
      });
      final manager = build(api);
      final result = await manager.fetchOrderDetailForTest('1', 'store-1');
      expect(result.orderNo, '1');
      expect(api.callCount, 2);
    });

    test('404 는 즉시 throw, 재시도 없음', () async {
      final api = _FakeApiService((i) async => throw _dioStatus(404));
      final manager = build(api);
      await expectLater(
        manager.fetchOrderDetailForTest('1', 'store-1'),
        throwsA(isA<DioException>()),
      );
      expect(api.callCount, 1);
    });

    test('5xx 지속 시 3회 소진 후 rethrow', () async {
      final api = _FakeApiService((i) async => throw _dioStatus(503));
      final manager = build(api);
      await expectLater(
        manager.fetchOrderDetailForTest('1', 'store-1'),
        throwsA(isA<DioException>()),
      );
      expect(api.callCount, 3);
    });
  });

  group('OrderDetailFetchFailedException', () {
    test('toString 에 식별 정보 포함', () {
      final e = OrderDetailFetchFailedException(
        orderNo: 'A1',
        eventType: 'ORDER_CREATED',
        source: 'socket',
        lastError: 'boom',
      );
      final s = e.toString();
      expect(s, contains('A1'));
      expect(s, contains('ORDER_CREATED'));
      // source 는 슬랙 제목용으로 우리말로 옮겨진다 — 원문 'socket' 이 아니라
      // 매핑된 표기가 나와야 한다. 문구 전체 고정은
      // test/exceptions/label_and_detail_titles_test.dart 참고.
      expect(s, contains('실시간 수신'));
    });
  });
}
