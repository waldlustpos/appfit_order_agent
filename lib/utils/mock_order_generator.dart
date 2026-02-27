import 'dart:math';
import 'package:kokonut_order_agent/models/order_model.dart';
import 'package:kokonut_order_agent/models/order_menu_model.dart';

/// 테스트용 가상 주문 생성기
class MockOrderGenerator {
  static final Random _random = Random();
  static int _lastOrderNum = 1000;

  /// 지정된 수만큼의 가짜 주문 데이터를 생성하여 리턴합니다.
  static List<OrderModel> generateMockOrders(int count) {
    final List<OrderModel> mockOrders = [];
    final now = DateTime.now();

    for (int i = 0; i < count; i++) {
      _lastOrderNum++;
      final String orderNo =
          'MOCK_${now.millisecondsSinceEpoch}_$_lastOrderNum';
      final String shopOrderNo = _lastOrderNum.toString();

      // 약간의 시간차를 두어 orderedAt 생성 (순차적 느낌 부여)
      final DateTime orderedAt = now.add(Duration(seconds: i));

      // 가짜 메뉴 1개 생성
      final mockMenu = OrderMenuModel(
        orderNo: orderNo,
        shopItemId: 'PROD_001',
        itemName: '테스트 아메리카노 (MOCK)',
        itemPrice: 4500,
        qty: 1,
        totalAmount: 4500,
        options: [], // 복잡성을 줄이기 위해 빈 옵션
        discPrc: 0.0,
        vatPrc: 409.0, // 4500 * (10/110)
      );

      final mockOrder = OrderModel(
        orderNo: orderNo,
        shopOrderNo: shopOrderNo,
        orderStatus: '2003', // NEW (api response style)
        orderedAt: orderedAt,
        totalAmount: 4500,
        status: OrderStatus.NEW,
        storeId: 'MOCK_STORE',
        userId: 'MOCK_USER',
        ordererName: mockMenu.itemName,
        orderCount: '1',
        paymentAmount: 4500.0,
        discountAmount: 0.0,
        paymentType: 'CARD',
        paymentCode: '01',
        menus: [mockMenu],
        orderType: 'T', // 포장
        kdsOrderType: 1,
        kioskId: 'MOCK_KIOSK',
        updateTime: orderedAt,
        isDetailLoaded: true,
      );

      mockOrders.add(mockOrder);
    }

    return mockOrders;
  }
}
