import 'package:appfit_order_agent/models/store_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// StoreModel.fromJson characterization 테스트.
///
/// 필수 필드(strId/name)는 누락/비문자열 시 명시적 FormatException throw.
/// 매장 정보는 silent 기본값('')이 더 위험(빈 storeId 가 초기 로드 가드를
/// 조용히 통과)하므로 명확한 실패를 방어 동작으로 고정한다.
void main() {
  group('StoreModel.fromJson — 정상 매핑', () {
    test('strId/name 매핑 + orderStatus == 8(int) 이면 isOpen true', () {
      final s = StoreModel.fromJson({
        'strId': 'store-1',
        'name': '왈루스트점',
        'orderStatus': 8,
      });
      expect(s.storeId, 'store-1');
      expect(s.name, '왈루스트점');
      expect(s.isOpen, isTrue);
    });

    test('orderStatus 가 8 이 아니면 isOpen false (2, 0, 누락, null)', () {
      expect(
          StoreModel.fromJson({'strId': 's', 'name': 'n', 'orderStatus': 2})
              .isOpen,
          isFalse);
      expect(
          StoreModel.fromJson({'strId': 's', 'name': 'n', 'orderStatus': 0})
              .isOpen,
          isFalse);
      expect(StoreModel.fromJson({'strId': 's', 'name': 'n'}).isOpen, isFalse);
      expect(
          StoreModel.fromJson({'strId': 's', 'name': 'n', 'orderStatus': null})
              .isOpen,
          isFalse);
    });

    test('orderStatus 가 문자열 "8" 이어도 isOpen true (tryParse 수용)', () {
      final s = StoreModel.fromJson({
        'strId': 's',
        'name': 'n',
        'orderStatus': '8',
      });
      expect(s.isOpen, isTrue); // 서버가 문자열로 보내도 영업 중으로 인식
    });
  });

  group('StoreModel.fromJson — fromJson 이 매핑하지 않는 필드 (현재 동작 고정)', () {
    test('현재 동작 고정(버그 의심): phone/shopContact 등은 JSON 에 있어도 무시되고 기본값 유지', () {
      // 필드 주석상 phone 은 /v0/shop 의 shopContact 인데, fromJson 은 strId/name/
      // orderStatus 3개 키만 읽는다 (실제 phone 매핑은 ApiService.getStoreInfo 쪽).
      final s = StoreModel.fromJson({
        'strId': 'store-1',
        'name': '왈루스트점',
        'orderStatus': 8,
        'phone': '02-1234-5678',
        'shopContact': '02-1234-5678',
        'businessNumber': '123-45-67890',
        'rewardType': 'STAMP',
        'shopGroupId': 'GRP-1',
      });
      expect(s.phone, isNull);
      expect(s.businessNumber, isNull);
      expect(s.rewardType, ''); // 생성자 기본값
      // shopGroupId 도 동일 — 실제 매핑은 ApiService.getStoreInfo 쪽이다.
      expect(s.shopGroupId, isNull);
    });
  });

  group('StoreModel.fromJson — 필수 필드 누락/타입 어긋남 시 명시적 FormatException', () {
    test('strId 누락 → FormatException (메시지에 strId 명시)', () {
      expect(
        () => StoreModel.fromJson({'name': 'n', 'orderStatus': 8}),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', contains('strId'))),
      );
    });

    test('name 이 null → FormatException (메시지에 name 명시)', () {
      expect(
        () => StoreModel.fromJson({'strId': 's', 'name': null}),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', contains('name'))),
      );
    });

    test('strId 가 숫자면 FormatException', () {
      expect(
        () => StoreModel.fromJson({'strId': 123, 'name': 'n'}),
        throwsA(isA<FormatException>()),
      );
    });

    test('빈 JSON {} → FormatException', () {
      expect(
        () => StoreModel.fromJson(<String, dynamic>{}),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
