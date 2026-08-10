import 'dart:convert';
import 'dart:typed_data';

import 'package:appfit_order_agent/models/order_model.dart';
import 'package:appfit_order_agent/services/api_service.dart';
import 'package:appfit_order_agent/services/appfit/appfit_providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 주문 **상세**(`GET /v1/orders/{orderNo}`) 응답 파싱 고정.
///
/// Swagger `OrderDetailV1Response` 기준. 이 경로는 그동안 테스트가 없었고,
/// 응답의 `payments`/`discounts` 를 앱이 통째로 버리고 있었다. 특히 **`payments` 폴백**(배열이 비면 상위 스칼라로 1건 합성)이
/// 회귀하면 결제수단 섹션이 조용히 사라지므로 여기서 잠근다.
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

/// Swagger `OrderDetailV1Response` 기준 상세 1건. [extra] 로 필드를 덮어쓴다.
/// 값에 `null` 을 주면 해당 키를 **제거**한다(키 누락 케이스 검증용).
Map<String, dynamic> _detail({Map<String, dynamic> extra = const {}}) {
  final base = <String, dynamic>{
    'orderNo': 873452469021424335,
    'shopId': 'shop-uuid',
    'shopCode': 'TPCP00001',
    'shopName': '왈루스트점',
    'shopOrderNo': 42,
    'displayOrderNo': '0909',
    'orderType': 'TAKE_OUT',
    'orderSource': 'WALD_KIOSK',
    'orderStatus': 'NEW',
    'paymentStatus': 'DONE',
    'paymentMethod': 'MULTI',
    'totalAmount': 12000,
    'totalDiscount': 2000,
    'paymentAmount': 10000,
    'totalQty': 2,
    'note': '얼음 많이',
    'createdAt': '2026-08-10T02:25:21.418Z',
    'user': {'userId': 'u-1', 'nickname': '홍길동', 'phone': '010-0000-0000'},
    'orderName': '아메리카노 외 1건',
    'orderLines': const [],
    'payments': [
      {
        'paymentMethod': 'CREDIT_CARD',
        'amount': 7000,
        'status': 'DONE',
        'cardName': '신한',
        'cardNo': '5327111122223333',
        'installment': 0,
        'approvalNo': '12345678',
        'txDate': '2026-08-10T02:25:30.000Z',
      },
      {
        'paymentMethod': 'CASH',
        'amount': 3000,
        'status': 'DONE',
      },
    ],
    'discounts': [
      {
        'discountType': 'COUPON',
        'discountAmount': 1000,
        'discountScope': 'ORDER',
        'couponNo': 'CP-1',
        'couponName': '1,000원 할인권',
      },
      {
        'discountType': 'POINT',
        'discountAmount': 1000,
        'discountScope': 'ORDER',
      },
    ],
  };
  extra.forEach((k, v) {
    if (v == null) {
      base.remove(k);
    } else {
      base[k] = v;
    }
  });
  return base;
}

Map<String, dynamic> _ok(Map<String, dynamic> data) =>
    {'code': 'SUCCESS', 'message': null, 'data': data};

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

Future<OrderModel> _fetch(Map<String, dynamic> data) async {
  final h = _harness((_) => _ok(data));
  return h.container.read(apiServiceProvider).getOrder('873452469021424335');
}

