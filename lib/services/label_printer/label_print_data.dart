// 라벨 출력에 필요한 모델-중립 DTO.
//
// LabelPainter 와 LabelPrintOrchestrator 는 이 DTO 만 알면 되고,
// OrderModel 어댑터에서 변환해 넣어준다.

import 'package:intl/intl.dart';
import 'package:appfit_order_agent/models/order_model.dart';

class LabelPrintData {
  const LabelPrintData({
    required this.menuName,
    required this.options,
    required this.orderIndex,
    required this.orderTotal,
    this.shopOrderNo,
    this.orderTime,
    this.beanType,
    this.temperature,
    this.sizeOption,
    this.memo,
    this.qrData,
    this.showDetailQr = false,
  });

  final String menuName;
  final List<String> options;

  /// 주문번호 (예: "0795"). 라벨에 큼지막하게 출력.
  final String? shopOrderNo;

  /// "MM/dd\nHH:mm:ss" 포맷 권장.
  final String? orderTime;

  /// sub-info 영역 (원두/온도/사이즈). kokonut 은 분류 룰이 없어 항상 null.
  final String? beanType;
  final String? temperature;
  final String? sizeOption;

  final String? memo;

  /// detail 영역 QR. kokonut 은 사용 안 함.
  final String? qrData;
  final bool showDetailQr;

  /// 한 주문 묶음 안에서 1부터 시작하는 누적 인덱스 (예: 1, 2, 3, 4 ...).
  final int orderIndex;

  /// 같은 묶음의 전체 라벨 매수.
  final int orderTotal;

  /// appfit [OrderModel] 을 라벨 묶음(메뉴 1개당 qty 장 반복) 으로 변환.
  ///
  /// 단순 매핑 — 옵션 분류 (원두/온도/사이즈), TPCP 매장 카테고리 필터링은
  /// product 카탈로그가 필요한 비즈니스 로직이라 OutputService 측에서 처리.
  /// 이 어댑터는 분류 없이 옵션 리스트를 그대로 평면화한다.
  /// - 옵션 수량 > 1 인 경우 "n 옵션명" 형태로 prefix.
  static List<LabelPrintData> fromOrder(OrderModel order) {
    final totalLabels =
        order.menus.fold<int>(0, (sum, menu) => sum + menu.qty);
    if (totalLabels == 0) return const [];

    final timeStr = DateFormat('MM/dd\nHH:mm:ss').format(order.orderedAt);
    final shopOrderNo =
        order.displayNum.isNotEmpty ? order.displayNum : order.shopOrderNo;

    final result = <LabelPrintData>[];
    int running = 0;
    for (final menu in order.menus) {
      final options = menu.options
          .map((opt) => opt.qty > 1
              ? '${opt.qty} ${opt.optionName}'
              : opt.optionName)
          .where((name) => name.isNotEmpty)
          .toList();

      for (int i = 0; i < menu.qty; i++) {
        running += 1;
        result.add(LabelPrintData(
          menuName: menu.itemName,
          options: options,
          shopOrderNo: shopOrderNo.isNotEmpty ? shopOrderNo : null,
          orderTime: timeStr,
          memo: order.note,
          orderIndex: running,
          orderTotal: totalLabels,
        ));
      }
    }
    return result;
  }

  /// 테스트 인쇄용 더미 데이터.
  static LabelPrintData testSample() {
    return LabelPrintData(
      menuName: '테스트 메뉴',
      options: const ['옵션 A', '옵션 B'],
      shopOrderNo: '0001',
      orderTime: DateFormat('MM/dd\nHH:mm:ss').format(DateTime.now()),
      memo: '라벨 프린터 테스트 인쇄',
      orderIndex: 1,
      orderTotal: 1,
    );
  }
}
