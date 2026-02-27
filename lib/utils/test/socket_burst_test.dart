import 'package:kokonut_order_agent/models/order_model.dart';
import 'package:kokonut_order_agent/models/order_menu_model.dart';
import 'package:kokonut_order_agent/models/menu_option_model.dart';
import 'package:kokonut_order_agent/core/orders/order_queue_service.dart';
import 'package:kokonut_order_agent/utils/logger.dart';

/// 주문 폭주 시뮬레이션 테스트 유틸리티
class SocketBurstTest {
  // WidgetRef와 Ref 모두 대응하기 위해 dynamic 사용
  final dynamic ref;

  SocketBurstTest(this.ref);

  /// N개의 주문을 M초 동안 무작위 순서로 주입
  void simulateBurst(
      {int count = 10,
      Duration duration = const Duration(milliseconds: 1000)}) async {
    logger.w('[TEST] 주문 폭주 시뮬레이션 시작: $count건');

    final now = DateTime.now();

    // 1. 테스트용 주문 생성
    List<OrderModel> testOrders = List.generate(count, (index) {
      final orderNum = 101 + index;
      final orderNo = 'TEST_${now.millisecondsSinceEpoch}_$orderNum';

      // 실제 데이터 기반 메뉴 구성
      final menus = [
        OrderMenuModel(
          orderNo: orderNo,
          shopItemId: 'TKP0003',
          qty: 1,
          itemName: 'アメリカーノ',
          itemPrice: 280.0,
          totalAmount: 454.0,
          discPrc: 0.0,
          vatPrc: 41.0,
          options: [
            MenuOptionModel(
              shopOptionId: 'TKP0017',
              optionName: 'ホ이ップクリーム追加',
              optionPrice: 50.0,
              qty: 1,
            ),
            MenuOptionModel(
              shopOptionId: 'TEST0003',
              optionName: '마이그레이션 테스트-옵션(2)',
              optionPrice: 124.0,
              qty: 1,
            ),
          ],
        )
      ];

      return OrderModel(
        orderNo: orderNo,
        shopOrderNo: orderNum.toString(),
        orderStatus: 'NEW', // AppFit string format
        orderedAt: now,
        totalAmount: 454.0,
        status: OrderStatus.NEW,
        storeId: 'TPCP00001',
        userId: '0p55f21bazrcc',
        userName: '', // userNickname was empty in example
        tel: '01062947151',
        ordererName: 'アメリカーノ 1개',
        orderCount: '1',
        paymentAmount: 454.0,
        discountAmount: 0.0,
        paymentType: 'CREDIT_CARD',
        paymentCode: 'CARD',
        menus: menus,
        orderType: 'T',
        kdsOrderType: 0,
        updateTime: now,
        kioskId: 'TEST_KIOSK',
      );
    });

    // 2. 순서 뒤섞기
    testOrders.shuffle();
    logger.d(
        '[TEST] 주문 순서 섞임: ${testOrders.map((e) => e.shopOrderNo).join(', ')}');

    // 3. 주입
    final interval = duration.inMilliseconds ~/ count;

    for (final order in testOrders) {
      ref.read(orderQueueAppServiceProvider).enqueueAll([order]);
      logger.d('[TEST] 주문 주입: ${order.shopOrderNo}');
      if (interval > 0) {
        await Future.delayed(Duration(milliseconds: interval));
      }
    }

    logger.w('[TEST] 모든 주문 주입 완료. UI 업데이트(0.5초 간격) 및 정렬(101->110) 확인 필요');
  }
}
