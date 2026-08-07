import 'dart:convert';
import 'dart:typed_data';

import 'package:appfit_order_agent/dev/net_fault_injector.dart';
import 'package:appfit_order_agent/providers/api_health_provider.dart';
import 'package:appfit_order_agent/services/api_service.dart';
import 'package:appfit_order_agent/services/appfit/appfit_providers.dart';
import 'package:appfit_order_agent/models/enums/order_status.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 장애 주입 경로 characterization.
///
/// 검증하는 계약:
/// - 주입 지점이 `try` **안**에 있어 실패가 [_logApiFailure]/[_recordApiFailure]
///   를 타고 건강도(`ApiHealth`)에 기록된다. 전신 injector 는 `try` 밖이라
///   강제 실패를 걸어도 배너가 안 떴다 — 이 테스트가 그 회귀를 막는다.
/// - 주입 실패는 실제 네트워크 요청 **전에** 단락된다(`adapter.requests` 비어 있음).
/// - `slowOnly` 는 요청을 통과시키고 성공으로 기록된다.
/// - `updateOrderStatus` 는 주입 실패 시 예외가 아니라 `false` 를 돌려준다
///   (catch 가 INVALID_ORDER_STATUS 외 전부 삼키는 기존 계약 유지 —
///   호출부의 else 분기 → SocketEventSuppressor.discard 가 타는 경로).
///
/// 어댑터/픽스처는 order_list_parsing_test.dart 의 패턴을 복제했다
/// (test/ 공용 헬퍼 디렉토리가 없는 프로젝트 관행).
class _CannedAdapter implements HttpClientAdapter {
  _CannedAdapter(this.responder);

