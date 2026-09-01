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
      expect(resolveMergedStatus(OrderStatus.CANCELLED, OrderStatus.CANCELLED),
          OrderStatus.CANCELLED);
    });

    test('진행도 격자 단조성: 모든 (local, server) 쌍에서 결과가 두 입력 중 더 진행된 쪽 (터미널 제외)', () {
      const progress = kOrderStatusProgress;
      // 터미널 상태는 격자 밖이라 progress 에 없다 — 여기서 걸러내지 않으면
      // progress[s]! 가 null-check 로 터진다.
      final nonTerminal = OrderStatus.values
          .where((s) => !kTerminalStatusPriority.contains(s))
          .toList();
      for (final local in nonTerminal) {
        for (final server in nonTerminal) {
          final resolved = resolveMergedStatus(local, server);
          final expected =
              (progress[local]! >= progress[server]!) ? local : server;
          expect(resolved, expected,
              reason: 'local=$local server=$server 에서 더 진행된 상태가 채택돼야 함');
          // 결과 진행도는 두 입력의 최대값
          expect(
              progress[resolved]!,
              progress[local]! > progress[server]!
                  ? progress[local]
                  : progress[server]);
        }
      }
    });

    test('격자 밖 터미널: kOrderStatusProgress 에 터미널 상태가 없어야 한다', () {
      // 터미널을 격자에 넣으면 `?? 0` 폴백에 걸려 NEW 급으로 취급되고,
      // 서버 stale 응답에 종결 주문이 폴링마다 되살아난다.
      for (final terminal in kTerminalStatusPriority) {
        expect(kOrderStatusProgress.containsKey(terminal), isFalse,
            reason: '$terminal 은 진행도 격자에 들어가면 안 된다');
      }
      // 반대로 격자는 비터미널 상태를 전부 덮어야 한다 (?? 0 폴백 도달 금지).
      for (final s in OrderStatus.values) {
        if (kTerminalStatusPriority.contains(s)) continue;
        expect(kOrderStatusProgress.containsKey(s), isTrue,
            reason: '$s 는 진행도 격자에 있어야 한다');
      }
    });
  });

  group('resolveMergedStatus — NO_SHOW 터미널', () {
    test('미픽업은 진행 상태를 이긴다 — 폴링 stale 응답에 부활하지 않는다 (양방향)', () {
      // 실제 P0 시나리오: READY → 미픽업 직후 폴링이 stale READY 를 돌려준다.
      for (final other in [
        OrderStatus.NEW,
        OrderStatus.PREPARING,
        OrderStatus.READY,
        OrderStatus.DONE,
      ]) {
        expect(resolveMergedStatus(OrderStatus.NO_SHOW, other),
            OrderStatus.NO_SHOW,
            reason: 'local=미픽업 server=$other');
        expect(resolveMergedStatus(other, OrderStatus.NO_SHOW),
            OrderStatus.NO_SHOW,
            reason: 'local=$other server=미픽업');
      }
    });

    test('취소가 미픽업보다 강하다 — 환불 사실이 가려지면 안 된다 (양방향)', () {
      expect(
          resolveMergedStatus(OrderStatus.CANCELLED, OrderStatus.NO_SHOW),
          OrderStatus.CANCELLED);
      expect(
          resolveMergedStatus(OrderStatus.NO_SHOW, OrderStatus.CANCELLED),
          OrderStatus.CANCELLED);
    });

    test('교환법칙: 모든 쌍에서 f(a,b) == f(b,a)', () {
      // 폴링은 (local, server), 소켓은 (order.status, eventStatus) 로 부른다.
      // 인자 순서에 결과가 의존하면 두 경로가 서로를 덮어쓰며 화면이 깜빡인다.
      for (final a in OrderStatus.values) {
        for (final b in OrderStatus.values) {
          expect(resolveMergedStatus(a, b), resolveMergedStatus(b, a),
              reason: 'a=$a b=$b 에서 교환법칙이 깨졌다');
        }
      }
    });
  });

  group('서버 상태 문자열 매핑표', () {
    test('kServerOrderStatus — 서버 어휘가 전부 매핑된다', () {
      expect(kServerOrderStatus['PENDING'], OrderStatus.NEW);
      expect(kServerOrderStatus['NEW'], OrderStatus.NEW);
      expect(kServerOrderStatus['ACCEPTED'], OrderStatus.PREPARING);
      expect(kServerOrderStatus['PREPARING'], OrderStatus.PREPARING);
      expect(kServerOrderStatus['READY'], OrderStatus.READY);
      expect(kServerOrderStatus['PICKUP_REQUESTED'], OrderStatus.READY);
      expect(kServerOrderStatus['DONE'], OrderStatus.DONE);
      expect(kServerOrderStatus['COMPLETED'], OrderStatus.DONE);
      expect(kServerOrderStatus['CANCELED'], OrderStatus.CANCELLED);
      expect(kServerOrderStatus['CANCELLED'], OrderStatus.CANCELLED);
      expect(kServerOrderStatus['FAILED'], OrderStatus.CANCELLED);
    });

    test('미픽업 가칭 별칭이 전부 NO_SHOW 으로 매핑된다', () {
      // 서버 스펙 확정 전 방어. 별칭이 빠지면 미픽업이 '취소' 로 보인다.
      for (final alias in kNoShowServerAliases) {
        expect(kServerOrderStatus[alias], OrderStatus.NO_SHOW,
            reason: '별칭 $alias 가 매핑표에 없다');
      }
      expect(kNoShowServerAliases, contains(kNoShowServerStatus));
    });

    test('orderStatusToServer 는 매핑표로 왕복한다', () {
      for (final s in OrderStatus.values) {
        expect(kServerOrderStatus[orderStatusToServer(s)], s,
            reason: '$s 의 대표 문자열이 매핑표에서 자기 자신으로 돌아오지 않는다');
      }
    });
  });
}
