import 'package:appfit_order_agent/exceptions/label_ack_timeout_exception.dart';
import 'package:appfit_order_agent/exceptions/label_print_missing_exception.dart';
import 'package:appfit_order_agent/exceptions/order_detail_fetch_failed_exception.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sentry 이슈 타이틀 = 슬랙 알림 제목이 되는 toString 고정.
///
/// 그룹핑은 타입+스택트레이스 기준이라(서로 다른 displayNum 이벤트가 이미 한
/// 이슈로 묶여 있다) 이 문구를 바꿔도 이슈는 갈라지지 않는다. 쿨다운 키도
/// `runtimeType` 이라 무관하다. 즉 여기서 고정하는 것은 **읽는 사람의 경험**이다.
void main() {
  group('LabelPrintMissingException', () {
    test('몇 장 중 몇 장이 실패했고 무엇을 해야 하는지가 제목에 있다', () {
      final e = LabelPrintMissingException(
        orderNo: '874987496599613426',
        displayNum: '0916',
        failedCount: 1,
        totalLabels: 1,
        failedIndices: [1],
      );

      expect(e.toString(), '라벨 출력 안 됨 — 주문 0916번, 1장 중 1장 실패 (재출력 필요)');
    });

    test('인덱스는 제목에 넣지 않는다 — 14장짜리 주문이 한 줄을 다 먹는다', () {
      final e = LabelPrintMissingException(
        orderNo: '1',
        displayNum: '0615',
        failedCount: 14,
        totalLabels: 14,
        failedIndices: List.generate(14, (i) => i + 1),
      );

      expect(e.toString(), isNot(contains('14]')));
      expect(e.toString(), contains('14장 중 14장 실패'));
    });
  });

  group('LabelAckTimeoutException', () {
    // 라벨이 안 나온 LabelPrintMissingException 과 헷갈려 재출력을 안내하면
    // 중복 인쇄가 된다(2026-08-03 아오야마점). 제목이 그 구분을 진다.
    test('제목이 "인쇄된 것으로 간주" 를 명시해 재출력 오안내를 막는다', () {
      final e = LabelAckTimeoutException(
        orderNo: '874987496599613426',
        displayNum: '0624',
        labelIndex: 1,
        totalLabels: 2,
        attempt: 1,
      );

      expect(
        e.toString(),
        '라벨 프린터 응답 없음 — 주문 0624번 1/2장째, 1차 시도 (인쇄된 것으로 간주)',
      );
      expect(e.toString(), isNot(contains('재출력')));
    });
  });

  group('OrderDetailFetchFailedException', () {
    test('발생 지점을 우리말로 옮긴다', () {
      final e = OrderDetailFetchFailedException(
        orderNo: '874987496599613426',
        eventType: 'ORDER_CREATED',
        source: 'socket',
        lastError: 'DioException: connectionError',
      );

      expect(
        e.toString(),
        '주문 정보 조회 실패 — 주문 874987496599613426, 실시간 수신 중 (ORDER_CREATED)',
      );
    });

    test('lastError 는 제목에서 빠진다 (extras 로 간다)', () {
      final e = OrderDetailFetchFailedException(
        orderNo: '1',
        eventType: 'ORDER_CREATED',
        source: 'receipt',
        lastError: '아주 긴 스택 덤프가 여기 들어온다',
      );

      expect(e.toString(), isNot(contains('아주 긴 스택 덤프')));
      expect(e.toString(), contains('영수증 출력 중'));
    });

    test('모르는 source 는 뭉개지 않고 원문을 흘린다', () {
      final e = OrderDetailFetchFailedException(
        orderNo: '1',
        eventType: 'ORDER_CREATED',
        source: 'brand_new_path',
      );

      expect(e.toString(), contains('brand_new_path 중'));
    });
  });
}
