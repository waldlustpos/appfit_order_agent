import 'package:flutter_test/flutter_test.dart';
import 'package:appfit_order_agent/config/membership_config.dart';
import 'package:appfit_order_agent/models/store_model.dart';

/// 스탬프 **적립** 차단 판정(shopGroupId 기반 deny-list) 규칙 고정.
///
/// 이 게이트는 적립·적립취소(쓰기)만 막는다. 스탬프내역 조회와 보유 개수 표시는
/// 전 매장 공통이라 판정 자체가 없다(그래서 여기에 대응 테스트도 없다).
///
/// 규칙 자체는 blockedIds 주입으로 검증하고, 실제 배포되는 정책 상수
/// [MembershipConfig.stampAccrualBlockedShopGroupIds] 는 아래 '실제 정책'
/// 그룹에서 별도로 고정한다.
void main() {
  StoreModel store(String? shopGroupId) => StoreModel(
        storeId: 'TPCP00001',
        name: '테스트점',
        isOpen: true,
        shopGroupId: shopGroupId,
      );

  group('실제 정책 — 배포되는 상수 값 고정', () {
    // 두 그룹 ID 는 마지막 한 글자(h/j)만 다르다. 상수에 오타가 나면 정반대
    // 브랜드가 걸리는데 화면에서만 드러나므로, 여기서 양방향으로 못 박는다.
    //
    // ⚠️ 여기는 일부러 **날문자열**을 쓴다. MembershipConfig 의 상수를 그대로
    // 참조하면 값이 바뀌어도 테스트가 따라 바뀌어 아무것도 검증하지 못한다.
    const mammothCoffee = '0qs2vf410y3wh'; // 매머드커피 (1차 브랜드) — 적립 허용
    const mammothExpress = '0qs2vf410y3wj'; // 매머드익스프레스 (2차) — 적립 차단

    test('브랜드 상수가 실제 그룹 ID 와 일치한다', () {
      expect(MembershipConfig.shopGroupMammothCoffee, mammothCoffee);
      expect(MembershipConfig.shopGroupMammothExpress, mammothExpress);
      expect(MembershipConfig.shopGroupLabel(mammothCoffee), '매머드커피');
      expect(MembershipConfig.shopGroupLabel(mammothExpress), '매머드익스프레스');
      expect(MembershipConfig.shopGroupLabel('other-group'), isNull);
      expect(MembershipConfig.shopGroupLabel(null), isNull);
    });

    test('매머드익스프레스(...j)는 스탬프를 적립할 수 없다', () {
      expect(MembershipConfig.stampAccrualBlockedShopGroupIds,
          contains(mammothExpress));
      expect(MembershipConfig.stampAccrualEnabledFor(mammothExpress), isFalse);
      expect(store(mammothExpress).stampAccrualEnabled, isFalse);
    });

    test('매머드커피(...h)는 스탬프를 적립할 수 있다 — 끝자리 오타 감지', () {
      expect(
        MembershipConfig.stampAccrualBlockedShopGroupIds,
        isNot(contains(mammothCoffee)),
      );
      expect(MembershipConfig.stampAccrualEnabledFor(mammothCoffee), isTrue);
      expect(store(mammothCoffee).stampAccrualEnabled, isTrue);
    });

    test('목록에 없는 그룹·그룹 없음은 기존대로 적립 허용', () {
      expect(MembershipConfig.stampAccrualEnabledFor('other-group'), isTrue);
      expect(MembershipConfig.stampAccrualEnabledFor(null), isTrue);
      expect(store(null).stampAccrualEnabled, isTrue);
    });
  });

  group('MembershipConfig.stampAccrualEnabledFor — 차단 목록에 값이 있을 때', () {
    const blocked = {'G1', 'G2'};

    test('목록에 있는 그룹은 적립 차단', () {
      expect(MembershipConfig.stampAccrualEnabledFor('G1', blockedIds: blocked),
          isFalse);
      expect(MembershipConfig.stampAccrualEnabledFor('G2', blockedIds: blocked),
          isFalse);
    });

    test('목록 밖 그룹은 적립 허용', () {
      expect(MembershipConfig.stampAccrualEnabledFor('G3', blockedIds: blocked),
          isTrue);
    });

    test('대소문자는 구분한다 (서버 값 원문 그대로 매칭)', () {
      expect(MembershipConfig.stampAccrualEnabledFor('g1', blockedIds: blocked),
          isTrue);
    });
  });

  group('MembershipConfig.stampAccrualEnabledFor — 그룹 정보가 없을 때', () {
    const blocked = {'G1'};

    test('null(필드 부재·구서버)이면 허용 — 기본은 기존 동작 유지', () {
      expect(MembershipConfig.stampAccrualEnabledFor(null, blockedIds: blocked),
          isTrue);
      expect(store(null).stampAccrualEnabled, isTrue);
    });

    test('빈 문자열도 그룹 없음과 같게 허용', () {
      expect(MembershipConfig.stampAccrualEnabledFor('', blockedIds: blocked),
          isTrue);
    });
  });

  group('StoreModel — shopGroupId 보존', () {
    test('copyWith 로 다른 필드를 바꿔도 shopGroupId 가 유지된다', () {
      final s = store('G1').copyWith(isOpen: false);
      expect(s.shopGroupId, 'G1');
      expect(s.isOpen, isFalse);
    });

    test('toJson 에 shopGroupId 가 포함된다', () {
      expect(store('G1').toJson()['shopGroupId'], 'G1');
    });
  });
}
