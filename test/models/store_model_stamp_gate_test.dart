import 'package:flutter_test/flutter_test.dart';
import 'package:appfit_order_agent/config/membership_config.dart';
import 'package:appfit_order_agent/models/store_model.dart';

/// 스탬프 노출 판정(shopGroupId 기반 deny-list) 규칙 고정.
///
/// 규칙 자체는 hiddenIds 주입으로 검증하고, 실제 배포되는 정책 상수
/// [MembershipConfig.stampHiddenShopGroupIds] 는 아래 '실제 정책' 그룹에서
/// 별도로 고정한다.
void main() {
  StoreModel store(String? shopGroupId) => StoreModel(
        storeId: 'TPCP00001',
        name: '테스트점',
        isOpen: true,
        shopGroupId: shopGroupId,
      );

  group('실제 정책 — 배포되는 상수 값 고정', () {
    // 두 그룹 ID 는 마지막 한 글자(h/j)만 다르다. 상수에 오타가 나면 정반대
    // 매장이 걸리는데 화면에서만 드러나므로, 여기서 양방향으로 못 박는다.
    const visibleGroup = '0qs2vf410y3wh';
    const hiddenGroup = '0qs2vf410y3wj';

    test('숨김 그룹(...j)은 스탬프가 보이지 않는다', () {
      expect(MembershipConfig.stampHiddenShopGroupIds, contains(hiddenGroup));
      expect(MembershipConfig.stampEnabledFor(hiddenGroup), isFalse);
      expect(store(hiddenGroup).stampEnabled, isFalse);
    });

    test('표시 그룹(...h)은 스탬프가 보인다 — 끝자리 오타 감지', () {
      expect(
        MembershipConfig.stampHiddenShopGroupIds,
        isNot(contains(visibleGroup)),
      );
      expect(MembershipConfig.stampEnabledFor(visibleGroup), isTrue);
      expect(store(visibleGroup).stampEnabled, isTrue);
    });

    test('목록에 없는 그룹·그룹 없음은 기존대로 표시', () {
      expect(MembershipConfig.stampEnabledFor('other-group'), isTrue);
      expect(MembershipConfig.stampEnabledFor(null), isTrue);
      expect(store(null).stampEnabled, isTrue);
    });
  });

  group('MembershipConfig.stampEnabledFor — 숨김 목록에 값이 있을 때', () {
    const hidden = {'G1', 'G2'};

    test('목록에 있는 그룹은 숨김', () {
      expect(
          MembershipConfig.stampEnabledFor('G1', hiddenIds: hidden), isFalse);
      expect(
          MembershipConfig.stampEnabledFor('G2', hiddenIds: hidden), isFalse);
    });

    test('목록 밖 그룹은 표시', () {
      expect(MembershipConfig.stampEnabledFor('G3', hiddenIds: hidden), isTrue);
    });

    test('대소문자는 구분한다 (서버 값 원문 그대로 매칭)', () {
      expect(MembershipConfig.stampEnabledFor('g1', hiddenIds: hidden), isTrue);
    });
  });

  group('MembershipConfig.stampEnabledFor — 그룹 정보가 없을 때', () {
    const hidden = {'G1'};

    test('null(필드 부재·구서버)이면 표시 — 기본은 기존 동작 유지', () {
      expect(MembershipConfig.stampEnabledFor(null, hiddenIds: hidden), isTrue);
      expect(store(null).stampEnabled, isTrue);
    });

    test('빈 문자열도 그룹 없음과 같게 표시', () {
      expect(MembershipConfig.stampEnabledFor('', hiddenIds: hidden), isTrue);
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
