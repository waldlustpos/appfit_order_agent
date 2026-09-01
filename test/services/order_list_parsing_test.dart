import 'dart:convert';
import 'dart:typed_data';

import 'package:appfit_order_agent/models/order_model.dart';
import 'package:appfit_order_agent/services/api_service.dart';
import 'package:appfit_order_agent/services/appfit/appfit_providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 주문 **목록**(`GET /v1/orders`) 응답 파싱 고정.
///
/// 목록 응답 스키마는 v0/v1 이 동일하다(`SliceResponse<ReadAllOrderResponse>`,
/// 서버가 v1 에서도 v0 패키지 DTO 를 그대로 쓴다). 그래서 픽스처 하나로 양쪽을
/// 커버한다. 그동안 이 경로는 테스트가 전혀 없었다 — 기존 통합 테스트는
/// `ApiService` 를 통째로 fake 로 대체해 `content`/`slice`/키 매핑을 검증하지 않는다.
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

/// Swagger `ReadAllOrderResponse` 기준 목록 항목 1건.
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
    'orderName': 'アメリカーノ 1개',
    'status': status,
    'totalAmount': 1200,
    'totalDiscount': 200,
    'totalQty': 3,
    'paymentStatus': 'DONE',
    'paymentAmount': 1000,
    'paymentMethod': 'CREDIT_CARD',
    'note': '덜 달게',
    'createdAt': '2026-07-27T02:25:21.418Z',
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
  group('주문 목록 파싱 (GET /v1/orders)', () {
    test('v1 라우트로 요청하고 조회 파라미터를 싣는다', () async {
      final h = _harness((_) => _page([_item()]));

      await h.container.read(apiServiceProvider).getOrders(
            'TPCP00001',
            startDate: '2026-07-27',
            endDate: '2026-07-27',
          );

      final req = h.adapter.requests.single;
      expect(req.path, '/v1/orders');
      expect(req.queryParameters['shopCode'], 'TPCP00001');
      expect(req.queryParameters['sortBy'], 'CreatedAtDesc');
    });

    // v1 은 from/to 가 날짜가 아니라 일시(yyyy-MM-dd'T'HH:mm:ss)다.
    // 날짜만 보내면 서버가 400 INVALID_REQUEST 로 거절한다(실기기에서 확인).
    test('날짜를 하루 전체 범위의 일시로 확장해 보낸다', () async {
      final h = _harness((_) => _page([_item()]));

      await h.container.read(apiServiceProvider).getOrders(
            'TPCP00001',
            startDate: '2026-07-27',
            endDate: '2026-07-27',
          );

      final q = h.adapter.requests.single.queryParameters;
      expect(q['from'], '2026-07-27T00:00:00');
      expect(q['to'], '2026-07-27T23:59:59');
    });

    test('이미 일시가 오면 그대로 보낸다', () async {
      final h = _harness((_) => _page([_item()]));

      await h.container.read(apiServiceProvider).getOrders(
            'TPCP00001',
            startDate: '2026-07-27T09:30:00',
            endDate: '2026-07-27T18:00:00',
          );

      final q = h.adapter.requests.single.queryParameters;
      expect(q['from'], '2026-07-27T09:30:00');
      expect(q['to'], '2026-07-27T18:00:00');
    });

    test('endDate 가 날짜 형식이 아니면(폴링 시퀀스 번호) to 를 싣지 않는다', () async {
      final h = _harness((_) => _page([_item()]));

      await h.container
          .read(apiServiceProvider)
          .getOrders('TPCP00001', startDate: '2026-07-27', endDate: '12345');

      final q = h.adapter.requests.single.queryParameters;
      expect(q.containsKey('to'), isFalse);
      expect(q['from'], '2026-07-27T00:00:00');
    });

    test('content 항목을 OrderModel 로 매핑한다', () async {
      final h = _harness((_) => _page([_item()]));

      final orders =
          await h.container.read(apiServiceProvider).getOrders('TPCP00001');

      expect(orders, hasLength(1));
      final o = orders.single;
      expect(o.orderNo, '869372468383139252');
      expect(o.shopOrderNo, '42');
      expect(o.displayOrderNo, '0909');
      expect(o.status, OrderStatus.NEW);
      expect(o.storeId, 'TPCP00001');
      expect(o.ordererName, 'アメリカーノ 1개');
      expect(o.orderCount, '3');
      expect(o.totalAmount, 1200);
      expect(o.paymentAmount, 1000);
      expect(o.discountAmount, 200);
      expect(o.paymentType, 'CREDIT_CARD');
      expect(o.source, 'WALD_KIOSK');
      expect(o.userName, '홍길동');
      expect(o.tel, '010-0000-0000');
      // 목록 응답에는 메뉴/옵션이 없다 — 상세 조회로만 채워진다.
      expect(o.menus, isEmpty);
    });

    test('slice.last=false 면 다음 페이지까지 이어서 읽는다', () async {
      final h = _harness((options) {
        final page = options.queryParameters['page'] as int;
        return page == 0
            ? _page([_item(orderNo: 1), _item(orderNo: 2)], last: false)
            : _page([_item(orderNo: 3)], last: true);
      });

      final orders =
          await h.container.read(apiServiceProvider).getOrders('TPCP00001');

      expect(orders.map((o) => o.orderNo), ['1', '2', '3']);
      expect(h.adapter.requests.map((r) => r.queryParameters['page']), [0, 1]);
    });

    test('slice 가 없으면 첫 페이지에서 멈춘다', () async {
      final h = _harness((_) => {
            'code': 'SUCCESS',
            'data': {
              'content': [_item()]
            },
          });

      final orders =
          await h.container.read(apiServiceProvider).getOrders('TPCP00001');

      expect(orders, hasLength(1));
      expect(h.adapter.requests, hasLength(1));
    });

    // 서버 status enum: PENDING/NEW/PREPARING/READY/DONE/CANCELLED/FAILED/UNKNOWN
    test('상태 문자열을 OrderStatus 로 매핑한다', () async {
      Future<OrderStatus> mapped(String status) async {
        final h = _harness((_) => _page([_item(status: status)]));
        final orders =
            await h.container.read(apiServiceProvider).getOrders('TPCP00001');
        return orders.single.status;
      }

      expect(await mapped('PENDING'), OrderStatus.NEW);
      expect(await mapped('NEW'), OrderStatus.NEW);
      expect(await mapped('PREPARING'), OrderStatus.PREPARING);
      expect(await mapped('ACCEPTED'), OrderStatus.PREPARING);
      expect(await mapped('READY'), OrderStatus.READY);
      expect(await mapped('DONE'), OrderStatus.DONE);
      expect(await mapped('CANCELLED'), OrderStatus.CANCELLED);
      expect(await mapped('FAILED'), OrderStatus.CANCELLED);
      // PICKUP_REQUESTED 는 이 프로덕션 파서에 없어서 CANCELLED 로 떨어지던
      // 값이다(테스트 전용 파서에만 있었다). 방어로 매핑표에 넣었다.
      expect(await mapped('PICKUP_REQUESTED'), OrderStatus.READY);
      // 미매핑 값(스키마에 실재하는 UNKNOWN 포함)은 CANCELLED 로 떨어진다.
      // 무증상 실패라 프로덕션 코드가 경고 로그를 남긴다 — 동작 자체는 보존.
      expect(await mapped('UNKNOWN'), OrderStatus.CANCELLED);
      expect(await mapped('SOMETHING_NEW'), OrderStatus.CANCELLED);
    });

    // 서버 엔드포인트 확정 전까지 가칭 문자열 + 별칭을 받는다. 이 매핑이 빠지면
    // 미픽업 주문이 화면에 '취소' 로 보이는 무증상 실패가 된다.
    test('미픽업 상태 문자열을 NOT_PICKED_UP 으로 매핑한다 (가칭 + 별칭)', () async {
      Future<OrderStatus> mapped(String status) async {
        final h = _harness((_) => _page([_item(status: status)]));
        final orders =
            await h.container.read(apiServiceProvider).getOrders('TPCP00001');
        return orders.single.status;
      }

      for (final alias in kNotPickedUpServerAliases) {
        expect(await mapped(alias), OrderStatus.NOT_PICKED_UP,
            reason: '별칭 $alias');
      }
    });
  });
}
