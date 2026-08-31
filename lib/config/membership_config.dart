/// 멤버십(스탬프/쿠폰) 기능의 매장별 정책.
///
/// 판정 근거는 매장정보조회(`GET /v0/shop/{shopCode}`) 응답의 `shopGroupId` 다.
///
/// ## 축은 '적립'(쓰기) 하나뿐 — '내역 조회'(읽기)는 전 매장 공통
///
/// 스탬프를 운영하지 않는 매장에서 막는 것은 **적립 경로**다: 적립 개수 입력란·
/// 키패드·[스탬프 적립] 버튼, 그리고 내역 카드의 [적립취소] 버튼. 이 매장 단말
/// 로는 스탬프를 늘리거나 되돌릴 수 없다.
///
/// 반면 **스탬프내역 탭과 보유 스탬프 개수는 어느 매장에서든 보인다.** 회원은
/// 브랜드를 넘나들며 같은 계정을 쓰므로, 2차 브랜드 매장에서도 "이 손님이
/// 스탬프를 몇 개 갖고 있고 언제 쌓았는지"를 확인해줄 수 있어야 한다. 읽기는
/// 아무것도 바꾸지 않으니 막을 이유가 없다.
///
/// ## 숨김 목록(deny-list) 방식
///
/// 기본은 적립 허용, 목록에 등록된 그룹만 차단. `shopGroupId` 가 없거나
/// (구서버·필드 부재) 목록 밖이면 허용하므로, 목록이 비어 있는 동안은 모든
/// 매장이 기존과 동일하게 동작한다. 반대(허용 목록)로 두면 값을 확인하기 전
/// 배포 시 전 매장에서 적립이 막힌다.
class MembershipConfig {
  const MembershipConfig._();

  // ─── 알려진 매장 그룹 ────────────────────────────────────────────────────
  //
  // 두 ID 는 **마지막 한 글자(h/j)만 다르다.** 끝자리를 잘못 적으면 정반대
  // 브랜드가 걸리는데 화면에서만 드러나 조용히 배포된다. 그래서 아래 목록에는
  // 날문자열 대신 반드시 이 상수를 쓴다 — 이름이 틀리면 컴파일이 깨진다.

  /// **매머드커피** (1차 브랜드). 스탬프 **적립 허용** — 차단 목록에 넣지 말 것.
  ///
  /// 멤버십 화면의 '미가입 접수'(미가입 번호로도 적립)가 성립하는 근거가 이
  /// 브랜드의 서버 정책이다 — **적립 요청을 받아주면서 회원을 내부적으로
  /// 가입시킨다.** 그래서 적립 직후 재조회가 정상 회원으로 응답한다.
  /// 상세는 `Membership._enterUnregistered` 문서 참고.
  static const String shopGroupMammothCoffee = '0qs2vf410y3wh';

  /// **매머드익스프레스** (2차 브랜드). 스탬프 **적립 차단**(내역 조회는 허용).
  static const String shopGroupMammothExpress = '0qs2vf410y3wj';

  /// 그룹 ID → 사람이 읽는 브랜드명. 모르는 그룹이면 null.
  ///
  /// 로그인 로그(`[SYSTEM]  매장그룹`)에 붙여, 현장에서 받은 ID 가 어느
  /// 브랜드인지 로그만 보고 판별할 수 있게 한다.
  static String? shopGroupLabel(String? shopGroupId) => switch (shopGroupId) {
        shopGroupMammothCoffee => '매머드커피',
        shopGroupMammothExpress => '매머드익스프레스',
        _ => null,
      };

  /// 스탬프 **적립·적립취소**를 차단할 매장 그룹(`shopGroupId`).
  ///
  /// 여기 등록해도 스탬프내역 탭과 보유 개수는 계속 보인다(클래스 문서 참고).
  ///
  /// 새 값은 로그인 시 파일 로그의 `[SYSTEM]  매장그룹` 줄에서 확인한다.
  ///
  /// 값 추가/수정 시 `test/models/store_model_stamp_gate_test.dart` 의 실제
  /// 정책 테스트를 함께 갱신해 오타를 테스트 단계에서 잡는다(그 테스트는
  /// 일부러 날문자열을 써서 상수 값 자체를 독립적으로 검증한다).
  static const Set<String> stampAccrualBlockedShopGroupIds = <String>{
    shopGroupMammothExpress,
  };

  /// 이 매장에서 스탬프를 적립(및 적립취소)할 수 있는지.
  ///
  /// 스탬프내역 조회에는 쓰지 않는다 — 내역은 이 판정과 무관하게 항상 보인다.
  ///
  /// [blockedIds] 는 테스트 주입용이다 — 정책 상수가 비어 있는 상태에서도
  /// 판정 규칙 자체를 고정할 수 있게 한다.
  static bool stampAccrualEnabledFor(
    String? shopGroupId, {
    Set<String> blockedIds = stampAccrualBlockedShopGroupIds,
  }) =>
      shopGroupId == null ||
      shopGroupId.isEmpty ||
      !blockedIds.contains(shopGroupId);
}
