import 'package:appfit_order_agent/i18n/strings.g.dart';
import 'package:appfit_order_agent/models/order_model.dart';
import 'package:appfit_order_agent/widgets/order/order_payment_info_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 주문 상세 팝업 가운데 '결제 내역' 카드 검증.
///
/// 팝업 실측 제약(Dialog maxWidth 1000 / maxHeight 650, padding 24, Row flex
/// 3:2:2)에서 이 카드가 받는 폭은 약 263px, 높이는 약 490px 이다. 좁은 폭에서
/// 수단명 + 금액이 한 줄에 들어가야 하므로 그 제약을 그대로 재현해
/// 오버플로가 없는지까지 확인한다.
OrderModel _order({
  double totalAmount = 12000,
  double discountAmount = 2000,
  double paymentAmount = 10000,
  List<OrderPaymentModel> payments = const [],
  List<OrderDiscountModel> discounts = const [],
}) {
  return OrderModel(
    orderNo: 'ORD-1',
    shopOrderNo: '42',
    orderStatus: 'NEW',
    orderedAt: DateTime(2026, 8, 10, 14, 32),
    totalAmount: totalAmount,
    status: OrderStatus.NEW,
    storeId: 'TPCP00001',
    userId: 'u-1',
    ordererName: '아메리카노 외 1건',
    orderCount: '2',
    paymentAmount: paymentAmount,
    discountAmount: discountAmount,
    paymentType: 'MULTI',
    paymentCode: '1',
    menus: const [],
    orderType: 'TAKE_OUT',
    kdsOrderType: 0,
    kioskId: '',
    payments: payments,
    discounts: discounts,
  );
}

