import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:appfit_order_agent/constants/app_styles.dart';
import 'package:appfit_order_agent/constants/card_types.dart';
import 'package:appfit_order_agent/i18n/strings.g.dart';
import 'package:appfit_order_agent/models/order_menu_model.dart';
import 'package:appfit_order_agent/models/order_model.dart';
import 'package:appfit_order_agent/providers/providers.dart';
import 'package:appfit_order_agent/services/label_printer/fast_menu_policy.dart';
import 'package:appfit_order_agent/utils/common_util.dart';
import 'package:appfit_order_agent/widgets/kds/kds_card_metrics.dart';

/// 단일 메뉴 줄 + 옵션 목록 표시.
class KdsMenuItemWidget extends StatelessWidget {
  final OrderMenuModel menu;
  final bool isChecked;
  final bool isCancelled;
  final VoidCallback? onTap;
  final int menuIndex;

  /// 빠른 제조 메뉴 뱃지 표시 여부. 호출부에서 "지정된 메뉴 && 표시 설정 ON"
  /// 을 이미 판정해 넘긴다 (표시 OFF 면 순서만 조용히 바뀐다).
  final bool isFastMenu;

  const KdsMenuItemWidget({
    super.key,
    required this.menu,
    required this.isChecked,
    required this.isCancelled,
    this.onTap,
    required this.menuIndex,
    this.isFastMenu = false,
  });

