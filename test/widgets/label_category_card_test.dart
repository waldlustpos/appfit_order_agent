import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:appfit_order_agent/widgets/settings/label_category_card.dart';

/// 라벨 출력 카테고리 카드의 **선택 표현**을 고정한다.
///
/// 이 화면은 카드를 탭해 다중 선택하는 유일한 화면이라, 선택 여부가 한눈에
/// 보이는 것 자체가 기능이다. 체크가 사라지거나 미선택 카드에까지 표식이 생기면
/// 점주는 무엇을 고른 상태인지 알 수 없다.
void main() {
  Future<void> pumpCard(
    WidgetTester tester, {
    required bool selected,
    String name = '커피',
    String? code = 'DX0000',
    VoidCallback? onTap,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 300,
            height: 112,
            child: LabelCategoryCard(
              name: name,
              code: code,
              selected: selected,
              onTap: onTap ?? () {},
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('선택되면 체크가 보이고, 미선택이면 아무 표식도 없다', (tester) async {
    await pumpCard(tester, selected: true);
    expect(find.byIcon(Icons.check), findsOneWidget);

    await pumpCard(tester, selected: false);
    expect(find.byIcon(Icons.check), findsNothing);
  });

  testWidgets('탭하면 onTap 이 호출된다 — 해제도 같은 탭이다', (tester) async {
    var taps = 0;
    await pumpCard(tester, selected: false, onTap: () => taps++);
    await tester.tap(find.byType(LabelCategoryCard));
    expect(taps, 1);

    await pumpCard(tester, selected: true, onTap: () => taps++);
    await tester.tap(find.byType(LabelCategoryCard));
    expect(taps, 2);
  });

  testWidgets('코드가 없으면 코드 줄을 그리지 않는다 (categoryPosId 미제공 매장)', (tester) async {
    await pumpCard(tester, selected: false, code: null);
    expect(find.text('커피'), findsOneWidget);
    expect(find.text('DX0000'), findsNothing);

    // 빈 문자열도 같다 — 서버가 `''` 로 내려주는 경우가 있다.
    await pumpCard(tester, selected: false, code: '');
    expect(find.textContaining('DX'), findsNothing);
  });

  testWidgets('선택 여부가 이름 영역 폭을 바꾸지 않는다 (탭할 때 글자가 밀리지 않는다)', (tester) async {
    await pumpCard(tester, selected: false);
    final unselectedWidth = tester.getSize(find.text('커피')).width;

    await pumpCard(tester, selected: true);
    final selectedWidth = tester.getSize(find.text('커피')).width;

    expect(selectedWidth, unselectedWidth);
  });

  testWidgets('긴 이름은 2줄까지 받고 넘치면 말줄임한다', (tester) async {
    await pumpCard(
      tester,
      selected: false,
      name: '아주 긴 카테고리 이름이 들어와도 카드 높이가 흔들리지 않아야 한다 정말로',
    );

    final text = tester.widget<Text>(find.byType(Text).first);
    expect(text.maxLines, 2);
    expect(text.overflow, TextOverflow.ellipsis);
    expect(tester.takeException(), isNull);
  });
}
