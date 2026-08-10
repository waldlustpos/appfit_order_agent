import 'package:appfit_order_agent/models/order_menu_model.dart';
import 'package:appfit_order_agent/models/order_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// OrderModel.fromJson / OrderMenuModel.fromJson characterization 테스트.
///
/// 서버 응답 형태를 fromJson 코드에서 역산한 픽스처로 파싱 동작을 고정한다.
/// 타입 어긋남 입력은 toString 후 tryParse 로 무해화하고, menus/options 는
/// 항목별 try-catch 로 격리해 손상 항목만 스킵하는 방어 동작을 검증한다.
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
      'discounts': [
        {
          'discountType': 'COUPON',
          'discountAmount': 500,
          'discountScope': 'ORDER',
          'couponName': '500원 할인권',
        },
      ],
      'payments': [
        {
          'paymentMethod': 'CREDIT_CARD',
          'amount': 9000,
          'status': 'DONE',
          'cardName': '신한',
          'cardNo': '5327111122223333',
          'installment': 0,
        },
      ],
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
      // 상세 전용 필드 (discountTypes 는 discounts 파생 getter)
      expect(o.discountTypes, ['COUPON']);
      expect(o.discounts, hasLength(1));
      expect(o.discounts.first.discountAmount, 500.0);
      expect(o.discounts.first.couponName, '500원 할인권');
      expect(o.payments, hasLength(1));
      expect(o.payments.first.paymentMethod, 'CREDIT_CARD');
      expect(o.payments.first.amount, 9000.0);
      expect(o.payments.first.cardNo, '5327-****'); // 파싱 시점 마스킹
      expect(o.payments.first.status, 'DONE');
      expect(o.payments.first.installment, 0);

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
      expect(o.payments, isEmpty);
      expect(o.discounts, isEmpty);
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

  group('OrderModel.fromJson — 타입 어긋남 방어', () {
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

    test('orderedAt 이 숫자(epoch)면 크래시 없이 DateTime.now() fallback', () {
      // toString 후 tryParse — epoch 밀리초 문자열은 ISO 가 아니라 파싱 실패 → now()
      final o = OrderModel.fromJson({'orderedAt': 1735780200000});
      expect(
          DateTime.now().difference(o.orderedAt).inSeconds.abs(), lessThan(5));
    });

    test('paidAt 이 숫자면 크래시 없이 null', () {
      final o = OrderModel.fromJson({'paidAt': 1735780200000});
      expect(o.paidAt, isNull);
    });

    test('orderType 이 숫자면 크래시 없이 toString 수용', () {
      final o = OrderModel.fromJson({'orderType': 1});
      expect(o.orderType, '1');
    });

    test('isDetailLoaded 비-bool 입력은 false 로 무해화, bool 은 그대로 사용', () {
      // 문자열 'true' 는 bool true 가 아니므로 == true 비교로 false
      expect(OrderModel.fromJson({'isDetailLoaded': 'true'}).isDetailLoaded,
          isFalse);
      expect(
          OrderModel.fromJson({'isDetailLoaded': 1}).isDetailLoaded, isFalse);
      // 명시적 bool 값은 메뉴 유무와 무관하게 그대로 사용
      expect(
          OrderModel.fromJson({'isDetailLoaded': true}).isDetailLoaded, isTrue);
      expect(
          OrderModel.fromJson({
            'isDetailLoaded': false,
            'menus': [
              {'shopItemId': 'sku-1', 'qty': 1, 'itemName': '아메리카노'},
            ],
          }).isDetailLoaded,
          isFalse);
    });
  });

  group('OrderModel.fromJson — menus 파싱 오류 처리', () {
    test('menus 가 List 가 아니면 조용히 빈 목록으로 대체 (크래시 없음)', () {
      final o = OrderModel.fromJson({'menus': 'not-a-list'});
      expect(o.menus, isEmpty);
      expect(o.isDetailLoaded, isFalse);
    });

    test('메뉴 1건 손상 시 해당 항목만 스킵, 정상 메뉴는 유지 (항목별 격리)', () {
      final o = OrderModel.fromJson({
        'menus': [
          {
            'shopItemId': 'sku-1',
            'qty': 1,
            'itemName': '정상 메뉴',
            'itemPrice': 1000,
          },
          'corrupted-item', // Map 이 아닌 항목 → 해당 항목만 스킵
        ],
      });
      expect(o.menus, hasLength(1));
      expect(o.menus.first.itemName, '정상 메뉴');
      expect(o.isDetailLoaded, isTrue); // 정상 메뉴가 남아 있으므로 true
    });

    test('메뉴의 qty 가 문자열이어도 tryParse 수용 (menus 드랍 없음)', () {
      final o = OrderModel.fromJson({
        'menus': [
          {'shopItemId': 'sku-1', 'qty': '2', 'itemName': '아메리카노'},
        ],
      });
      expect(o.menus, hasLength(1));
      expect(o.menus.first.qty, 2);
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

    test('qty 가 문자열이어도 tryParse 수용, 파싱 불가면 0', () {
      // 다른 숫자 필드와 동일하게 toString 후 tryParse 패턴.
      expect(OrderMenuModel.fromJson({'qty': '3'}).qty, 3);
      expect(OrderMenuModel.fromJson({'qty': 'abc'}).qty, 0);
    });

    test('옵션 파싱 오류 시 로그만 남기고 손상 항목만 스킵 (항목별 격리)', () {
      // options 가 List 가 아닌 경우 → 빈 목록
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
      // 손상 항목만 스킵하고 정상 옵션은 유지
      expect(corruptedItem.options, hasLength(1));
      expect(corruptedItem.options.first.optionName, '정상 옵션');
    });
  });
}
