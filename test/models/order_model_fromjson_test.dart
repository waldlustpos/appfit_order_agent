import 'package:appfit_order_agent/models/order_menu_model.dart';
import 'package:appfit_order_agent/models/order_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// OrderModel.fromJson / OrderMenuModel.fromJson characterization 테스트.
///
/// 서버 응답 형태를 fromJson 코드에서 역산한 픽스처로 "현재 파싱 동작"을 고정한다.
/// 버그처럼 보이는 동작(타입 어긋남 크래시, 부분 손상 시 전체 드랍 등)도
/// 수정하지 않고 그대로 고정하며 '현재 동작 고정(버그 의심)' 으로 표기한다.
Map<String, dynamic> _fullOrderJson() => {
      'orderNo': 'ORD-1001',
      'shopOrderNo': '12',
      'displayOrderNo': '7',
      'orderStatus': '2003',
      'orderedAt': '2026-01-02T09:30:00.000',
      'totalAmount': 9500,
      'storeId': 'store-1',
      'userId': 'user-1',
      'customerName': '김고객',
      'tel': '010-1234-5678',
      'note': '얼음 적게',
      'userName': '닉네임',
      'storeName': '왈루스트점',
      'ordererName': '아메리카노 외 1건',
      'orderCount': 2,
      'paymentAmount': 9000,
      'discountAmount': 500,
      'paymentType': 'CARD',
      'paymentCode': 'KIOSK_CARD',
      'paidAt': '2026-01-02T09:31:00.000',
      'updateTime': '2026-01-02T09:32:00.000',
      'kioskId': 'kiosk-1',
      'orderSource': 'WALD_KIOSK',
      'orderType': 'T',
      'discountTypes': ['COUPON', 1],
      'menus': [
        {
          'orderNo': 'ORD-1001',
          'shopItemId': 'sku-1',
          'qty': 2,
          'itemName': '아메리카노',
          'itemPrice': 4500,
          'totalAmount': 9000,
          'discPrc': 0,
          'vatPrc': 818,
          'options': [
            {
              'shopOptionId': 'opt-1',
              'optionName': '샷 추가',
              'optionPrice': 500,
              'qty': 1,
            },
          ],
        },
      ],
    };

