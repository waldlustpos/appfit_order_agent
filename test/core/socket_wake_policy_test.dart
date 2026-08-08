import 'package:appfit_core/appfit_core.dart' as appfit_core;
import 'package:appfit_order_agent/core/net/socket_wake_policy.dart';
import 'package:flutter_test/flutter_test.dart';

/// HTTP 회복 시 소켓을 깨울지 판정하는 정책 고정.
///
/// 이 정책이 존재하는 이유: 코어는 빠른 재연결 5회(93초) 실패 후 disconnected 를
/// 알리고 5분 간격 느린 재시도로 넘어간다. 링크는 살아있고 상위 경로만 죽는
/// 장애에서는 connectivity 이벤트가 오지 않아 코어가 그 5분 대기를 스스로
/// 앞당길 수 없다 — HTTP 회복이 앱만 아는 단축 신호다.
void main() {
  const all = appfit_core.ConnectionStatus.values;

  group('로그인 상태', () {
    test('disconnected 일 때만 깨운다', () {
      for (final status in all) {
        final expected = status == appfit_core.ConnectionStatus.disconnected;
        expect(
          shouldWakeSocket(status: status, isLoggedOut: false),
          expected,
          reason: '${status.name} → $expected 이어야 한다',
        );
      }
    });

    test('reconnecting 은 건드리지 않는다 (코어가 빠른 백오프 진행 중)', () {
      expect(
        shouldWakeSocket(
          status: appfit_core.ConnectionStatus.reconnecting,
          isLoggedOut: false,
        ),
        isFalse,
        reason: '재연결 중 간섭은 코어 백오프를 방해한다',
      );
    });

    test('이미 연결된 상태는 깨울 대상이 아니다', () {
      for (final status in all.where((s) => s.isConnected)) {
        expect(shouldWakeSocket(status: status, isLoggedOut: false), isFalse);
      }
    });
  });

  group('로그아웃 상태', () {
    test('어떤 상태에서도 깨우지 않는다', () {
      for (final status in all) {
        expect(
          shouldWakeSocket(status: status, isLoggedOut: true),
          isFalse,
          reason: 'disconnected 는 의도적 종료(로그아웃)에서도 나온다 — '
              '${status.name} 에서 재연결하면 로그아웃을 되돌리는 꼴',
        );
      }
    });
  });
}
