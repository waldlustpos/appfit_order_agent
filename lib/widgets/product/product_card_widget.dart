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
      if (!context.mounted) return;

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
    final isSoldOut = product.status == ProductStatus.soldOut;

    final borderColor = isSoldOut ? AppStyles.kMainColor : AppStyles.gray3;
    final borderWidth = isSoldOut ? 1.5 : 1.0;
    final bgColor =
        isSoldOut ? AppStyles.kMainColor.withValues(alpha: 0.08) : Colors.white;

    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.all(AppSpacing.s4),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: AppRadius.bLg,
          border: Border.all(color: borderColor, width: borderWidth),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: AppRadius.bLg,
          child: InkWell(
            onTap: () => _showStatusChangeDialog(context, ref),
            borderRadius: AppRadius.bLg,
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.s8),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          product.productName,
                          style: AppTextStyles.titleSm.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: AppSpacing.s8),
                        Text(
                          CommonUtil.formatPrice(product.menuPrice,
                              currencyUnit: currencySymbol),
                          style: AppTextStyles.body.copyWith(
                            color: AppStyles.gray6,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (isSoldOut)
                  Positioned(
                    top: AppSpacing.s8,
                    left: AppSpacing.s8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.s8,
                        vertical: AppSpacing.s4,
                      ),
                      decoration: BoxDecoration(
                        color: AppStyles.kMainColor,
                        borderRadius: AppRadius.bMd,
                      ),
                      child: Text(
                        t.product_mgmt.sold_out,
                        style: AppTextStyles.caption.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
