import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:appfit_order_agent/models/order_menu_model.dart';
import 'package:appfit_order_agent/models/order_model.dart';
import 'package:appfit_order_agent/providers/preference_provider.dart';

/// 빠른 메뉴 우선 모드. 설정 정본은 `PreferenceService.getFastMenuMode()`.
enum FastMenuMode {
  /// 종전 동작과 완전히 동일. 정렬도 추월도 없다.
  off,

  /// 한 주문 안에서만 빠른 메뉴 라벨을 먼저 인쇄. 주문번호 순서는 불변.
  withinOrder,

  /// 주문 내 정렬 + 전량 빠른 메뉴 주문의 라벨 큐 추월. 주문번호가 역전된다.
  acrossOrders;

  static FastMenuMode fromInt(int value) => switch (value) {
        1 => FastMenuMode.withinOrder,
        2 => FastMenuMode.acrossOrders,
        _ => FastMenuMode.off,
      };

  /// 주문 내 정렬 적용 여부.
  bool get sortsWithinOrder => this != FastMenuMode.off;

  /// 라벨 큐 추월 적용 여부.
  bool get overtakesQueue => this == FastMenuMode.acrossOrders;
}

/// "어떤 메뉴가 빠른 제조 메뉴인가"를 판정하는 단일 지점.
///
/// ## 왜 ID 집합만으로 판정하는가
/// 서버 상품 응답에 제조시간 필드가 없어 매장이 설정에서 직접 상품을 고른다.
/// 그 선택을 저장할 때 상품의 `productId` 와 `internalId` 를 **둘 다** 담아두므로
/// ([PreferenceService.getFastMenuIds] 주석 참조), 판정이 상품 카탈로그 조회 없이
/// 동기 문자열 멤버십 테스트로 끝난다.
///
/// 이게 중요한 이유: 라벨 큐 enqueue 지점([OutputQueueService.addLabelOnly] 등)이
/// **동기 void 함수**라 `FutureProvider` 인 `productProvider` 를 await 할 수 없다.
class FastMenuPolicy {
  const FastMenuPolicy({
    required this.mode,
    required this.showMarker,
    required this.fastIds,
  });

  /// 판정만 하고 아무 동작도 하지 않는 중립 정책.
  static const FastMenuPolicy disabled = FastMenuPolicy(
    mode: FastMenuMode.off,
    showMarker: false,
    fastIds: <String>{},
  );

  final FastMenuMode mode;

  /// 라벨 마커 / KDS 뱃지 표시 여부. [mode] 와 독립 축이다 —
  /// 순서만 바꾸고 표시는 하지 않는 "조용한 운용"이 기본값.
  final bool showMarker;

  /// 빠른 메뉴로 지정된 상품 ID 집합 (productId + internalId 혼재).
  final Set<String> fastIds;

  /// 지정된 상품이 하나도 없으면 정책 전체가 무의미하다.
  bool get isConfigured => fastIds.isNotEmpty;

  bool isFast(OrderMenuModel menu) => fastIds.contains(menu.shopItemId);

  /// 주문 전체가 빠른 메뉴일 때만 라벨 큐 추월 대상.
  ///
  /// 혼합 주문(빠른 메뉴 + 느린 메뉴)은 추월시키지 않는다 — 어차피 그 주문 안의
  /// 느린 메뉴가 병목이라 추월 이득은 없고 주문번호 역전 비용만 치른다.
  /// 혼합 주문은 [sortFastFirst] 로 주문 안에서만 순서를 조정한다.
  ///
  /// 메뉴가 비어 있으면(상세 미로드) 판정 불가 → false. 안전한 기본값이다.
  bool isFastOrder(OrderModel order) =>
      mode.overtakesQueue &&
      isConfigured &&
      order.menus.isNotEmpty &&
      order.menus.every(isFast);

  /// 빠른 메뉴를 앞으로 보낸 새 리스트. **안정 정렬** — 같은 부류 안에서는
  /// 원본 상대 순서를 그대로 유지한다.
  ///
  /// `List.sort` 는 Dart 에서 안정성이 보장되지 않으므로 분할로 구현한다.
  /// (주문 내 메뉴 순서는 영수증/KDS 와 대조되는 값이라 임의 재배열은 사고다.)
  List<OrderMenuModel> sortFastFirst(List<OrderMenuModel> menus) {
    if (!mode.sortsWithinOrder || !isConfigured) return menus;
    final fast = <OrderMenuModel>[];
    final rest = <OrderMenuModel>[];
    for (final menu in menus) {
      (isFast(menu) ? fast : rest).add(menu);
    }
    // 전부 한쪽이면 원본을 그대로 돌려 불필요한 사본 생성을 피한다.
    if (fast.isEmpty || rest.isEmpty) return menus;
    return [...fast, ...rest];
  }
}

/// 현재 설정 기준 [FastMenuPolicy].
///
/// `SharedPreferences` 는 변경 알림이 없으므로, 설정을 저장한 화면이
/// `ref.invalidate(fastMenuPolicyProvider)` 로 명시 갱신하는 계약이다.
final fastMenuPolicyProvider = Provider<FastMenuPolicy>((ref) {
  final prefs = ref.watch(preferenceServiceProvider);
  return FastMenuPolicy(
    mode: FastMenuMode.fromInt(prefs.getFastMenuMode()),
    showMarker: prefs.getFastMenuMarker(),
    fastIds: prefs.getFastMenuIds(),
  );
});
