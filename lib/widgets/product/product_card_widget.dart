import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:appfit_order_agent/constants/app_styles.dart';
import 'package:appfit_order_agent/providers/currency_provider.dart';
import 'package:appfit_order_agent/services/platform_service.dart';
import 'package:appfit_order_agent/utils/common_util.dart';
import '../../models/product_model.dart';
import '../../providers/product_provider.dart';
import '../common/common_dialog.dart';
import '../../i18n/strings.g.dart';

class ProductCardWidget extends ConsumerWidget {
  final ProductModel product;

  const ProductCardWidget({
    Key? key,
    required this.product,
  }) : super(key: key);

  void _showStatusChangeDialog(BuildContext context, WidgetRef ref) {
    logToFile(
        tag: LogTag.UI_ACTION,
        message: '상품 선택: ${product.productName} : ${product.productId}');

    CommonDialog.showStatusChangeDialog(
      context: context,
      itemName: product.productName,
      currentStatus: product.status,
    ).then((selectedStatus) {
      if (selectedStatus == null || selectedStatus == product.status) return;

      // 미노출 선택 시 재확인 다이얼로그 표시
      if (selectedStatus == ProductStatus.hidden) {
        CommonDialog.showConfirmDialog(
          context: context,
          title: t.product_mgmt.dialog_hidden_title,
          content:
              t.product_mgmt.dialog_hidden_content(name: product.productName),
          confirmText: t.product_mgmt.btn_hidden,
          cancelText: t.common.cancel,
        ).then((confirmed) {
          if (confirmed == true) {
            ref
                .read(productProvider.notifier)
                .updateProductStatus(product.productId, selectedStatus)
                .then((success) {
              if (success) {
                // 미노출 처리 시 목록 새로고침
                ref.read(productProvider.notifier).refresh();
              }
            });
          }
        });
      } else {
        ref
            .read(productProvider.notifier)
            .updateProductStatus(product.productId, selectedStatus);
      }
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currencySymbol = ref.watch(currencySymbolProvider);
    return GestureDetector(
      onTap: () => _showStatusChangeDialog(context, ref),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(16)),
          side: BorderSide(
            color: product.status != ProductStatus.soldOut
                ? Colors.grey[400]!
                : AppStyles.kMainColor,
            width: 1,
          ),
        ),
        color: product.status == ProductStatus.soldOut
            ? AppStyles.kMainColor.withValues(alpha: 0.1)
            : Colors.white,
        margin: const EdgeInsets.all(4),
        child: Stack(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      product.productName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      CommonUtil.formatPrice(product.menuPrice, currencyUnit: currencySymbol),
                      style: const TextStyle(
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (product.status == ProductStatus.soldOut)
              Positioned(
                top: 0,
                left: 0,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: const BoxDecoration(
                    color: AppStyles.kMainColor,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                  ),
                  child: Text(
                    t.product_mgmt.sold_out,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
