import 'package:appfit_order_agent/utils/socket_event_suppressor.dart';
import 'package:flutter_test/flutter_test.dart';

/// [SocketEventSuppressor] 는 싱글톤이라 테스트끼리 상태가 샌다.
/// 각 테스트가 서로 다른 orderId 를 쓰는 것으로 격리한다.
void main() {
  const eventType = 'ORDER_PICKUP_REQUESTED';

  group('SocketEventSuppressor.discard', () {
    test('등록한 억제를 해제하면 이후 이벤트가 통과한다', () {
      final s = SocketEventSuppressor();
      s.add('order-discard-1', eventType);

      s.discard('order-discard-1', eventType);

      // 해제됐으므로 무시 대상이 아니다 = 소켓 핸들러가 정상 처리해야 한다.
      expect(s.shouldIgnore('order-discard-1', eventType), isFalse);
    });

    test('해제하지 않으면 1회는 억제된다 (기존 동작 보존)', () {
      final s = SocketEventSuppressor();
      s.add('order-discard-2', eventType);

      expect(s.shouldIgnore('order-discard-2', eventType), isTrue);
      // 1회성 소비 — 두 번째부터는 통과
      expect(s.shouldIgnore('order-discard-2', eventType), isFalse);
    });

    test('등록되지 않은 키를 해제해도 예외가 나지 않는다', () {
      final s = SocketEventSuppressor();
      expect(
        () => s.discard('order-never-registered', eventType),
        returnsNormally,
      );
    });

    test('해제는 같은 (orderId, eventType) 만 지운다', () {
      final s = SocketEventSuppressor();
      s.add('order-discard-3', eventType);
      s.add('order-discard-4', eventType);

      s.discard('order-discard-3', eventType);

      expect(s.shouldIgnore('order-discard-3', eventType), isFalse);
      expect(s.shouldIgnore('order-discard-4', eventType), isTrue);
    });

    test('이벤트 타입이 다르면 지우지 않는다', () {
      final s = SocketEventSuppressor();
      s.add('order-discard-5', eventType);

      s.discard('order-discard-5', 'ORDER_DONE');

      expect(s.shouldIgnore('order-discard-5', eventType), isTrue);
    });
  });
}