  @override
  Widget build(BuildContext context) {
    // 색상/취소선은 한 번만 계산해 모든 텍스트가 공유한다.
    final muted = isCancelled || isChecked;
    final textColor = muted ? AppStyles.gray6 : Colors.black;
    final textDecoration =
        muted ? TextDecoration.lineThrough : TextDecoration.none;

    // 메뉴명: 검정 (muted 시 gray6 + 취소선). 굵기는 종전대로 normal —
    // 옵션명이 한 단계 작고 gray6 이라 위계는 그것만으로 충분하다.
    final menuStyle = TextStyle(
      fontSize: KdsCardMetrics.menuFontSize,
      fontWeight: FontWeight.normal,
      color: textColor,
      decoration: textDecoration,
      height: 1.25, // 2줄 wrap 행간
    );
    // 수량: 메뉴명과 같은 크기·굵기 + 브랜드 컬러.
    // 긴 메뉴명이 2줄로 늘어나 수량과 맞닿으면 같은 검정끼리 뭉쳐 읽기 어렵다.
    // 색으로 경계를 만들되, muted(체크/취소)일 땐 gray6 으로 내려
    // '처리됨' 신호(회색 + 취소선)를 흐리지 않는다.
    final qtyStyle = menuStyle.copyWith(
      color: muted ? AppStyles.gray6 : AppStyles.kMainColor,
    );
    // 옵션: 한 단계 작게 + 항상 gray6 (주문 상세와 동일). muted 신호는
    // 취소선이 전담한다 — 메뉴명 색 변화가 이미 상태를 알리고 있다.
    final optionStyle = TextStyle(
      fontSize: KdsCardMetrics.optionFontSize,
      fontWeight: FontWeight.normal,
      color: AppStyles.gray6,
      decoration: textDecoration,
      height: 1.2,
    );
    // 옵션 수량도 메뉴 수량과 같은 규칙 (옵션명과 수량이 둘 다 gray6 이라 동일 문제).
    final optionQtyStyle = optionStyle.copyWith(
      color: muted ? AppStyles.gray6 : AppStyles.kMainColor,
    );

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isChecked ? AppStyles.kCheckedBgColor : Colors.transparent,
          borderRadius: AppRadius.bSm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              // 메뉴명이 2줄일 때 수량이 세로 중앙에 뜨지 않고 첫 줄에 붙게 한다.
              // 메뉴/수량 fontSize 가 같아 start 가 곧 첫 줄 baseline 정렬이다.
              // (CrossAxisAlignment.baseline 은 textBaseline 미지정 시 assert 로
              //  카드가 통째로 사라지므로 쓰지 않는다.)
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 뱃지는 메뉴명 앞. muted(체크/취소)일 땐 회색으로 내려
                // '처리됨' 신호를 흐리지 않는다 (수량 텍스트와 같은 규칙).
                if (isFastMenu) ...[
                  _FastMenuBadge(muted: muted),
                  const SizedBox(width: AppSpacing.s4),
                ],
                Expanded(
                  child: Text(
                    CommonUtil.normalizeInlineText(menu.itemName),
                    style: menuStyle,
                    maxLines: KdsCardMetrics.menuNameMaxLines,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // 색만으로는 2줄 메뉴명의 끝 글자와 바로 붙어 보여 간격도 함께 넓힌다.
                const SizedBox(width: AppSpacing.s8),
                Text(t.kds.item_qty(n: menu.qty), style: qtyStyle),
              ],
            ),
            if (menu.options.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(
                  left: AppSpacing.s16,
                  top: AppSpacing.s4,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: menu.options.map((option) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(
                              top: KdsCardMetrics.optionIconTopNudge,
                            ),
                            child: Icon(
                              Icons.subdirectory_arrow_right,
                              size: KdsCardMetrics.optionIconSize,
                              color: AppStyles.gray6,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.s4),
                          Expanded(
                            child: Text(
                              CommonUtil.normalizeInlineText(option.optionName),
                              style: optionStyle,
                              maxLines: KdsCardMetrics.optionNameMaxLines,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // qty 가 1 이면 빈 Text + SizedBox 를 아예 만들지 않아
                          // 옵션 가용폭을 되찾는다(종전엔 항상 생성했다).
                          if (option.qty > 1) ...[
                            const SizedBox(width: AppSpacing.s8),
                            Text(
                              t.kds.item_qty(n: option.qty),
                              style: optionQtyStyle,
                            ),
                          ],
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 빠른 제조 메뉴 뱃지. 라벨의 반전 칩과 같은 문구([t.common.fast_menu])를 써서
/// 화면과 인쇄물이 같은 언어로 말하게 한다.
class _FastMenuBadge extends StatelessWidget {
  const _FastMenuBadge({required this.muted});

  final bool muted;

  @override
  Widget build(BuildContext context) {
    final color = muted ? AppStyles.gray6 : AppStyles.kMainColor;
    return Padding(
      // 메뉴명 첫 줄 baseline 에 맞추는 미세 보정 (옵션 아이콘과 같은 방식).
      padding: const EdgeInsets.only(top: 2),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: AppRadius.bSm,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
          child: Text(
            t.common.fast_menu,
            style: TextStyle(
              fontSize: KdsCardMetrics.optionFontSize,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              height: 1.25,
            ),
          ),
        ),
      ),
    );
  }
}

/// 메뉴 리스트.
///
/// 진행(`OrderStatus.PREPARING`) 탭에서만 체크 토글이 활성화되며,
/// 체크 상태는 `kdsCheckedItemsProvider`에서 주문 단위로 select하여
/// 다른 카드 변경에 영향받지 않도록 한다.
class KdsMenuListWidget extends ConsumerWidget {
  final List<OrderMenuModel> menuList;
  final OrderModel order;
  final CardType cardType;

  const KdsMenuListWidget({
    super.key,
    required this.menuList,
    required this.order,
    required this.cardType,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!order.isDetailLoaded) return const _MenuLoading();
    if (menuList.isEmpty) return const _MenuEmpty();

    final checkedForOrder = ref.watch(
      kdsCheckedItemsProvider.select((map) => map[order.orderId]),
    );
    final isCancelledTab = cardType == CardType.cancelled;
    final isProgressTab = order.status == OrderStatus.PREPARING;
    // 표시 설정이 꺼져 있으면 판정 자체를 건너뛴다 (조용한 운용이 기본).
    final fastMenuPolicy = ref.watch(fastMenuPolicyProvider);
    final showFastBadge = fastMenuPolicy.showMarker;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(menuList.length, (i) {
        final menu = menuList[i];
        final isChecked =
            isProgressTab ? (checkedForOrder?.contains(i) ?? false) : false;

        return Column(
          children: [
            KdsMenuItemWidget(
              menu: menu,
              isChecked: isChecked,
              isCancelled: isCancelledTab,
              menuIndex: i,
              isFastMenu: showFastBadge && fastMenuPolicy.isFast(menu),
              onTap: () {
                ref.read(orderProvider.notifier).stopBlinking();
                if (order.status != OrderStatus.PREPARING) return;
                ref
                    .read(kdsCheckedItemsProvider.notifier)
                    .toggle(order.orderId, i, !isChecked);
              },
            ),
            if (i < menuList.length - 1)
              const Divider(
                color: AppStyles.gray3,
                thickness: 1,
                height: AppSpacing.s8,
              ),
          ],
        );
      }),
    );
  }
}

class _MenuLoading extends StatelessWidget {
  const _MenuLoading();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(height: AppSpacing.s8),
            Text(
              t.kds.loading_detail,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuEmpty extends StatelessWidget {
  const _MenuEmpty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.warning_amber_rounded, size: 20, color: Colors.grey),
          const SizedBox(height: AppSpacing.s8),
          Text(
            t.kds.no_menu_info,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
