import 'package:appfit_order_agent/i18n/strings.g.dart';
import 'package:appfit_order_agent/models/membership_model.dart';
import 'package:appfit_order_agent/widgets/membership/stamp_history_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 스탬프내역 카드의 **조회 전용 모드** 고정.
///
/// 스탬프 적립이 차단된 매장(2차 브랜드)에서도 스탬프내역 탭은 열린다 — 조회는
/// 아무것도 바꾸지 않기 때문이다. 대신 그 매장 단말이 남의 매장 적립을 되돌리는
/// 일이 없도록 [적립취소] 버튼만 사라져야 한다. 화면은 `onCancel: null` 로 그
/// 상태를 표현하므로, 여기서 null ↔ 버튼 부재의 대응을 못 박는다.
void main() {
  StampInfo issued({bool isCancelable = true}) => StampInfo(
        logDate: DateTime(2026, 8, 30, 14, 5),
        stampCount: 3,
        status: 'ISSUED',
        memo: '',
        seq: '1',
        rewardId: 'rw-1',
        isCancelable: isCancelable,
      );

  Future<void> pumpCard(WidgetTester tester, {VoidCallback? onCancel}) async {
    await tester.pumpWidget(TranslationProvider(
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 420,
              child: StampHistoryCard(
                entry: StampHistoryEntry(primary: issued()),
                isLoading: false,
                onCancel: onCancel,
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('onCancel 이 null 이면 취소 버튼을 그리지 않는다 (적립 차단 매장)', (tester) async {
    await pumpCard(tester);

    expect(find.byType(ElevatedButton), findsNothing);
    // 내역 자체는 그대로 보여야 한다 — 숨기는 것은 취소 버튼뿐이다.
    expect(find.text('2026-08-30 14:05'), findsOneWidget);
    expect(find.text('+3'), findsOneWidget);
  });

  testWidgets('onCancel 이 있으면 취소 가능한 적립에 버튼이 뜬다 (적립 허용 매장)', (tester) async {
    var calls = 0;
    await pumpCard(tester, onCancel: () => calls++);

    expect(find.byType(ElevatedButton), findsOneWidget);
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    expect(calls, 1);
  });

  testWidgets('onCancel 이 있어도 isCancelable=false 면 버튼이 없다 (기존 규칙 유지)',
      (tester) async {
    await tester.pumpWidget(TranslationProvider(
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 420,
              child: StampHistoryCard(
                entry: StampHistoryEntry(primary: issued(isCancelable: false)),
                isLoading: false,
                onCancel: () {},
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(ElevatedButton), findsNothing);
  });
}
