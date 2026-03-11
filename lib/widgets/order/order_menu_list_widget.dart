import 'package:flutter/material.dart';
import 'package:appfit_order_agent/models/order_menu_model.dart';
import 'package:appfit_order_agent/utils/common_util.dart';
import 'package:appfit_order_agent/i18n/strings.g.dart';

class OrderMenuListWidget extends StatelessWidget {
  final List<OrderMenuModel> menus;
  final ScrollController scrollController;

  const OrderMenuListWidget({
    super.key,
    required this.menus,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);

    if (menus.isEmpty) {
      return Center(child: Text(t.order.menu_no_info));
    }

    return RawScrollbar(
      thumbVisibility: true,
      radius: const Radius.circular(10),
      thickness: 5,
      controller: scrollController,
      child: ListView.builder(
        controller: scrollController,
        itemCount: menus.length,
        itemBuilder: (context, index) {
          final menu = menus[index];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                child: Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: Text(
                        menu.itemName.replaceAll('\\n', ''),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        t.order.qty(n: menu.qty.toString()),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        CommonUtil.formatPrice(menu.itemPrice / menu.qty),
                        textAlign: TextAlign.right,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              ...menu.options.map((option) => Container(
                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 5,
                          child: Text(
                            '   - ${option.optionName}',
                            style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            t.order.qty(n: option.qty.toString()),
                            style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            option.optionPrice != 0
                                ? CommonUtil.formatPrice(option.optionPrice * option.qty)
                                : '-',
                            style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                            textAlign: TextAlign.right,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  )),
              const Divider(),
            ],
          );
        },
      ),
    );
  }
}
