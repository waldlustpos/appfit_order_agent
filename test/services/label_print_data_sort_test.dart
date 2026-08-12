import 'package:appfit_order_agent/models/menu_option_model.dart';
import 'package:appfit_order_agent/models/order_menu_model.dart';
import 'package:appfit_order_agent/models/order_model.dart';
import 'package:appfit_order_agent/models/product_model.dart';
import 'package:appfit_order_agent/services/label_printer/fast_menu_policy.dart';
import 'package:appfit_order_agent/services/label_printer/label_filter_strategy.dart';
import 'package:appfit_order_agent/services/label_printer/label_print_data.dart';
import 'package:appfit_order_agent/services/label_printer/qr_payload_strategy.dart';
import 'package:flutter_test/flutter_test.dart';

OrderMenuModel _menu(String shopItemId, {int qty = 1}) => OrderMenuModel(
      orderNo: 'ORD1',
      shopItemId: shopItemId,
      qty: qty,
      itemName: shopItemId,
      itemPrice: 1000,
      totalAmount: 1000.0 * qty,
      discPrc: 0,
      vatPrc: 0,
      options: const <MenuOptionModel>[],
    );

OrderModel _order(List<OrderMenuModel> menus) => OrderModel(
      orderNo: 'ORD1',
      shopOrderNo: '0001',
      orderStatus: OrderStatus.PREPARING.name,
      orderedAt: DateTime.utc(2026, 1, 1, 9),
      totalAmount: 1000,
      status: OrderStatus.PREPARING,
      storeId: 'store-1',
      userId: 'user-1',
      ordererName: '홍길동',
      orderCount: '1',
      paymentAmount: 1000,
      discountAmount: 0,
      paymentType: 'CARD',
      paymentCode: 'CARD',
      menus: menus,
      orderType: 'T',
      kdsOrderType: 1,
      kioskId: 'kiosk-1',
      updateTime: DateTime.utc(2026, 1, 1, 9),
    );

const _fastIds = {'AMERICANO'};

FastMenuPolicy _policy(FastMenuMode mode, {bool showMarker = false}) =>
    FastMenuPolicy(mode: mode, showMarker: showMarker, fastIds: _fastIds);

