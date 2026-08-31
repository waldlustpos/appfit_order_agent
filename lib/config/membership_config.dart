/// 멤버십(스탬프/쿠폰) 기능의 매장별 노출 정책.
///
/// 스탬프를 운영하지 않는 매장에서는 멤버십 탭의 스탬프 UI(적립 입력·버튼·
/// 스탬프내역 탭)를 통째로 감춘다. 판정 근거는 매장정보조회
/// (`GET /v0/shop/{shopCode}`) 응답의 `shopGroupId` 다.
///
/// **숨김 목록(deny-list) 방식**이다 — 기본은 표시, 목록에 등록된 그룹만 숨김.
/// `shopGroupId` 가 없거나(구서버·필드 부재) 목록 밖이면 표시하므로, 목록이
/// 비어 있는 동안은 모든 매장이 기존과 동일하게 동작한다. 반대(표시 목록)로
/// 두면 값을 확인하기 전 배포 시 전 매장에서 스탬프가 사라진다.
class MembershipConfig {
  const MembershipConfig._();

  /// 스탬프 기능을 숨길 매장 그룹(`shopGroupId`).
  ///
  /// 새 값은 로그인 시 파일 로그의 `[SYSTEM]  매장그룹` 줄에서 확인한다.
  ///
  /// **주의 — 아는 그룹 ID 두 개는 마지막 한 글자만 다르다:**
  /// - `0qs2vf410y3wh` : 스탬프 **표시** (목록에 넣지 말 것)
  /// - `0qs2vf410y3wj` : 스탬프 **숨김**
  ///
  /// 끝자리 `h`/`j` 를 잘못 적으면 정반대 매장이 걸리고, 화면에서만 드러나므로
  /// 조용히 잘못된 채로 배포된다. 값 추가/수정 시
  /// `test/models/store_model_stamp_gate_test.dart` 의 실제 정책 테스트를
  /// 함께 갱신해 오타를 컴파일/테스트 단계에서 잡는다.
  static const Set<String> stampHiddenShopGroupIds = <String>{
    '0qs2vf410y3wj',
  };

  /// 이 매장에서 스탬프 UI 를 노출할지.
  ///
  /// [hiddenIds] 는 테스트 주입용이다 — 정책 상수가 비어 있는 상태에서도
  /// 판정 규칙 자체를 고정할 수 있게 한다.
  static bool stampEnabledFor(
    String? shopGroupId, {
    Set<String> hiddenIds = stampHiddenShopGroupIds,
  }) =>
      shopGroupId == null ||
      shopGroupId.isEmpty ||
      !hiddenIds.contains(shopGroupId);
}
