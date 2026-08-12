import 'package:appfit_order_agent/models/order_menu_model.dart';
import 'package:appfit_order_agent/models/order_model.dart';
import 'package:appfit_order_agent/services/label_printer/fast_menu_policy.dart';
import 'package:flutter_test/flutter_test.dart';

OrderMenuModel _menu(String shopItemId) => OrderMenuModel(
      orderNo: 'o1',
      shopItemId: shopItemId,
      qty: 1,
      itemName: shopItemId,
      itemPrice: 1000,
      totalAmount: 1000,
      discPrc: 0,
      vatPrc: 0,
      options: const [],
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

FastMenuPolicy _policy(
  FastMenuMode mode, {
  Set<String> fastIds = const {'AMERICANO'},
  bool showMarker = false,
}) =>
    FastMenuPolicy(mode: mode, showMarker: showMarker, fastIds: fastIds);

void main() {
  group('FastMenuMode.fromInt', () {
    test('저장값 → 모드 매핑', () {
      expect(FastMenuMode.fromInt(0), FastMenuMode.off);
      expect(FastMenuMode.fromInt(1), FastMenuMode.withinOrder);
      expect(FastMenuMode.fromInt(2), FastMenuMode.acrossOrders);
    });

    test('알 수 없는 값은 off 로 흡수한다 (설정 손상 시 종전 동작)', () {
      expect(FastMenuMode.fromInt(-1), FastMenuMode.off);
      expect(FastMenuMode.fromInt(99), FastMenuMode.off);
    });

    test('모드별 활성 축', () {
      expect(FastMenuMode.off.sortsWithinOrder, isFalse);
      expect(FastMenuMode.off.overtakesQueue, isFalse);
      expect(FastMenuMode.withinOrder.sortsWithinOrder, isTrue);
      expect(FastMenuMode.withinOrder.overtakesQueue, isFalse);
      expect(FastMenuMode.acrossOrders.sortsWithinOrder, isTrue);
      expect(FastMenuMode.acrossOrders.overtakesQueue, isTrue);
    });
  });

  group('isFast — 순수 멤버십 (모드와 독립)', () {
    test('모드가 꺼져 있어도 지정 여부는 판정한다 (표시 전용 운용)', () {
      final policy = _policy(FastMenuMode.off);
      expect(policy.isFast(_menu('AMERICANO')), isTrue);
      expect(policy.isFast(_menu('WAFFLE')), isFalse);
    });

    test('productId / internalId 어느 쪽으로 와도 매칭된다', () {
      // 설정 저장이 상품당 ID 2개를 담기 때문에 성립하는 성질.
      final policy =
          _policy(FastMenuMode.withinOrder, fastIds: {'AME', 'internal-AME'});
      expect(policy.isFast(_menu('AME')), isTrue);
      expect(policy.isFast(_menu('internal-AME')), isTrue);
    });
  });

  group('isFastOrder — 주문 간 추월 대상', () {
    test('전량 빠른 메뉴 주문만 대상', () {
      final policy = _policy(FastMenuMode.acrossOrders);
      expect(policy.isFastOrder(_order([_menu('AMERICANO')])), isTrue);
      expect(
        policy.isFastOrder(_order([_menu('AMERICANO'), _menu('AMERICANO')])),
        isTrue,
      );
    });

    test('혼합 주문은 제외 — 느린 메뉴가 어차피 그 주문을 막는다', () {
      final policy = _policy(FastMenuMode.acrossOrders);
      expect(
        policy.isFastOrder(_order([_menu('AMERICANO'), _menu('WAFFLE')])),
        isFalse,
      );
    });

    test('메뉴가 비어 있으면(상세 미로드) 판정 불가 → 일반 취급', () {
      final policy = _policy(FastMenuMode.acrossOrders);
      expect(policy.isFastOrder(_order(const [])), isFalse);
    });

    test('모드 1(주문 내 정렬)에서는 추월하지 않는다', () {
      final policy = _policy(FastMenuMode.withinOrder);
      expect(policy.isFastOrder(_order([_menu('AMERICANO')])), isFalse);
    });

    test('지정 상품이 하나도 없으면 추월하지 않는다', () {
      final policy = _policy(FastMenuMode.acrossOrders, fastIds: const {});
      expect(policy.isFastOrder(_order([_menu('AMERICANO')])), isFalse);
    });
  });

  group('sortFastFirst — 안정 정렬', () {
    test('빠른 메뉴가 앞으로, 각 부류 안에서는 원본 순서 유지', () {
      final policy = _policy(FastMenuMode.withinOrder);
      final menus = [
        _menu('WAFFLE'),
        _menu('AMERICANO'),
        _menu('CAKE'),
        _menu('AMERICANO'),
      ];
      final sorted = policy.sortFastFirst(menus);
      // 느린 메뉴 쪽도 원본 순서(WAFFLE → CAKE)가 보존되어야 한다.
      expect(sorted.map((m) => m.shopItemId).toList(),
          ['AMERICANO', 'AMERICANO', 'WAFFLE', 'CAKE']);
    });

    test('모드 off 면 원본을 그대로 돌려준다', () {
      final policy = _policy(FastMenuMode.off);
      final menus = [_menu('WAFFLE'), _menu('AMERICANO')];
      expect(identical(policy.sortFastFirst(menus), menus), isTrue);
    });

    test('지정 상품이 없으면 원본을 그대로 돌려준다', () {
      final policy =
          _policy(FastMenuMode.withinOrder, fastIds: const <String>{});
      final menus = [_menu('WAFFLE'), _menu('AMERICANO')];
      expect(identical(policy.sortFastFirst(menus), menus), isTrue);
    });

    test('전부 같은 부류면 사본을 만들지 않는다', () {
      final policy = _policy(FastMenuMode.withinOrder);
      final allFast = [_menu('AMERICANO'), _menu('AMERICANO')];
      final allSlow = [_menu('WAFFLE'), _menu('CAKE')];
      expect(identical(policy.sortFastFirst(allFast), allFast), isTrue);
      expect(identical(policy.sortFastFirst(allSlow), allSlow), isTrue);
    });

    test('빈 목록도 안전하다', () {
      final policy = _policy(FastMenuMode.withinOrder);
      expect(policy.sortFastFirst(const []), isEmpty);
    });
  });

  test('disabled 는 아무 것도 하지 않는다', () {
    const policy = FastMenuPolicy.disabled;
    expect(policy.isConfigured, isFalse);
    expect(policy.showMarker, isFalse);
    expect(policy.isFast(_menu('AMERICANO')), isFalse);
    expect(policy.isFastOrder(_order([_menu('AMERICANO')])), isFalse);
  });
}
