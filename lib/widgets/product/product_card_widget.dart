import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:appfit_order_agent/constants/app_styles.dart';
import 'package:appfit_order_agent/providers/currency_provider.dart';
import 'package:appfit_order_agent/services/platform_service.dart';
import 'package:appfit_order_agent/utils/common_util.dart';
import 'package:appfit_order_agent/models/product_model.dart';
import 'package:appfit_order_agent/providers/product_provider.dart';
import 'package:appfit_order_agent/widgets/common/common_dialog.dart';
import 'package:appfit_order_agent/i18n/strings.g.dart';

class ProductCardWidget extends ConsumerStatefulWidget {
  final ProductModel product;

  const ProductCardWidget({
    Key? key,
    required this.product,
  }) : super(key: key);

  @override
  ConsumerState<ProductCardWidget> createState() => _ProductCardWidgetState();
}

class _ProductCardWidgetState extends ConsumerState<ProductCardWidget> {
  bool _isUpdating = false;

  Future<void> _applyStatus(ProductStatus newStatus) async {
    if (_isUpdating) return;
    setState(() => _isUpdating = true);
    try {
      final ok = await ref
          .read(productProvider.notifier)
          .updateProductStatus(widget.product.productId, newStatus);
      if (ok && newStatus == ProductStatus.hidden && mounted) {
        ref.read(productProvider.notifier).refresh();
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Future<void> _showStatusChangeDialog() async {
    if (_isUpdating) return;
    logToFile(
        tag: LogTag.UI_ACTION,
        message:
            '상품 선택: ${widget.product.productName} : ${widget.product.productId}');

    final selectedStatus = await CommonDialog.showStatusChangeDialog(
      context: context,
      itemName: widget.product.productName,
      currentStatus: widget.product.status,
    );
    if (!mounted) return;
    if (selectedStatus == null || selectedStatus == widget.product.status) {
      return;
    }

    if (selectedStatus == ProductStatus.hidden) {
      final confirmed = await CommonDialog.showConfirmDialog(
        context: context,
        title: t.product_mgmt.dialog_hidden_title,
        content: t.product_mgmt
            .dialog_hidden_content(name: widget.product.productName),
        confirmText: t.product_mgmt.btn_hidden,
        cancelText: t.common.cancel,
      );
      if (confirmed != true || !mounted) return;
    }

    await _applyStatus(selectedStatus);
  }

  @override
  Widget build(BuildContext context) {
    final currencySymbol = ref.watch(currencySymbolProvider);
    final isSoldOut = widget.product.status == ProductStatus.soldOut;

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
          child: Stack(
            children: [
              InkWell(
                onTap: _isUpdating ? null : _showStatusChangeDialog,
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
                              widget.product.productName,
                              style: AppTextStyles.titleSm.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: AppSpacing.s8),
                            Text(
                              CommonUtil.formatPrice(widget.product.menuPrice,
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
              if (_isUpdating)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.55),
                        borderRadius: AppRadius.bLg,
                      ),
                      alignment: Alignment.center,
                      child: const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
