import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dotted_line/dotted_line.dart';
import '../../constants/app_styles.dart';
import '../../constants/card_types.dart';
import '../../models/order_model.dart';
import '../../models/order_menu_model.dart';
import '../../i18n/strings.g.dart';

import '../../providers/providers.dart';

// 공통 메뉴 아이템 위젯
class KdsMenuItemWidget extends StatelessWidget {
  final OrderMenuModel menu;
  final bool isChecked;
  final bool isCancelled;
  final VoidCallback? onTap;
  final int menuIndex;

  const KdsMenuItemWidget({
    Key? key,
    required this.menu,
    required this.isChecked,
    required this.isCancelled,
    this.onTap,
    required this.menuIndex,
  }) : super(key: key);

  // 메뉴 이름을 13자로 제한하고 말줄임표 추가
  String _truncateMenuName(String menuName) {
    if (menuName.length <= 12) {
      return menuName;
    }
    return '${menuName.substring(0, 12)}...';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: isChecked ? AppStyles.kCheckedBgColor : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 메뉴 항목
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _truncateMenuName(menu.itemName.replaceAll('\\n', '')),
                        style: TextStyle(
                          fontSize: AppStyles.kOrderCardTimeSize,
                          color: isCancelled
                              ? AppStyles.gray6
                              : (isChecked ? AppStyles.gray6 : Colors.black),
                          decoration: isCancelled
                              ? TextDecoration.lineThrough
                              : (isChecked
                                  ? TextDecoration.lineThrough
                                  : TextDecoration.none),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      t.kds.item_qty(n: menu.qty),
                      style: TextStyle(
                        fontSize: AppStyles.kOrderCardTimeSize,
                        color: isCancelled
                            ? AppStyles.gray6
                            : (isChecked ? AppStyles.gray6 : Colors.black),
                        decoration: isCancelled
                            ? TextDecoration.lineThrough
                            : (isChecked
                                ? TextDecoration.lineThrough
                                : TextDecoration.none),
                      ),
                    ),
                  ],
                ),
                // 옵션 목록
                if (menu.options.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 15, top: 2),
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
                                  style: TextStyle(
                                    fontSize: AppStyles.kOrderCardTimeSize,
                                    color: isCancelled
                                        ? AppStyles.gray6
                                        : (isChecked
                                            ? AppStyles.gray6
                                            : Colors.black),
                                    decoration: isCancelled
                                        ? TextDecoration.lineThrough
                                        : (isChecked
                                            ? TextDecoration.lineThrough
                                            : TextDecoration.none),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                option.qty == 1
                                    ? ''
                                    : t.kds.item_qty(n: option.qty),
                                style: TextStyle(
                                  fontSize: AppStyles.kOrderCardTimeSize,
                                  color: isCancelled
                                      ? AppStyles.gray6
                                      : (isChecked
                                          ? AppStyles.gray6
                                          : Colors.black),
                                  decoration: isCancelled
                                      ? TextDecoration.lineThrough
                                      : (isChecked
                                          ? TextDecoration.lineThrough
                                          : TextDecoration.none),
                                ),
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
        ],
      ),
    );
  }
}

// 간단한 메뉴 리스트 위젯
class KdsMenuListWidget extends ConsumerWidget {
  final List<OrderMenuModel> menuList;
  final OrderModel order;
  final CardType cardType;

  const KdsMenuListWidget({
    Key? key,
    required this.menuList,
    required this.order,
    required this.cardType,
  }) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final checkedItems = ref.watch(kdsCheckedItemsProvider);
    final isCancelledTab = cardType == CardType.cancelled;
    final isProgressTab = order.status == OrderStatus.PREPARING;

    // 메뉴 상세 정보가 아직 로드되지 않은 경우
    if (!order.isDetailLoaded) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(height: 8),
              Text(
                t.kds.loading_detail,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 메뉴 리스트가 비어있는 경우 (로딩 완료된 상태)
    if (menuList.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.warning_amber_rounded, size: 20, color: Colors.grey),
            SizedBox(height: 8),
            Text(
              t.kds.no_menu_info,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: menuList.asMap().entries.map((entry) {
        final menuIndex = entry.key;
        final menu = entry.value;
        // 진행 탭에서만 체크 상태 적용
        final isChecked = isProgressTab
            ? (checkedItems[order.orderId]?.contains(menuIndex) ?? false)
            : false;

        return Column(
          children: [
            KdsMenuItemWidget(
              menu: menu,
              isChecked: isChecked,
              isCancelled: isCancelledTab,
              menuIndex: menuIndex,
              onTap: () {
                ref.read(orderProvider.notifier).stopBlinking();
                if (order.status != OrderStatus.PREPARING) return;

                ref
                    .read(kdsCheckedItemsProvider.notifier)
                    .toggle(order.orderId, menuIndex, !isChecked);
              },
            ),
            // 메뉴 간 점선 구분선 (마지막 메뉴가 아닌 경우)
            if (menuIndex < menuList.length - 1)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: DottedLine(
                  dashColor: AppStyles.gray4,
                  dashLength: 1,
                ),
              ),
          ],
        );
      }).toList(),
    );
  }
}
// 간단한 메뉴 리스트 위젯
