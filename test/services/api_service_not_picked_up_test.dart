import 'dart:convert';
import 'dart:typed_data';

import 'package:appfit_order_agent/exceptions/api_exceptions.dart';
import 'package:appfit_order_agent/services/api_service.dart';
import 'package:appfit_order_agent/services/appfit/appfit_providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 미픽업 처리 API(`ApiService.markOrderNotPickedUp`) 계약 고정.
///
/// **서버 엔드포인트가 아직 없다(2026-09).** 그래서 이 테스트가 고정하는 것은
/// "서버가 뭘 돌려주든 호출부가 그걸 구분할 수 있는가" 다. 특히 미배포 404 가
/// 조용히 false 로 뭉개지지 않고 [ApiException] 으로 올라가야 한다 — 그래야
/// 상세팝업이 "서버 미지원일 수 있습니다" 를 띄운다.
class _StatusAdapter implements HttpClientAdapter {
  _StatusAdapter({
    this.statusCode = 200,
    this.body = const <String, dynamic>{'code': 'SUCCESS'},
  });

  final int statusCode;
  final Map<String, dynamic> body;
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
      jsonEncode(body),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

({ProviderContainer container, _StatusAdapter adapter}) _harness({
  int statusCode = 200,
  Map<String, dynamic> body = const <String, dynamic>{'code': 'SUCCESS'},
}) {
  final adapter = _StatusAdapter(statusCode: statusCode, body: body);
  final dio = Dio()..httpClientAdapter = adapter;
  final container = ProviderContainer(
    overrides: [appFitDioProvider.overrideWithValue(dio)],
  );
  addTearDown(container.dispose);
  return (container: container, adapter: adapter);
}

void main() {
  group('markOrderNotPickedUp — 가칭 전용 엔드포인트(A안)', () {
    test('POST /v0/order/{orderNo}/not-picked-up 을 친다', () async {
      final h = _harness();

      await h.container.read(apiServiceProvider).markOrderNotPickedUp('ORD-1');

      final req = h.adapter.requests.single;
      expect(req.method, 'POST');
      expect(req.path, '/v0/order/ORD-1/not-picked-up');
    });

    test('200 이면 true', () async {
      final h = _harness();

      final ok =
          await h.container.read(apiServiceProvider).markOrderNotPickedUp('A');

      expect(ok, isTrue);
    });
  });

  group('markOrderNotPickedUp — 실패는 예외로 드러난다', () {
    test('미배포 서버의 404 는 삼키지 않고 ApiException 으로 던진다', () async {
      // 엔드포인트 확정 전 실기기에서 실제로 보게 될 경로다. false 로 뭉개면
      // 팝업이 "상태 변경에 실패했습니다" 라는 무의미한 문구만 띄운다.
      final h = _harness(statusCode: 404, body: const {'code': 'NOT_FOUND'});

      expect(
        () => h.container.read(apiServiceProvider).markOrderNotPickedUp('A'),
        throwsA(isA<ApiException>()),
      );
    });

    test('서버 message 원문이 예외 메시지가 된다 (409 등)', () async {
      final h = _harness(
        statusCode: 409,
        body: const {
          'code': 'INVALID_ORDER_STATUS',
          'message': '이미 완료된 주문입니다.'
        },
      );

      await expectLater(
        () => h.container.read(apiServiceProvider).markOrderNotPickedUp('A'),
        throwsA(isA<ApiException>()
            .having((e) => e.message, 'message', '이미 완료된 주문입니다.')),
      );
    });

    test('서버 message 가 없으면 기본 문구로 미지원 가능성을 알린다', () async {
      final h = _harness(statusCode: 404, body: const {'code': 'NOT_FOUND'});

      await expectLater(
        () => h.container.read(apiServiceProvider).markOrderNotPickedUp('A'),
        throwsA(isA<ApiException>()
            .having((e) => e.message, 'message', contains('서버 미지원'))),
      );
    });
  });
}