void main() {
  // 팝업에서 이 카드가 실제로 받는 제약.
  const cardWidth = 263.0;
  const cardHeight = 490.0;

  Future<void> pumpCard(WidgetTester tester, OrderModel order) async {
    await tester.pumpWidget(TranslationProvider(
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: cardWidth,
              height: cardHeight,
              child: OrderPaymentInfoWidget(
                order: order,
                currencySymbol: '원',
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// 정확한 위젯 하나의 Text 스타일을 꺼낸다.
  TextStyle styleOf(WidgetTester tester, Finder f) =>
      tester.widget<Text>(f).style!;

  group('금액 3줄 (기존 동작 유지)', () {
    testWidgets('결제수단 정보가 없어도 주문/할인/결제 금액은 그대로 나온다', (tester) async {
      await pumpCard(tester, _order());

      expect(find.text('주문금액'), findsOneWidget);
      expect(find.text('12,000원'), findsOneWidget);
      expect(find.text('할인금액'), findsOneWidget);
      expect(find.text('-2,000원'), findsOneWidget);
      expect(find.text('결제금액'), findsOneWidget);
      expect(find.text('10,000원'), findsOneWidget);
    });

    testWidgets('payments 가 비면 결제수단 섹션 자체를 숨긴다', (tester) async {
      await pumpCard(tester, _order());

      expect(find.text('결제수단'), findsNothing);
    });
  });

  group('결제수단별 금액', () {
    testWidgets('수단명과 금액을 건별로 표시한다', (tester) async {
      await pumpCard(
          tester,
          _order(payments: const [
            OrderPaymentModel(
                paymentMethod: 'CREDIT_CARD', amount: 7000, status: 'DONE'),
            OrderPaymentModel(
                paymentMethod: 'CASH', amount: 3000, status: 'DONE'),
          ]));

      expect(find.text('결제수단'), findsOneWidget);
      expect(find.text('신용카드'), findsOneWidget);
      expect(find.text('7,000원'), findsOneWidget);
      expect(find.text('현금'), findsOneWidget);
      expect(find.text('3,000원'), findsOneWidget);
      expect(find.text('2건'), findsOneWidget); // 2건 이상일 때만 건수 표시
    });

    testWidgets('1건일 때는 건수 배지를 표시하지 않는다', (tester) async {
      await pumpCard(
          tester,
          _order(payments: const [
            OrderPaymentModel(
                paymentMethod: 'CREDIT_CARD', amount: 10000, status: 'DONE'),
          ]));

      expect(find.text('신용카드'), findsOneWidget);
      expect(find.text('1건'), findsNothing);
    });

    testWidgets('미지의 수단 코드는 원문 그대로 노출한다', (tester) async {
      await pumpCard(
          tester,
          _order(payments: const [
            OrderPaymentModel(
                paymentMethod: 'SOME_NEW_PAY', amount: 10000, status: 'DONE'),
          ]));

      expect(find.text('SOME_NEW_PAY'), findsOneWidget);
    });
  });

  group('결제 상태는 표시하지 않는다', () {
    // 주문이 취소면 결제도 취소라는 전제가 성립하고, 주문 상태는 팝업 헤더의
    // 상태 배지가 이미 보여준다. 여기에 취소선·배지를 또 그리면 중복이다.
    testWidgets('취소된 결제 건도 정상 건과 똑같이 표시한다', (tester) async {
      await pumpCard(
          tester,
          _order(payments: const [
            OrderPaymentModel(
                paymentMethod: 'CREDIT_CARD',
                amount: 3000,
                status: 'FULL_CANCELLED'),
            OrderPaymentModel(
                paymentMethod: 'CASH', amount: 10000, status: 'DONE'),
          ]));

      expect(find.text('신용카드'), findsOneWidget);
      expect(find.text('3,000원'), findsOneWidget);
      expect(find.text('취소'), findsNothing);
      expect(styleOf(tester, find.text('신용카드')).decoration, isNull);
      // 정상 건과 색까지 동일해야 한다 (dim 처리 제거)
      expect(styleOf(tester, find.text('신용카드')).color,
          styleOf(tester, find.text('현금')).color);
    });

    testWidgets('실패·대기 상태도 배지를 붙이지 않는다', (tester) async {
      await pumpCard(
          tester,
          _order(payments: const [
            OrderPaymentModel(
                paymentMethod: 'CREDIT_CARD', amount: 5000, status: 'FAILED'),
            OrderPaymentModel(
                paymentMethod: 'CASH', amount: 5000, status: 'PENDING'),
          ]));

      expect(find.text('실패'), findsNothing);
      expect(find.text('대기'), findsNothing);
      expect(styleOf(tester, find.text('신용카드')).decoration, isNull);
    });
  });

  group('카드 상세는 표시하지 않는다', () {
    testWidgets('카드사·카드번호·할부·잔액을 렌더하지 않는다', (tester) async {
      await pumpCard(
          tester,
          _order(payments: const [
            OrderPaymentModel(
              paymentMethod: 'CREDIT_CARD',
              amount: 7000,
              status: 'DONE',
              cardName: '신한',
              cardNo: '5327-****',
              installment: 3,
            ),
            OrderPaymentModel(
              paymentMethod: 'PREPAID_CARD',
              amount: 3000,
              status: 'DONE',
              balance: 12000,
            ),
          ]));

      expect(find.textContaining('신한'), findsNothing);
      expect(find.textContaining('5327'), findsNothing);
      expect(find.textContaining('3개월'), findsNothing);
      expect(find.textContaining('잔액'), findsNothing);
      // 수단명과 금액은 그대로
      expect(find.text('신용카드'), findsOneWidget);
      expect(find.text('7,000원'), findsOneWidget);
      expect(find.text('선불카드'), findsOneWidget);
    });
  });

  group('0원 결제 건', () {
    testWidgets('금액이 0인 건은 숨긴다 (할인 행에서 이미 드러남)', (tester) async {
      await pumpCard(
          tester,
          _order(
            payments: const [
              OrderPaymentModel(
                  paymentMethod: 'FREE', amount: 0, status: 'DONE'),
            ],
            discounts: const [
              OrderDiscountModel(
                  discountType: 'COUPON',
                  discountAmount: 12000,
                  discountScope: 'ORDER'),
            ],
          ));

      expect(find.text('무료'), findsNothing);
      expect(find.text('결제수단'), findsNothing); // 볼 게 없으면 섹션째 숨김
      expect(find.text('쿠폰'), findsOneWidget); // 할인은 그대로
    });

    testWidgets('0원 건이 섞여 있으면 그 행만 빼고 건수도 다시 센다', (tester) async {
      await pumpCard(
          tester,
          _order(payments: const [
            OrderPaymentModel(paymentMethod: 'FREE', amount: 0, status: 'DONE'),
            OrderPaymentModel(
                paymentMethod: 'CREDIT_CARD', amount: 7000, status: 'DONE'),
            OrderPaymentModel(
                paymentMethod: 'CASH', amount: 3000, status: 'DONE'),
          ]));

      expect(find.text('무료'), findsNothing);
      expect(find.text('신용카드'), findsOneWidget);
      expect(find.text('현금'), findsOneWidget);
      expect(find.text('2건'), findsOneWidget); // 3건이 아니라 2건
    });

    testWidgets('금액이 있는 FREE 건은 그대로 보여준다', (tester) async {
      await pumpCard(
          tester,
          _order(payments: const [
            OrderPaymentModel(
                paymentMethod: 'FREE', amount: 10000, status: 'DONE'),
          ]));

      expect(find.text('무료'), findsOneWidget);
      // 상단 '결제금액' 헤드라인과 이 행이 같은 금액이라 2건이 정상.
      expect(find.text('10,000원'), findsNWidgets(2));
    });
  });

  group('할인 종류별 금액', () {
    testWidgets('할인 상세를 종류·쿠폰명과 함께 나열한다', (tester) async {
      await pumpCard(
          tester,
          _order(discounts: const [
            OrderDiscountModel(
              discountType: 'COUPON',
              discountAmount: 1000,
              discountScope: 'ORDER',
              couponName: '1,000원 할인권',
            ),
            OrderDiscountModel(
                discountType: 'POINT',
                discountAmount: 1000,
                discountScope: 'ORDER'),
          ]));

      expect(find.text('쿠폰 (1,000원 할인권)'), findsOneWidget);
      expect(find.text('포인트'), findsOneWidget);
      expect(find.text('-1,000원'), findsNWidgets(2));
    });
  });

  group('좁은 카드 폭에서의 오버플로', () {
    testWidgets('결제 6건 + 할인 3건이어도 오버플로 없이 스크롤된다', (tester) async {
      await pumpCard(
          tester,
          _order(
            payments: List.generate(
              6,
              (i) => OrderPaymentModel(
                paymentMethod: 'CREDIT_CARD',
                amount: 1000 + i * 100,
                status: 'DONE',
                cardName: '신한카드',
                cardNo: '5327-****',
                installment: 0,
              ),
            ),
            discounts: List.generate(
              3,
              (i) => OrderDiscountModel(
                discountType: 'COUPON',
                discountAmount: 500,
                discountScope: 'ORDER',
                couponName: '아주 긴 이름의 할인 쿠폰 $i',
              ),
            ),
          ));

      expect(tester.takeException(), isNull);
      expect(find.byType(Scrollable), findsWidgets);
    });

    testWidgets('아주 긴 수단명도 ellipsis 로 잘려 오버플로를 내지 않는다', (tester) async {
      await pumpCard(
          tester,
          _order(payments: const [
            OrderPaymentModel(
              paymentMethod: '엄청나게 길어서 한 줄에 절대 들어가지 않는 결제 수단 이름입니다',
              amount: 10000,
              status: 'FULL_CANCELLED',
            ),
          ]));

      expect(tester.takeException(), isNull);
    });
  });
}
