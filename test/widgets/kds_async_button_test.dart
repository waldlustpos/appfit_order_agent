import 'dart:async';

import 'package:appfit_order_agent/widgets/kds/kds_async_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// KdsAsyncButton 재진입 가드 검증.
///
/// 배경(2026-08-08 에뮬레이터 실검증에서 발견): 스피너 진행 중 재탭이 확인
/// 다이얼로그를 다시 띄웠다. `_busy` 는 State 로컬이라 **부모가 서브트리를
/// 조건부로 교체하면(State 재생성) 리셋**된다 — KDS 카드는 실제로
/// `isDetailLoaded`/`kdsOrderType` 에 따라 Simple/Scrollable 트리를 통째로
/// 갈아끼우고 하단 버튼도 `if (isDetailLoaded)` 조건부다.
///
/// 그래서 가드는 두 층이다:
/// - 로컬 `_busy` — 정상 수명주기에서의 1차 방어
/// - [KdsAsyncButton.externalBusy] — provider 가 준 주문별 in-flight 상태.
///   State 가 몇 번 재생성되든 진실은 provider 에 있으므로 관통이 불가능하다.
void main() {
  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(body: Center(child: SizedBox(width: 200, child: child))),
      );

  group('로컬 _busy 가드 (정상 수명주기)', () {
    testWidgets('진행 중 재탭은 onPressed 를 다시 부르지 않는다', (tester) async {
      var calls = 0;
      final gate = Completer<void>();
      await tester.pumpWidget(wrap(KdsAsyncButton(
        text: '픽업 요청',
        style: ElevatedButton.styleFrom(),
        onPressed: () async {
          calls++;
          await gate.future;
        },
      )));

      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();
      expect(calls, 1);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // 스피너 중 재탭 — AbsorbPointer 가 흡수해야 한다.
      await tester.tap(find.byType(ElevatedButton), warnIfMissed: false);
      await tester.pump();
      await tester.tap(find.byType(ElevatedButton), warnIfMissed: false);
      await tester.pump();
      expect(calls, 1, reason: '재탭이 관통하면 안 된다');

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('픽업 요청'), findsOneWidget);
    });

    testWidgets('완료 후 다시 탭할 수 있다 (순차 재시도 허용)', (tester) async {
      var calls = 0;
      await tester.pumpWidget(wrap(KdsAsyncButton(
        text: '픽업 요청',
        style: ElevatedButton.styleFrom(),
        onPressed: () async => calls++,
      )));

      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();
      expect(calls, 2);
    });
  });

  group('State 재생성 관통 (에뮬레이터 실검증에서 발견된 버그의 재현)', () {
    /// 부모가 버튼 서브트리를 조건부로 제거했다 되살리는 상황을 재현한다.
    /// KDS 카드의 `if (order.isDetailLoaded) _buildBottomButtons(...)` 와
    /// Simple↔Scrollable 트리 교체가 정확히 이 모양이다.
    Widget host({
      required bool showButton,
      required bool externalBusy,
      required Future<void> Function() onPressed,
    }) =>
        wrap(Column(children: [
          if (showButton)
            KdsAsyncButton(
              text: '픽업 요청',
              style: ElevatedButton.styleFrom(),
              externalBusy: externalBusy,
              onPressed: onPressed,
            ),
        ]));

    testWidgets('externalBusy 없이는 State 재생성 후 재탭이 관통한다 (버그 문서화)',
        (tester) async {
      var calls = 0;
      final gate = Completer<void>();
      Future<void> action() async {
        calls++;
        await gate.future;
      }

      // 탭 → 진행 중
      await tester.pumpWidget(
          host(showButton: true, externalBusy: false, onPressed: action));
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();
      expect(calls, 1);

      // 부모가 서브트리를 제거했다 되살림 → State 재생성, _busy 소실
      await tester.pumpWidget(
          host(showButton: false, externalBusy: false, onPressed: action));
      await tester.pumpWidget(
          host(showButton: true, externalBusy: false, onPressed: action));

      // 재탭 — 로컬 가드만으로는 막을 수 없다 (이게 실기기에서 본 관통)
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();
      expect(calls, 2, reason: '로컬 _busy 만으로는 State 재생성 관통을 못 막는다');

      gate.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('externalBusy(provider in-flight)가 있으면 재생성 후에도 차단된다',
        (tester) async {
      var calls = 0;
      final gate = Completer<void>();
      Future<void> action() async {
        calls++;
        await gate.future;
      }

      await tester.pumpWidget(
          host(showButton: true, externalBusy: false, onPressed: action));
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();
      expect(calls, 1);

      // in-flight 시작이 provider 에 반영됐다고 가정(externalBusy=true) —
      // 그 상태에서 서브트리 재생성.
      await tester.pumpWidget(
          host(showButton: false, externalBusy: true, onPressed: action));
      await tester.pumpWidget(
          host(showButton: true, externalBusy: true, onPressed: action));

      // 재생성된 State 의 _busy 는 false 지만 externalBusy 가 막는다.
      await tester.tap(find.byType(ElevatedButton), warnIfMissed: false);
      await tester.pump();
      expect(calls, 1, reason: 'provider 가 진실이면 State 재생성과 무관하게 차단');

      // 스피너도 유지 — 사용자에게는 진행 중으로 보인다.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // in-flight 해제 → 버튼 복귀 → 순차 재시도 가능.
      gate.complete();
      await tester.pumpWidget(
          host(showButton: true, externalBusy: false, onPressed: action));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();
      expect(calls, 2);
      gate.complete;
      await tester.pumpAndSettle();
    });
  });
}