void main() {
  group('OrderModel.fromJson — 정상 전체 픽스처 매핑', () {
    test('모든 필드 매핑 검증', () {
      final o = OrderModel.fromJson(_fullOrderJson());

      expect(o.orderNo, 'ORD-1001');
      expect(o.shopOrderNo, '12');
      expect(o.displayOrderNo, '7');
      expect(o.orderStatus, '2003');
      expect(o.status, OrderStatus.NEW);
      expect(o.orderedAt, DateTime.parse('2026-01-02T09:30:00.000'));
      expect(o.totalAmount, 9500.0);
      expect(o.storeId, 'store-1');
      expect(o.userId, 'user-1');
      expect(o.customerName, '김고객');
      expect(o.tel, '010-1234-5678');
      expect(o.note, '얼음 적게');
      expect(o.userName, '닉네임');
      expect(o.storeName, '왈루스트점');
      expect(o.ordererName, '아메리카노 외 1건');
      expect(o.orderCount, '2'); // 숫자 → toString
      expect(o.paymentAmount, 9000.0);
      expect(o.discountAmount, 500.0);
      expect(o.paymentType, 'CARD');
      expect(o.paymentCode, 'KIOSK_CARD');
      expect(o.paidAt, DateTime.parse('2026-01-02T09:31:00.000'));
      expect(o.updateTime, DateTime.parse('2026-01-02T09:32:00.000'));
      expect(o.kioskId, 'kiosk-1');
      expect(o.source, 'WALD_KIOSK'); // orderSource 우선 매핑
      expect(o.orderType, 'T');
      expect(o.discountTypes, ['COUPON', '1']); // 원소 toString

      // 메뉴/옵션 파싱
      expect(o.menus, hasLength(1));
      expect(o.menus.first.shopItemId, 'sku-1');
      expect(o.menus.first.qty, 2);
      expect(o.menus.first.itemPrice, 4500.0);
      expect(o.menus.first.options, hasLength(1));
      expect(o.menus.first.options.first.optionName, '샷 추가');

      // 파생값 (생성자에서 paymentAmount 기준 계산)
      expect(o.exceptTaxPrice, 8182.0); // round(9000*100/110)
      expect(o.taxPrice, 818.0); // round(9000*10/110)

      // 메뉴 1 + 옵션 1 → 복잡도 50 < 130 → kdsOrderType 1
      expect(o.kdsOrderType, 1);
      expect(o.isDetailLoaded, isTrue); // 메뉴 존재 → true
      expect(o.displayNum, '0007'); // displayOrderNo 우선 + 4자리 패딩
    });

    test('상태 코드 매핑 테이블 (숫자 코드 + 문자열 코드)', () {
      OrderStatus statusOf(String code) =>
          OrderModel.fromJson({'orderStatus': code}).status;

      expect(statusOf('2003'), OrderStatus.NEW);
      expect(statusOf('2007'), OrderStatus.PREPARING);
      expect(statusOf('2009'), OrderStatus.READY);
      expect(statusOf('2020'), OrderStatus.DONE);
      expect(statusOf('9001'), OrderStatus.CANCELLED);
      expect(statusOf('2099'), OrderStatus.CANCELLED); // 미픽업 → 취소 취급
      expect(statusOf('9999'), OrderStatus.CANCELLED);
      expect(statusOf('NEW'), OrderStatus.NEW);
      expect(statusOf('ACCEPTED'), OrderStatus.PREPARING);
      expect(statusOf('PICKUP_REQUESTED'), OrderStatus.READY);
      expect(statusOf('CANCELED'), OrderStatus.CANCELLED);
      expect(statusOf('COMPLETED'), OrderStatus.DONE);
    });

    test('현재 동작 고정(버그 의심): 알 수 없는 상태 코드는 CANCELLED 로 강제 매핑', () {
      expect(OrderModel.fromJson({'orderStatus': 'UNKNOWN_CODE'}).status,
          OrderStatus.CANCELLED);
    });
  });

  group('OrderModel.fromJson — 선택 필드 누락/null 기본값', () {
    test('빈 JSON {} 도 크래시 없이 파싱됨 (현재 동작 고정: status 는 CANCELLED)', () {
      final o = OrderModel.fromJson(<String, dynamic>{});

      expect(o.orderNo, '');
      expect(o.shopOrderNo, '');
      expect(o.displayOrderNo, '');
      expect(o.orderStatus, '');
      expect(o.status, OrderStatus.CANCELLED); // '' → default 분기
      expect(o.totalAmount, 0.0);
      expect(o.paymentAmount, 0.0);
      expect(o.discountAmount, 0.0);
      expect(o.orderCount, '0');
      expect(o.customerName, isNull);
      expect(o.tel, isNull);
      expect(o.note, isNull);
      expect(o.userName, isNull);
      expect(o.paidAt, isNull);
      expect(o.menus, isEmpty);
      expect(o.orderType, '');
      expect(o.kdsOrderType, 0); // 메뉴 없음 → 0
      expect(o.isDetailLoaded, isFalse); // 메뉴 없음 → false
      expect(o.discountTypes, isEmpty);
      // orderedAt/updateTime 누락 → DateTime.now() fallback
      expect(
          DateTime.now().difference(o.orderedAt).inSeconds.abs(), lessThan(5));
      expect(
          DateTime.now().difference(o.updateTime).inSeconds.abs(), lessThan(5));
    });

    test('shopOrderNo 누락 시 displayOrderNum 으로 fallback', () {
      final o = OrderModel.fromJson({'displayOrderNum': '42'});
      expect(o.shopOrderNo, '42');
    });

    test('레거시 키 fallback: memo→note, userNickname→userName, source, order_type',
        () {
      final o = OrderModel.fromJson({
        'memo': '레거시 메모',
        'userNickname': '레거시닉',
        'source': 'LEGACY_SRC',
        'order_type': 'H',
      });
      expect(o.note, '레거시 메모');
      expect(o.userName, '레거시닉');
      expect(o.source, 'LEGACY_SRC');
      expect(o.orderType, 'H');
    });

    test('orderedAt 이 파싱 불가 문자열이면 DateTime.now() fallback', () {
      final o = OrderModel.fromJson({'orderedAt': 'not-a-date'});
      expect(
          DateTime.now().difference(o.orderedAt).inSeconds.abs(), lessThan(5));
    });
  });

  group('OrderModel.fromJson — 타입 어긋남 (현재 동작 고정)', () {
    test('숫자 필드가 문자열로 와도 tryParse 로 수용', () {
      final o = OrderModel.fromJson({
        'totalAmount': '12345.5',
        'paymentAmount': '9000',
        'discountAmount': '500',
      });
      expect(o.totalAmount, 12345.5);
      expect(o.paymentAmount, 9000.0);
      expect(o.discountAmount, 500.0);
    });

    test('숫자 필드가 파싱 불가 문자열이면 0.0', () {
      final o = OrderModel.fromJson({'totalAmount': 'abc'});
      expect(o.totalAmount, 0.0);
    });

    test('현재 동작 고정(버그 의심): orderedAt 이 숫자(epoch)면 TypeError 크래시', () {
      // DateTime.tryParse(json['orderedAt'] ?? '') 는 String 외 타입에 방어가 없다.
      expect(
        () => OrderModel.fromJson({'orderedAt': 1735780200000}),
        throwsA(isA<TypeError>()),
      );
    });

    test('현재 동작 고정(버그 의심): paidAt 이 숫자면 TypeError 크래시', () {
      expect(
        () => OrderModel.fromJson({'paidAt': 1735780200000}),
        throwsA(isA<TypeError>()),
      );
    });

    test('현재 동작 고정(버그 의심): orderType 이 숫자면 TypeError 크래시 (toString 누락)', () {
      // orderType 은 다른 문자열 필드와 달리 ?.toString() 없이 그대로 할당된다.
      expect(
        () => OrderModel.fromJson({'orderType': 1}),
        throwsA(isA<TypeError>()),
      );
    });

    test('현재 동작 고정(버그 의심): isDetailLoaded 가 문자열이면 TypeError 크래시', () {
      expect(
        () => OrderModel.fromJson({'isDetailLoaded': 'true'}),
        throwsA(isA<TypeError>()),
      );
    });
  });

  group('OrderModel.fromJson — menus 파싱 오류 처리 (현재 동작 고정)', () {
    test('menus 가 List 가 아니면 조용히 빈 목록으로 대체 (크래시 없음)', () {
      final o = OrderModel.fromJson({'menus': 'not-a-list'});
      expect(o.menus, isEmpty);
      expect(o.isDetailLoaded, isFalse);
    });

    test('현재 동작 고정(버그 의심): 메뉴 1건만 손상돼도 전체 menus 가 [] 로 드랍', () {
      final o = OrderModel.fromJson({
        'menus': [
          {
            'shopItemId': 'sku-1',
            'qty': 1,
            'itemName': '정상 메뉴',
            'itemPrice': 1000,
          },
          'corrupted-item', // Map 이 아닌 항목 → 전체 catch
        ],
      });
      expect(o.menus, isEmpty); // 정상 메뉴까지 함께 유실되는 현재 동작
    });

    test('현재 동작 고정(버그 의심): 메뉴의 qty 가 문자열이면 전체 menus 드랍', () {
      // OrderMenuModel.fromJson 의 (qty as num) TypeError 가 상위 catch 로 전파.
      final o = OrderModel.fromJson({
        'menus': [
          {'shopItemId': 'sku-1', 'qty': '2', 'itemName': '아메리카노'},
        ],
      });
      expect(o.menus, isEmpty);
    });
  });

  group('OrderModel.fromDetailJson', () {
    test('data 가 있으면 fromJson 으로 위임', () {
      final o = OrderModel.fromDetailJson({'data': _fullOrderJson()});
      expect(o.orderNo, 'ORD-1001');
      expect(o.status, OrderStatus.NEW);
    });

    test('data 가 null/누락이면 Exception throw', () {
      expect(() => OrderModel.fromDetailJson({'data': null}), throwsException);
      expect(() => OrderModel.fromDetailJson(<String, dynamic>{}),
          throwsException);
    });
  });

  group('OrderMenuModel.fromJson', () {
    test('정상 매핑 (옵션 포함)', () {
      final m = OrderMenuModel.fromJson({
        'orderNo': 'ORD-1001',
        'shopItemId': 'sku-1',
        'qty': 3,
        'itemName': '라떼',
        'itemPrice': 5000,
        'totalAmount': 15000,
        'discPrc': 100,
        'vatPrc': 1364,
        'options': [
          {
            'shopOptionId': 'opt-1',
            'optionName': '샷 추가',
            'optionPrice': 500,
            'qty': 2,
          },
        ],
      });
      expect(m.orderNo, 'ORD-1001');
      expect(m.shopItemId, 'sku-1');
      expect(m.qty, 3);
      expect(m.itemName, '라떼');
      expect(m.itemPrice, 5000.0);
      expect(m.totalAmount, 15000.0);
      expect(m.discPrc, 100.0);
      expect(m.vatPrc, 1364.0);
      expect(m.options, hasLength(1));
      expect(m.options.first.shopOptionId, 'opt-1');
      expect(m.options.first.optionPrice, 500.0);
      expect(m.options.first.qty, 2);
    });

    test('선택 필드 누락 시 기본값 (qty=0, 문자열 빈값, 가격 0.0, options [])', () {
      final m = OrderMenuModel.fromJson(<String, dynamic>{});
      expect(m.orderNo, '');
      expect(m.shopItemId, '');
      expect(m.qty, 0);
      expect(m.itemName, '');
      expect(m.itemPrice, 0.0);
      expect(m.options, isEmpty);
    });

    test('가격 필드는 문자열로 와도 tryParse 수용', () {
      final m = OrderMenuModel.fromJson({
        'qty': 1,
        'itemPrice': '4500',
        'totalAmount': '4500.5',
      });
      expect(m.itemPrice, 4500.0);
      expect(m.totalAmount, 4500.5);
    });

    test('현재 동작 고정(버그 의심): qty 가 문자열이면 TypeError 크래시 (qty 만 num 캐스트)', () {
      // itemPrice 등은 tryParse 인데 qty 는 (json['qty'] as num) 직캐스트.
      expect(
        () => OrderMenuModel.fromJson({'qty': '3'}),
        throwsA(isA<TypeError>()),
      );
    });

    test('옵션 파싱 오류 시 로그만 남기고 options=[] 유지 (L38-40 catch 고정)', () {
      // options 가 List 가 아닌 경우
      final notList = OrderMenuModel.fromJson({
        'shopItemId': 'sku-1',
        'qty': 1,
        'itemName': '아메리카노',
        'options': 'not-a-list',
      });
      expect(notList.options, isEmpty);
      expect(notList.shopItemId, 'sku-1'); // 나머지 필드는 정상 파싱

      // 옵션 항목 1건 손상(shopOptionId 가 int → as String? TypeError)
      final corruptedItem = OrderMenuModel.fromJson({
        'shopItemId': 'sku-1',
        'qty': 1,
        'itemName': '아메리카노',
        'options': [
          {'shopOptionId': 'opt-1', 'optionName': '정상 옵션', 'optionPrice': 500},
          {'shopOptionId': 123, 'optionName': '손상 옵션'},
        ],
      });
      // 현재 동작 고정(버그 의심): 손상 1건 때문에 정상 옵션까지 전체 드랍
      expect(corruptedItem.options, isEmpty);
    });
  });
}
