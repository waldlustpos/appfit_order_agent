import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:appfit_order_agent/constants/app_styles.dart';
import 'package:appfit_order_agent/providers/currency_provider.dart';
import 'package:appfit_order_agent/services/platform_service.dart';
import 'package:appfit_order_agent/utils/common_util.dart';
import 'package:appfit_order_agent/models/product_group.dart';
import 'package:appfit_order_agent/models/product_model.dart';
import 'package:appfit_order_agent/providers/product_provider.dart';
import 'package:appfit_order_agent/widgets/common/common_dialog.dart';
import 'package:appfit_order_agent/i18n/strings.g.dart';

/// 상품관리 그리드의 카드 1장 = 동일 상품명 그룹.
///
/// 이름이 같고 가격만 다른 레코드(주로 옵션)를 한 장으로 묶어 **일괄** 품절/판매
/// 전환한다. 그룹은 all-or-nothing 이 정책 전제라 카드 배지는 전원 품절일 때만
/// 품절을 표시한다.
class ProductCardWidget extends ConsumerStatefulWidget {
  final ProductGroup group;

  const ProductCardWidget({
    super.key,
    required this.group,
  });

  @override
  ConsumerState<ProductCardWidget> createState() => _ProductCardWidgetState();
}

class _ProductCardWidgetState extends ConsumerState<ProductCardWidget> {
  bool _isUpdating = false;

  Future<void> _applyStatus(ProductStatus newStatus) async {
    if (_isUpdating) return;
    setState(() => _isUpdating = true);
    try {
      final ok = await ref.read(productProvider.notifier).updateProductsStatus(
            type: widget.group.type,
            internalIds: widget.group.internalIds,
            newStatus: newStatus,
          );
      if (!ok && mounted) {
        // 일괄 처리는 "눌렀는데 아무 일도 안 일어남"이 특히 위험하다 — 점주는
        // 품절 처리된 줄 알고 넘어간다. 실패를 명시하고 서버 정본으로 되맞춘다.
        await CommonDialog.showInfoDialog(
          context: context,
          title: t.common.error_title,
          content: t.product_mgmt.error_status_update,
          dedupeKey: 'product-status-update-failed',
        );
        if (mounted) ref.read(productProvider.notifier).refresh();
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Future<void> _showStatusChangeDialog() async {
    if (_isUpdating) return;
    final group = widget.group;
    logToFile(
      tag: LogTag.UI_ACTION,
      message: '상품 그룹 선택: ${group.name}(${group.type.code}) '
          '멤버 ${group.memberCount} 가격 ${group.prices.length}종',
    );

    // 통화기호 해석은 위젯 계층 책임 — CommonDialog 는 static 이라 ref 가 없다.
    final symbol = ref.read(currencySymbolProvider);
    final selectedStatus = await CommonDialog.showBulkStatusChangeDialog(
      context: context,
      itemName: group.name,
      currentStatus: group.status,
      memberCount: group.memberCount,
      priceLabels: [
        for (final price in group.prices)
          CommonUtil.formatPrice(price, currencyUnit: symbol),
      ],
      categoryNames: group.categoryNames,
    );
    if (!mounted || selectedStatus == null) return;

    // 이미 전원이 그 상태면 서버 왕복이 무의미하다. 다만 혼합 그룹은 표시 상태가
    // 같아 보여도 정합성을 맞추기 위한 호출이 필요하므로 통과시킨다.
    if (!group.isMixed && selectedStatus == group.status) return;

    await _applyStatus(selectedStatus);
  }

  @override
  Widget build(BuildContext context) {
    final currencySymbol = ref.watch(currencySymbolProvider);
    final group = widget.group;
    final isSoldOut = group.isSoldOut;

    // 묶인 카드는 가격 대신 몇 건이 묶였는지를 보여준다 — 가격이 여러 종일 때
    // 카드 한 줄에 다 담을 수 없고, 개별 가격은 탭 후 다이얼로그에서 확인한다.
    final subtitleText = group.memberCount > 1
        ? t.product_mgmt.same_product_count(n: group.memberCount)
        : CommonUtil.formatPrice(group.minPrice, currencyUnit: currencySymbol);

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
                              group.name,
                              style: AppTextStyles.titleSm.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: AppSpacing.s8),
                            // 5열 그리드라 문자열이 카드 폭을 넘길 수 있다 —
                            // 줄바꿈·잘림 대신 축소해 한 줄을 유지한다.
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                subtitleText,
                                maxLines: 1,
                                softWrap: false,
                                style: AppTextStyles.body.copyWith(
                                  color: AppStyles.gray6,
                                ),
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