void main() {
  group('LabelPrintData.fromOrder — 주문 내 빠른 메뉴 정렬', () {
    test('기본값(정책 미지정)은 종전 동작 — 원본 메뉴 순서 유지', () {
      final labels = LabelPrintData.fromOrder(
        _order([_menu('WAFFLE'), _menu('AMERICANO')]),
      );
      expect(labels.map((l) => l.menuName).toList(), ['WAFFLE', 'AMERICANO']);
      expect(labels.map((l) => l.orderIndex).toList(), [1, 2]);
    });

    test('빠른 메뉴가 먼저 인쇄된다', () {
      final labels = LabelPrintData.fromOrder(
        _order([_menu('WAFFLE'), _menu('AMERICANO')]),
        fastMenuPolicy: _policy(FastMenuMode.withinOrder),
      );
      expect(labels.map((l) => l.menuName).toList(), ['AMERICANO', 'WAFFLE']);
    });

    test('라벨 순번(cup index)은 정렬과 무관하게 원본 메뉴 순서로 채번된다', () {
      // 와플 1 + 아메리카노 2 → 와플=1, 아메리카노=2·3 이 원본 채번.
      // 정렬은 인쇄 순서만 바꾸므로 아메리카노가 2/3, 3/3 을 **달고** 먼저 나온다.
      //
      // 이 값은 인쇄 카운터가 아니라 컵의 고유 식별자다 — QR 로 스캔해 서버
      // 데이터와 대조하므로 출력 편의 때문에 흔들리면 안 된다.
      final labels = LabelPrintData.fromOrder(
        _order([_menu('WAFFLE'), _menu('AMERICANO', qty: 2)]),
        fastMenuPolicy: _policy(FastMenuMode.withinOrder),
      );
      expect(labels.map((l) => l.menuName).toList(),
          ['AMERICANO', 'AMERICANO', 'WAFFLE']);
      expect(labels.map((l) => l.orderIndex).toList(), [2, 3, 1]);
      expect(labels.every((l) => l.orderTotal == 3), isTrue);
    });

    test('메뉴↔순번 대응이 정렬 전후 완전히 동일하다', () {
      final order = _order([
        _menu('WAFFLE'),
        _menu('AMERICANO', qty: 2),
        _menu('CAKE'),
      ]);
      // (메뉴명, 순번) 쌍이 집합으로 같아야 한다 — 순서만 다르고 채번은 불변.
      Set<String> pairs(List<LabelPrintData> l) =>
          l.map((e) => '${e.menuName}#${e.orderIndex}').toSet();

      expect(
        pairs(LabelPrintData.fromOrder(order,
            fastMenuPolicy: _policy(FastMenuMode.withinOrder))),
        pairs(LabelPrintData.fromOrder(order)),
      );
    });

    test('총 라벨 매수(orderTotal)는 정렬과 무관하다', () {
      final order = _order([_menu('WAFFLE', qty: 2), _menu('AMERICANO')]);
      final plain = LabelPrintData.fromOrder(order);
      final sorted = LabelPrintData.fromOrder(order,
          fastMenuPolicy: _policy(FastMenuMode.withinOrder));
      expect(sorted.length, plain.length);
      expect(sorted.first.orderTotal, plain.first.orderTotal);
    });

    test('운영 QR 전략(Default)의 페이로드는 정렬 전후 동일한 집합이다', () {
      // DefaultQrPayloadStrategy 는 labelSeq(메뉴 내 순번) + shopItemId 기반이라
      // 메뉴 순서와 독립이어야 한다. 최근 cupIdx 충돌 사고 영역의 회귀 고정.
      final order = _order([_menu('WAFFLE'), _menu('AMERICANO', qty: 2)]);
      Set<String?> payloads(List<LabelPrintData> l) =>
          l.map((e) => e.qrData).toSet();

      expect(
        payloads(LabelPrintData.fromOrder(order,
            fastMenuPolicy: _policy(FastMenuMode.withinOrder))),
        payloads(LabelPrintData.fromOrder(order)),
      );
    });

    test('운영 기본 QR 포맷(신규)에서도 메뉴별 페이로드가 정렬 전후 동일하다', () {
      // `getLabelQrPayloadFormat()` 기본값이 1(신규)이라 이 전략이 운영 기본이다.
      // cupIdx = labelIndex - 1 로 라벨 순번을 직접 쓰므로, 정렬이 채번을 건드리면
      // 여기서 바로 깨진다 — 서버 대조가 어긋나는 사고의 회귀 고정선.
      final order = _order([_menu('WAFFLE'), _menu('AMERICANO', qty: 2)]);
      Map<String, String?> byMenuAndSeq(List<LabelPrintData> l) => {
            for (final e in l) '${e.menuName}#${e.menuInfo!.labelSeq}': e.qrData
          };

      final sorted = LabelPrintData.fromOrder(
        order,
        qrStrategy: const DisplayNumIndexQrPayloadStrategy(),
        fastMenuPolicy: _policy(FastMenuMode.withinOrder),
      );
      final plain = LabelPrintData.fromOrder(
        order,
        qrStrategy: const DisplayNumIndexQrPayloadStrategy(),
      );

      expect(byMenuAndSeq(sorted), byMenuAndSeq(plain));
      // 라벨마다 유일해야 한다는 성질도 함께 유지.
      expect(sorted.map((l) => l.qrData).toSet().length, sorted.length);
    });

    test('isFastMenu 플래그는 모드와 무관하게 지정 여부를 따른다', () {
      // 표시만 켜고 순서는 안 바꾸는 운용을 지원해야 한다.
      final labels = LabelPrintData.fromOrder(
        _order([_menu('WAFFLE'), _menu('AMERICANO')]),
        fastMenuPolicy: _policy(FastMenuMode.off, showMarker: true),
      );
      expect(labels.map((l) => l.menuName).toList(), ['WAFFLE', 'AMERICANO']);
      expect(labels.map((l) => l.isFastMenu).toList(), [false, true]);
    });
  });

  group('브랜드 카테고리 필터와의 상호작용', () {
    ProductModel product(String id, String categoryCode) => ProductModel(
          productId: id,
          productName: id,
          categoryName: categoryCode,
          categoryCode: categoryCode,
          menuPrice: 1000,
          status: ProductStatus.sale,
          type: ProductType.item,
          internalId: 'internal-$id',
          displayOrder: 0,
        );

    // TKP1006 = 와플 카테고리, 그 외는 비와플.
    final products = [
      product('WAFFLE', 'TKP1006'),
      product('AMERICANO', 'TKP9999'),
      product('LATTE', 'TKP9999'),
    ];

    test('필터가 걸려도 정렬은 인쇄 순서만 바꾸고 순번은 원본 채번을 유지한다', () {
      final labels = LabelPrintData.fromOrder(
        _order([_menu('WAFFLE'), _menu('LATTE'), _menu('AMERICANO')]),
        products: products,
        strategy: const TpcpLabelFilterStrategy(),
        filterMode: 2, // 와플 제외
        fastMenuPolicy: _policy(FastMenuMode.withinOrder),
      );

      // 인쇄 순서: 빠른 메뉴 먼저.
      expect(labels.map((l) => l.menuName).toList(), ['AMERICANO', 'LATTE']);
      // 순번: 원본 순서(WAFFLE=1, LATTE=2, AMERICANO=3) 그대로 — 필터로 빠진
      // 와플의 1번도 그대로 비워 둔다.
      expect(labels.map((l) => l.orderIndex).toList(), [3, 2]);
      // 전체 매수는 필터와 무관하게 주문 전체 기준(기존 동작 보존).
      expect(labels.first.orderTotal, 3);
    });
  });
}
