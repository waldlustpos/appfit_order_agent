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

  group('OrderSocketManager.enforceStatusFromEvent — 보정은 앞으로만', () {
    // 서버는 NEW 인 주문만 접수를 허용한다. 결제와 동시에 PREPARING 으로 생성되는
    // 주문 유형(NICE_KIOSK 등)의 ORDER_CREATED 이벤트를 보고 상태를 NEW 로 되돌리면,
    // 앱이 이미 수락된 주문에 접수를 시도해 400 INVALID_ORDER_STATUS 를 맞는다.
    OrderSocketManager build() {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      return container.read(
        Provider<OrderSocketManager>((ref) => OrderSocketManager(ref)),
      );
    }

    test('ORDER_CREATED 인데 API 가 PREPARING 이면 NEW 로 되돌리지 않는다', () {
      final manager = build();
      final accepted = _order('A').copyWith(
        status: OrderStatus.PREPARING,
        orderStatus: '2007',
      );

      final result =
          manager.enforceStatusFromEventForTest(accepted, 'ORDER_CREATED');

      expect(result.status, OrderStatus.PREPARING);
      // 원본 상태코드도 보존한다 — 상태를 안 바꿨는데 코드만 바뀌면 어긋난다.
      expect(result.orderStatus, '2007');
    });

    test('ORDER_ACCEPTED 인데 API 가 아직 NEW 면 PREPARING 으로 앞당긴다 (기존 동작 유지)', () {
      final manager = build();

      final result =
          manager.enforceStatusFromEventForTest(_order('A'), 'ORDER_ACCEPTED');

      expect(result.status, OrderStatus.PREPARING);
      expect(result.orderStatus, '2007');
    });

    test('ORDER_CANCELLED 는 진행도와 무관하게 터미널로 확정된다', () {
      final manager = build();
      final done = _order('A').copyWith(
        status: OrderStatus.DONE,
        orderStatus: '2020',
      );

      final result =
          manager.enforceStatusFromEventForTest(done, 'ORDER_CANCELLED');

      expect(result.status, OrderStatus.CANCELLED);
      expect(result.orderStatus, '9001');
    });

    test('알 수 없는 이벤트 타입은 주문을 그대로 통과시킨다', () {
      final manager = build();
      final ready = _order('A').copyWith(
        status: OrderStatus.READY,
        orderStatus: '2009',
      );

      final result =
          manager.enforceStatusFromEventForTest(ready, 'SOMETHING_ELSE');

      expect(result.status, OrderStatus.READY);
      expect(result.orderStatus, '2009');
    });
  });

  group('OrderSocketManager.isExternallyAcceptedAtCreation', () {
    // 생성 시점부터 PREPARING 인 주문(NICE_KIOSK 등)은 앱이 접수 단계를 거치지
    // 않아 '접수 성공' 에 걸린 사운드그래프 전송이 발화하지 않는다. 그 공백을
    // 메우는 판정이자, 중복 전송을 막는 유일한 방어선이다.
    test('ORDER_CREATED + PREPARING 이면 외부 접수로 본다', () {
      expect(
        OrderSocketManager.isExternallyAcceptedAtCreation(
            'ORDER_CREATED', OrderStatus.PREPARING),
        isTrue,
      );
    });

    test('ORDER_CREATED + NEW 는 평범한 신규 주문 — 앱이 접수한다', () {
      expect(
        OrderSocketManager.isExternallyAcceptedAtCreation(
            'ORDER_CREATED', OrderStatus.NEW),
        isFalse,
      );
    });

    test('ORDER_ACCEPTED + PREPARING 은 제외 — 다른 단말이 접수한 주문이다', () {
      // 이걸 통과시키면 단말 수만큼 같은 주문이 KDS 에 중복으로 뜬다.
      expect(
        OrderSocketManager.isExternallyAcceptedAtCreation(
            'ORDER_ACCEPTED', OrderStatus.PREPARING),
        isFalse,
      );
    });

    test('종결 상태 이벤트는 대상이 아니다', () {
      expect(
        OrderSocketManager.isExternallyAcceptedAtCreation(
            'ORDER_DONE', OrderStatus.DONE),
        isFalse,
      );
      expect(
        OrderSocketManager.isExternallyAcceptedAtCreation(
            'ORDER_CANCELLED', OrderStatus.CANCELLED),
        isFalse,
      );
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