void main() {
  group('주문 상세 파싱 (GET /v1/orders/{orderNo})', () {
    test('v1 라우트로 요청한다', () async {
      final h = _harness((_) => _ok(_detail()));
      await h.container.read(apiServiceProvider).getOrder('873452469021424335');

      expect(h.adapter.requests, hasLength(1));
      expect(h.adapter.requests.single.path, '/v1/orders/873452469021424335');
    });

    test('복합결제 payments 2건을 수단·금액·상태 그대로 매핑한다', () async {
      final o = await _fetch(_detail());

      expect(o.payments, hasLength(2));
      expect(o.payments[0].paymentMethod, 'CREDIT_CARD');
      expect(o.payments[0].amount, 7000.0);
      expect(o.payments[0].status, 'DONE');
      expect(o.payments[1].paymentMethod, 'CASH');
      expect(o.payments[1].amount, 3000.0);
      // 상위 스칼라는 복합결제라 MULTI
      expect(o.paymentType, 'MULTI');
    });

    test('카드 상세를 담고 카드번호는 파싱 시점에 마스킹한다', () async {
      final o = await _fetch(_detail());
      final card = o.payments.first;

      expect(card.cardName, '신한');
      expect(card.cardNo, '5327-****');
      expect(card.cardNo, isNot(contains('1111'))); // 원본 PAN 미보유
      expect(card.installment, 0);
    });

    test('서버가 이미 마스킹한 카드번호는 원문을 유지한다', () async {
      final o = await _fetch(_detail(extra: {
        'payments': [
          {
            'paymentMethod': 'CREDIT_CARD',
            'amount': 7000,
            'status': 'DONE',
            'cardNo': '5327-****-****-3333',
          },
        ],
      }));

      expect(o.payments.single.cardNo, '5327-****-****-3333');
    });

    test('payments 키가 없으면 상위 paymentMethod 로 1건을 합성한다', () async {
      final o = await _fetch(_detail(extra: {
        'payments': null, // 키 제거
        'paymentMethod': 'CREDIT_CARD',
      }));

      expect(o.payments, hasLength(1));
      expect(o.payments.single.paymentMethod, 'CREDIT_CARD');
      expect(o.payments.single.amount, 10000.0); // totalAmount - totalDiscount
      expect(o.payments.single.status, 'DONE'); // 상위 paymentStatus
    });

    test('payments 가 빈 배열이어도 동일하게 1건을 합성한다', () async {
      final o = await _fetch(_detail(extra: {
        'payments': const [],
        'paymentMethod': 'CASH',
      }));

      expect(o.payments, hasLength(1));
      expect(o.payments.single.paymentMethod, 'CASH');
    });

    test('payments 와 paymentMethod 가 모두 없으면 빈 리스트 (예외 없음)', () async {
      final o = await _fetch(_detail(extra: {
        'payments': null,
        'paymentMethod': null,
      }));

      // paymentMethod 누락 시 paymentType 은 기존 폴백('CARD')이 유지되지만,
      // 합성은 하지 않는다 → 위젯이 결제수단 섹션을 통째로 숨긴다.
      expect(o.payments, isEmpty);
    });

    test('status 는 원문 그대로 보관한다 (UI 미사용, 상세 로그용)', () async {
      final o = await _fetch(_detail(extra: {
        'payments': [
          {
            'paymentMethod': 'CREDIT_CARD',
            'amount': 3000,
            'status': 'FULL_CANCELLED'
          },
          {'paymentMethod': 'CASH', 'amount': 10000, 'status': 'SOMETHING_NEW'},
        ],
      }));

      // 상태로 거르지 않는다 — 주문이 취소면 결제도 취소라는 전제라 UI 는 주문
      // 상태 배지만 보면 되고, 여기서는 서버 값을 손대지 않고 그대로 싣는다.
      expect(o.payments, hasLength(2));
      expect(o.payments[0].status, 'FULL_CANCELLED');
      expect(o.payments[1].status, 'SOMETHING_NEW');
    });

    test('discounts 를 금액·쿠폰명까지 매핑하고 discountTypes 는 distinct 파생', () async {
      final o = await _fetch(_detail());

      expect(o.discounts, hasLength(2));
      expect(o.discounts[0].discountType, 'COUPON');
      expect(o.discounts[0].discountAmount, 1000.0);
      expect(o.discounts[0].couponName, '1,000원 할인권');
      expect(o.discounts[0].discountScope, 'ORDER');
      expect(o.discounts[1].couponName, isNull);
      expect(o.discountTypes, ['COUPON', 'POINT']);
    });

    test('레거시 orderDiscounts 키도 동일하게 읽는다', () async {
      final o = await _fetch(_detail(extra: {
        'discounts': null,
        'orderDiscounts': [
          {
            'discountType': 'MEMBERSHIP',
            'discountAmount': 2000,
            'discountScope': 'ORDER',
          },
        ],
      }));

      expect(o.discounts, hasLength(1));
      expect(o.discounts.single.discountType, 'MEMBERSHIP');
      expect(o.discounts.single.discountAmount, 2000.0);
    });

    test('타입이 어긋난 배열/원소는 스킵하고 나머지는 정상 파싱한다', () async {
      final o = await _fetch(_detail(extra: {
        'payments': 'not-a-list',
        'discounts': [
          'not-a-map',
          {
            'discountType': 'POINT',
            'discountAmount': 500,
            'discountScope': 'ORDER'
          },
        ],
      }));

      // payments 가 List 가 아니면 폴백이 걸려 상위 스칼라로 합성
      expect(o.payments, hasLength(1));
      expect(o.payments.single.paymentMethod, 'MULTI');
      // 손상 원소만 스킵
      expect(o.discounts, hasLength(1));
      expect(o.discounts.single.discountType, 'POINT');
    });

    test('toSunmiJson 이 jsonEncode 가능해야 한다 (영수증 출력 경로 보호)', () async {
      final o = await _fetch(_detail());

      // print_service 가 toSunmiJson() 결과를 jsonEncode 해 네이티브로 넘긴다.
      // 중첩 모델이 DateTime/enum 같은 non-primitive 를 흘리면 영수증이 통째로
      // 안 나오므로, 인코딩 가능성 자체를 테스트로 잠근다.
      expect(() => jsonEncode(o.toSunmiJson()), returnsNormally);

      final decoded =
          jsonDecode(jsonEncode(o.toSunmiJson())) as Map<String, dynamic>;
      expect(decoded['payments'], hasLength(2));
      expect((decoded['payments'] as List).first['cardNo'], '5327-****');
      expect(decoded['discountTypes'], ['COUPON', 'POINT']);
    });
  });
}
