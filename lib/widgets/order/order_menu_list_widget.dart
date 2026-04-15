import 'package:flutter/material.dart';
import 'package:appfit_order_agent/constants/app_styles.dart';
import 'package:appfit_order_agent/models/order_menu_model.dart';
import 'package:appfit_order_agent/utils/common_util.dart';
import 'package:appfit_order_agent/i18n/strings.g.dart';

class OrderMenuListWidget extends StatelessWidget {
  final List<OrderMenuModel> menus;
  final ScrollController scrollController;
  final String currencySymbol;
  final int orderCount;

  const OrderMenuListWidget({
    super.key,
    required this.menus,
    required this.scrollController,
    required this.currencySymbol,
    required this.orderCount,
  });

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.bLg,
        boxShadow: AppElevation.soft,
      ),
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.order.count_items(n: orderCount),
            style: AppTextStyles.titleSm,
          ),
          const SizedBox(height: AppSpacing.s8),
          const Divider(height: 1, color: AppStyles.gray3),
          const SizedBox(height: AppSpacing.s4),
          if (menus.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  t.order.menu_no_info,
                  style: AppTextStyles.body.copyWith(color: AppStyles.gray6),
                ),
              ),
            )
          else
            Expanded(
              child: RawScrollbar(
                thumbVisibility: true,
                radius: const Radius.circular(AppRadius.sm),
                thickness: AppSpacing.s4,
                controller: scrollController,
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: menus.length,
                  itemBuilder: (context, index) {
                    final menu = menus[index];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.s12,
                            horizontal: AppSpacing.s8,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 5,
                                child: Text(
                                  menu.itemName.replaceAll('\\n', ''),
                                  style: AppTextStyles.body.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  t.order.qty(n: menu.qty.toString()),
                                  textAlign: TextAlign.center,
                                  style: AppTextStyles.body,
                                ),
                              ),
                              Expanded(
                                flex: 3,
                                child: Text(
                                  CommonUtil.formatPrice(
                                    menu.itemPrice,
                                    currencyUnit: currencySymbol,
                                  ),
                                  textAlign: TextAlign.right,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.body.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        ...menu.options.map(
                          (option) => Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.s4,
                              horizontal: AppSpacing.s8,
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.subdirectory_arrow_right,
                                  size: 14,
                                  color: AppStyles.gray6,
                                ),
                                const SizedBox(width: AppSpacing.s4),
                                Expanded(
                                  flex: 5,
                                  child: Text(
                                    option.optionName,
                                    style: AppTextStyles.bodySm.copyWith(
                                      color: AppStyles.gray6,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    t.order.qty(n: option.qty.toString()),
                                    textAlign: TextAlign.center,
                                    style: AppTextStyles.bodySm.copyWith(
                                      color: AppStyles.gray6,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    option.optionPrice != 0
                                        ? CommonUtil.formatPrice(
                                            option.optionPrice * option.qty,
                                            currencyUnit: currencySymbol,
                                          )
                                        : '-',
                                    textAlign: TextAlign.right,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTextStyles.bodySm.copyWith(
                                      color: AppStyles.gray6,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const Divider(height: 1, color: AppStyles.gray3),
                      ],
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}