  final Map<String, dynamic> Function(RequestOptions options) responder;
  final List<RequestOptions> requests = [];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode(responder(options)),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

Map<String, dynamic> _item({
  int orderNo = 869372468383139252,
  String status = 'NEW',
}) {
  return {
    'projectId': 'prj-1',
    'shopId': 'shop-uuid',
    'shopCode': 'TPCP00001',
    'userId': 'ex_system',
    'userBarcode': '',
    'userName': '홍길동',
    'userContact': '010-0000-0000',
    'orderNo': orderNo,
    'shopOrderNo': 42,
    'displayOrderNo': '0909',
    'orderType': 'TAKE_OUT',
    'orderSource': 'WALD_KIOSK',
    'orderName': '아메리카노 1개',
    'status': status,
    'totalAmount': 1200,
    'totalDiscount': 200,
    'totalQty': 3,
    'paymentStatus': 'DONE',
    'paymentAmount': 1000,
    'paymentMethod': 'CREDIT_CARD',
    'note': '',
    'createdAt': '2026-08-07T02:25:21.418Z',
    'orderLogs': const [],
  };
}

Map<String, dynamic> _page(List<Map<String, dynamic>> items,
        {bool last = true}) =>
    {
      'code': 'SUCCESS',
      'message': null,
      'data': {
        'content': items,
        'slice': {'last': last, 'empty': items.isEmpty},
      },
    };

/// updateOrderStatus 용 성공 응답.
Map<String, dynamic> _updateOk() => {'code': 'SUCCESS', 'data': {}};

({ProviderContainer container, _CannedAdapter adapter}) _harness(
  Map<String, dynamic> Function(RequestOptions options) responder,
) {
  final adapter = _CannedAdapter(responder);
  final dio = Dio()..httpClientAdapter = adapter;
  final container = ProviderContainer(
    overrides: [appFitDioProvider.overrideWithValue(dio)],
  );
  addTearDown(container.dispose);
  return (container: container, adapter: adapter);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // static 무장 상태가 다른 테스트 파일(order_list_parsing_test 등)로 새는 것을
  // 막는다. 만료 Timer 도 함께 취소된다.
  tearDown(NetFaultInjector.clear);

  int failures(ProviderContainer c) =>
      c.read(apiHealthNotifierProvider).consecutiveFailures;

  group('주입 실패가 건강도에 기록된다 (try 안 배치의 회귀 방지)', () {
    test('getOrders 무장 → throw + 요청 단락 + 실패 1회 기록', () async {
      final h = _harness((_) => _page([_item()]));
      NetFaultInjector.arm(const NetFaultConfig(
        targets: {NetFaultTarget.orders},
        kind: NetFaultKind.dnsFailure,
      ));

      await expectLater(
        h.container.read(apiServiceProvider).getOrders('TPCP00001'),
        throwsA(isA<DioException>()
            .having((e) => e.type, 'type', DioExceptionType.connectionError)),
      );

      expect(h.adapter.requests, isEmpty, reason: '실제 요청 전에 단락돼야 한다');
      expect(failures(h.container), 1,
          reason: '주입 실패도 실제 실패처럼 건강도에 잡혀야 배너가 뜬다');
    });

    test('2회 실패로 degraded 진입 (P4 프리셋의 전제)', () async {
      final h = _harness((_) => _page([_item()]));
      NetFaultInjector.arm(const NetFaultConfig(
        targets: {NetFaultTarget.orders},
        kind: NetFaultKind.dnsFailure,
        remaining: 2,
      ));

      final api = h.container.read(apiServiceProvider);
      await expectLater(api.getOrders('TPCP00001'), throwsA(anything));
      expect(h.container.read(apiHealthNotifierProvider).isDegraded, isFalse);

      await expectLater(api.getOrders('TPCP00001'), throwsA(anything));
      expect(h.container.read(apiHealthNotifierProvider).isDegraded, isTrue);

      // 잔여 소진 → 3번째는 실제 요청이 나가고 성공 → 회복
      final orders = await api.getOrders('TPCP00001');
      expect(orders, hasLength(1));
      expect(h.adapter.requests, hasLength(1));
      expect(h.container.read(apiHealthNotifierProvider).isDegraded, isFalse);
      expect(
          h.container.read(apiHealthNotifierProvider).lastSuccessAt, isNotNull);
    });

    test('getOrder 무장 → throw + 실패 기록', () async {
      final h = _harness((_) => _page([_item()]));
      NetFaultInjector.arm(const NetFaultConfig(
        targets: {NetFaultTarget.orderDetail},
        kind: NetFaultKind.receiveTimeout,
      ));

      await expectLater(
        h.container.read(apiServiceProvider).getOrder('869372468383139252'),
        throwsA(isA<DioException>()
            .having((e) => e.type, 'type', DioExceptionType.receiveTimeout)),
      );
      expect(h.adapter.requests, isEmpty);
      expect(failures(h.container), 1);
    });

    test('notFound(4xx) 무장 → 카운터 리셋 (열화가 아니다)', () async {
      final h = _harness((_) => _page([_item()]));
      final api = h.container.read(apiServiceProvider);

      // 먼저 transient 1회로 카운터를 올려두고
      NetFaultInjector.arm(const NetFaultConfig(
        targets: {NetFaultTarget.orders},
        kind: NetFaultKind.dnsFailure,
        remaining: 1,
      ));
      await expectLater(api.getOrders('TPCP00001'), throwsA(anything));
      expect(failures(h.container), 1);

      // 404 는 서버가 정상 응답한 것 → 리셋
      NetFaultInjector.arm(const NetFaultConfig(
        targets: {NetFaultTarget.orders},
        kind: NetFaultKind.notFound,
        remaining: 1,
      ));
      await expectLater(api.getOrders('TPCP00001'), throwsA(anything));
      expect(failures(h.container), 0,
          reason: '4xx 는 네트워크 열화로 세지 않는 계약 (end-to-end 고정)');
    });
  });

  group('updateOrderStatus 의 삼킴 계약', () {
    test('주입 실패 → 예외가 아니라 false (discard 를 타는 else 경로)', () async {
      final h = _harness((_) => _updateOk());
      NetFaultInjector.arm(const NetFaultConfig(
        targets: {NetFaultTarget.orderUpdate},
        kind: NetFaultKind.receiveTimeout,
      ));

      final ok = await h.container.read(apiServiceProvider).updateOrderStatus(
          'TPCP00001', OrderStatus.READY, '869372468383139252');

      expect(ok, isFalse, reason: 'INVALID_ORDER_STATUS 외 예외는 false 로 삼킨다');
      expect(h.adapter.requests, isEmpty);
      expect(failures(h.container), 1);
    });

    test('비무장 시 정상 성공 + 성공 기록', () async {
      final h = _harness((_) => _updateOk());

      final ok = await h.container.read(apiServiceProvider).updateOrderStatus(
          'TPCP00001', OrderStatus.READY, '869372468383139252');

      expect(ok, isTrue);
      expect(h.adapter.requests.single.path, '/v0/order/869372468383139252');
      expect(
          h.container.read(apiHealthNotifierProvider).lastSuccessAt, isNotNull);
    });
  });

  group('slowOnly (버퍼블로트 재현)', () {
    test('요청이 실제로 나가고 성공으로 기록된다 — 배너 오탐 없음의 전제', () async {
      final h = _harness((_) => _page([_item()]));
      NetFaultInjector.arm(const NetFaultConfig(
        targets: {NetFaultTarget.orders},
        kind: NetFaultKind.slowOnly,
        // 테스트에서는 지연 0 — 지연의 실제 대기는 injector 단위 테스트와
        // 실기기 검증(P2/P5)이 담당한다.
        delay: Duration.zero,
      ));

      final orders =
          await h.container.read(apiServiceProvider).getOrders('TPCP00001');

      expect(orders, hasLength(1));
      expect(h.adapter.requests, hasLength(1), reason: '요청이 통과해야 한다');
      expect(failures(h.container), 0, reason: '느린 성공은 성공이다 — 배너가 뜨면 버그');
    });
  });

  group('대상 필터링', () {
    test('orderUpdate 만 무장하면 getOrders 는 정상', () async {
      final h = _harness((_) => _page([_item()]));
      NetFaultInjector.arm(const NetFaultConfig(
        targets: {NetFaultTarget.orderUpdate},
        kind: NetFaultKind.dnsFailure,
      ));

      final orders =
          await h.container.read(apiServiceProvider).getOrders('TPCP00001');

      expect(orders, hasLength(1));
      expect(failures(h.container), 0);
    });
  });
}
