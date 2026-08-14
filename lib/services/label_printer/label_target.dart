import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:appfit_order_agent/providers/preference_provider.dart';

/// 라벨 한 장이 향할 프린터(= 제조 구역) 식별자.
///
/// 값 하나짜리 래퍼인 이유: 이 id 는 `categoryCode` / `shopItemId` 같은 다른
/// 문자열들과 같은 자리에서 오가는데, 전부 `String` 이면 인자 순서를 바꿔 넣어도
/// 컴파일이 통과한다. 라벨이 엉뚱한 프린터로 가는 사고는 동일 기종 2대 환경에서
/// **육안으로 검출되지 않으므로** 타입으로 막는다.
class LabelTarget {
  const LabelTarget(this.id);

  /// 기본 타깃. 매핑되지 않은 카테고리와 미설정 매장이 전부 여기로 온다.
  ///
  /// **폴백은 항상 이쪽이다** — 설정 실수로 라벨이 사라지는 것보다 한 프린터에
  /// 몰려 나오는 편이 낫다. 후자는 운영자가 손으로 분류하면 끝이지만, 전자는
  /// 누락 복구 경로(`markPendingReprint`)를 타야 한다.
  static const LabelTarget primary = LabelTarget('primary');
  static const LabelTarget zone2 = LabelTarget('zone2');
  static const LabelTarget zone3 = LabelTarget('zone3');

  /// 설정 화면이 고를 수 있는 구역 목록.
  ///
  /// **자료구조는 임의의 id 를 받는다** — 고정 목록은 UI 쪽 제약일 뿐이다.
  /// 자유 입력을 주지 않는 이유: 오타 하나가 "이 단말이 담당하는 구역" 과
  /// 어긋나면 해당 카테고리 라벨이 **어느 단말에서도 안 나온다.** 카페 규모에서
  /// 3구역이면 충분하므로, 늘려야 할 때 여기에 추가하는 편이 안전하다.
  static const List<LabelTarget> selectable = [primary, zone2, zone3];

  final String id;

  @override
  bool operator ==(Object other) => other is LabelTarget && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => id;
}

/// "이 라벨이 어느 프린터로 가는가" + "이 단말이 그 프린터를 갖고 있는가".
///
/// ## 두 축을 왜 나눠 두는가
/// [assignment] 는 **매장 정책**(음료는 1번, 디저트는 2번)이라 모든 단말이 같은
/// 값을 갖는다. [localTargets] 는 **단말별 배치**(이 단말에 붙은 프린터가 2번)라
/// 단말마다 다르다. 두 값을 합쳐야 "이 단말이 이 라벨을 인쇄하는가" 가 나온다.
///
/// ## 현재 운용 형태
/// 한 단말에 라벨 프린터 1대가 물리 한계다 — REXOD RXLA-561 이 USB serial 을
/// 보고하지 않아 동일 기종 2대를 SDK 포트명으로 지목할 수 없다(2026-08-13 실측).
/// 그래서 지금은 **단말 여러 대 × 프린터 1대씩** 구성에서 각 단말이 담당 구역만
/// 인쇄하는 데 쓴다. 한 단말에 2대를 붙이는 길이 열리면
/// (벤더 유틸 PID 변경 / LAN 옵션), 여기 [assignment] 는 그대로 두고
/// [localTargets] 대신 타깃별 프린터 핸들로 분기하면 된다.
class LabelTargetPolicy {
  const LabelTargetPolicy({
    required this.assignment,
    required this.localTargets,
    this.fastMenuTarget,
  });

  /// 아무 것도 하지 않는 중립 정책. 모든 라벨이 primary 로 가고 전부 인쇄된다.
  static const LabelTargetPolicy disabled = LabelTargetPolicy(
    assignment: <String, String>{},
    localTargets: <String>{},
  );

  /// 상품 카테고리 코드 → 타깃 id. 비어 있으면 전부 [LabelTarget.primary].
  final Map<String, String> assignment;

  /// 빠른 제조 메뉴 전용 타깃 id. null 이면 이 규칙을 쓰지 않는다.
  ///
  /// [assignment] 와 **같은 매장 정책 축**이지만 더 좁다: 카테고리 배정이
  /// "음료는 1번" 이라는 면(面)이라면 이쪽은 "그중 아아만 2번" 이라는 점(點)이다.
  /// 그래서 [resolveTarget] 에서 **점이 면을 이긴다** — 그렇지 않으면 고객사가
  /// 실제로 쓰는 말("아아만 따로 빼 주세요")을 표현할 수 없다.
  ///
  /// 빠른 메뉴 집합 자체는 여기 없다. 그건 [FastMenuPolicy] 소관이고, 이 클래스는
  /// "빠르다고 판정된 메뉴를 어디로 보낼지" 만 안다.
  final String? fastMenuTarget;

  /// 이 단말이 담당하는 타깃 id 집합.
  ///
  /// **비어 있으면 전부 담당한다** — 미설정 매장의 종전 동작을 보존하는 기본값이다.
  final Set<String> localTargets;

  /// 설정이 하나라도 있는가. 로그/진단 표기용.
  bool get isConfigured =>
      assignment.isNotEmpty ||
      localTargets.isNotEmpty ||
      (fastMenuTarget != null && fastMenuTarget!.isNotEmpty);

  /// 카테고리 코드가 배정된 타깃. 미매핑·미상은 [LabelTarget.primary].
  LabelTarget targetForCategory(String? categoryCode) {
    if (categoryCode == null || categoryCode.isEmpty) {
      return LabelTarget.primary;
    }
    final id = assignment[categoryCode];
    if (id == null || id.isEmpty) return LabelTarget.primary;
    return LabelTarget(id);
  }

  /// 최종 행선지. 빠른 메뉴 배정이 카테고리 배정을 **덮는다**.
  ///
  /// 두 규칙이 한 메서드에 있어야 우선순위가 한눈에 보인다 — 호출부마다 조건을
  /// 나열하면 어디선가 순서가 뒤집힌다.
  LabelTarget resolveTarget({
    required bool isFastMenu,
    required String? categoryCode,
  }) {
    if (isFastMenu) {
      final id = fastMenuTarget;
      if (id != null && id.isNotEmpty) return LabelTarget(id);
    }
    return targetForCategory(categoryCode);
  }

  /// 이 단말이 [target] 을 인쇄하는가.
  bool handles(LabelTarget target) =>
      localTargets.isEmpty || localTargets.contains(target.id);
}

/// 현재 설정 기준 [LabelTargetPolicy].
///
/// `SharedPreferences` 는 변경 알림이 없으므로, 설정을 저장한 화면이
/// `ref.invalidate(labelTargetPolicyProvider)` 로 명시 갱신하는 계약이다
/// ([fastMenuPolicyProvider] 와 동일).
final labelTargetPolicyProvider = Provider<LabelTargetPolicy>((ref) {
  final prefs = ref.watch(preferenceServiceProvider);
  return LabelTargetPolicy(
    assignment: prefs.getLabelTargetAssignment(),
    localTargets: prefs.getLabelLocalTargets(),
    fastMenuTarget: prefs.getLabelFastMenuTarget(),
  );
});
