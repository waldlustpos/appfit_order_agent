import 'package:appfit_order_agent/models/enums/order_status.dart';
import 'package:flutter_test/flutter_test.dart';

/// I3 불변식: 상태 단조성/다운그레이드 금지.
///
/// 서버 PUT 직후 GET 응답이 구버전을 돌려주는 타이밍에서도 로컬이 더 진행된
/// 상태면 로컬을 유지해야 한다 (DONE→NEW 부활 금지). CANCELLED 는 터미널이라
/// 어느 쪽이든 우선한다.
///
/// resolveMergedStatus 는 ref/state 비의존 순수 함수이므로 직접 검증한다.
void main() {
  group('resolveMergedStatus — I3 상태 단조성', () {
    test('서버 구버전 다운그레이드 차단: local 우선', () {
      expect(resolveMergedStatus(OrderStatus.PREPARING, OrderStatus.NEW),
          OrderStatus.PREPARING);
      expect(resolveMergedStatus(OrderStatus.READY, OrderStatus.PREPARING),
          OrderStatus.READY);
      expect(resolveMergedStatus(OrderStatus.DONE, OrderStatus.READY),
          OrderStatus.DONE);
      // DONE → NEW 부활 시도 차단 (가장 위험한 케이스)
      expect(resolveMergedStatus(OrderStatus.DONE, OrderStatus.NEW),
          OrderStatus.DONE);
    });

    test('정상 진행: server 가 더 앞서면 server 채택', () {
      expect(resolveMergedStatus(OrderStatus.NEW, OrderStatus.PREPARING),
          OrderStatus.PREPARING);
      expect(resolveMergedStatus(OrderStatus.PREPARING, OrderStatus.READY),
          OrderStatus.READY);
      expect(resolveMergedStatus(OrderStatus.READY, OrderStatus.DONE),
          OrderStatus.DONE);
    });

    test('동일 상태: 그대로 유지', () {
      for (final s in OrderStatus.values) {
        expect(resolveMergedStatus(s, s), s);
      }
    });

    test('CANCELLED 터미널 우선: 어느 쪽이든 CANCELLED 면 CANCELLED', () {
      expect(resolveMergedStatus(OrderStatus.DONE, OrderStatus.CANCELLED),
          OrderStatus.CANCELLED);
      expect(resolveMergedStatus(OrderStatus.CANCELLED, OrderStatus.DONE),
          OrderStatus.CANCELLED);
      expect(resolveMergedStatus(OrderStatus.NEW, OrderStatus.CANCELLED),
          OrderStatus.CANCELLED);
      expect(resolveMergedStatus(OrderStatus.CANCELLED, OrderStatus.NEW),
          OrderStatus.CANCELLED);
      expect(
          resolveMergedStatus(OrderStatus.CANCELLED, OrderStatus.CANCELLED),
          OrderStatus.CANCELLED);
    });

    test('진행도 격자 단조성: 모든 (local, server) 쌍에서 결과가 두 입력 중 더 진행된 쪽 (CANCELLED 제외)', () {
      const progress = kOrderStatusProgress;
      final nonCancelled = OrderStatus.values
          .where((s) => s != OrderStatus.CANCELLED)
          .toList();
      for (final local in nonCancelled) {
        for (final server in nonCancelled) {
          final resolved = resolveMergedStatus(local, server);
          final expected =
              (progress[local]! >= progress[server]!) ? local : server;
          expect(resolved, expected,
              reason: 'local=$local server=$server 에서 더 진행된 상태가 채택돼야 함');
          // 결과 진행도는 두 입력의 최대값
          expect(progress[resolved]!,
              progress[local]! > progress[server]! ? progress[local] : progress[server]);
        }
      }
    });
  });
}
