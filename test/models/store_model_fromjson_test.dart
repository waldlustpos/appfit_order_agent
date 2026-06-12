import 'package:appfit_order_agent/models/store_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// StoreModel.fromJson characterization 테스트.
///
/// 필수 필드(strId/name)는 `as String` 직캐스트라 누락/타입 어긋남 시
/// TypeError 크래시가 현재 동작이다 — 방어 코드 추가는 다음 커밋으로 미루고
/// 여기서는 크래시 자체를 throwsA 로 고정한다.
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

    test('현재 동작 고정(버그 의심): orderStatus 가 문자열 "8" 이면 isOpen false (== 8 정수 비교)',
        () {
      final s = StoreModel.fromJson({
        'strId': 's',
        'name': 'n',
        'orderStatus': '8',
      });
      expect(s.isOpen, isFalse); // 서버가 문자열로 보내면 영업 종료로 오인되는 현재 동작
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
      });
      expect(s.phone, isNull);
      expect(s.businessNumber, isNull);
      expect(s.rewardType, ''); // 생성자 기본값
    });
  });

  group('StoreModel.fromJson — 필수 필드 누락/타입 어긋남 크래시 (현재 동작 고정)', () {
    test('현재 동작 고정(버그 의심): strId 누락 → TypeError 크래시 (as String 직캐스트)', () {
      expect(
        () => StoreModel.fromJson({'name': 'n', 'orderStatus': 8}),
        throwsA(isA<TypeError>()),
      );
    });

    test('현재 동작 고정(버그 의심): name 이 null → TypeError 크래시', () {
      expect(
        () => StoreModel.fromJson({'strId': 's', 'name': null}),
        throwsA(isA<TypeError>()),
      );
    });

    test('현재 동작 고정(버그 의심): strId 가 숫자면 TypeError 크래시', () {
      expect(
        () => StoreModel.fromJson({'strId': 123, 'name': 'n'}),
        throwsA(isA<TypeError>()),
      );
    });

    test('빈 JSON {} → TypeError 크래시', () {
      expect(
        () => StoreModel.fromJson(<String, dynamic>{}),
        throwsA(isA<TypeError>()),
      );
    });
  });
}
