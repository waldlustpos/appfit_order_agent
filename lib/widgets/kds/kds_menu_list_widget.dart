import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../constants/app_styles.dart';
import '../../constants/card_types.dart';
import '../../i18n/strings.g.dart';
import '../../models/order_menu_model.dart';
import '../../models/order_model.dart';
import '../../providers/providers.dart';
import 'kds_card_metrics.dart';

/// 단일 메뉴 줄 + 옵션 목록 표시.
class KdsMenuItemWidget extends StatelessWidget {
  final OrderMenuModel menu;
  final bool isChecked;
  final bool isCancelled;
  final VoidCallback? onTap;
  final int menuIndex;

  const KdsMenuItemWidget({
    super.key,
    required this.menu,
    required this.isChecked,
    required this.isCancelled,
    this.onTap,
    required this.menuIndex,
  });

  static String _truncate(String name) {
    if (name.length <= KdsCardMetrics.maxMenuNameLength) return name;
    return '${name.substring(0, KdsCardMetrics.maxMenuNameLength)}...';
  }

  @override
  Widget build(BuildContext context) {
    // 색상/취소선은 한 번만 계산해 모든 텍스트가 공유한다.
    final muted = isCancelled || isChecked;
    final textColor = muted ? AppStyles.gray6 : Colors.black;
    final textDecoration =
        muted ? TextDecoration.lineThrough : TextDecoration.none;
    final baseStyle = TextStyle(
      fontSize: AppStyles.kOrderCardTimeSize,
      color: textColor,
      decoration: textDecoration,
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
              children: [
                Expanded(
                  child: Text(
                    _truncate(menu.itemName.replaceAll('\\n', '')),
                    style: baseStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(t.kds.item_qty(n: menu.qty), style: baseStyle),
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
                        children: [
                          Expanded(
                            child: Text(
                              '- ${option.optionName}',
                              style: baseStyle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.s4),
                          Text(
                            option.qty == 1
                                ? ''
                                : t.kds.item_qty(n: option.qty),
                            style: baseStyle,
                          ),
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
