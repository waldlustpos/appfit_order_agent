import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:appfit_order_agent/constants/app_styles.dart';
import 'package:shimmer/shimmer.dart';
import '../providers/product_provider.dart';
import '../widgets/product/product_card_widget.dart';
import '../models/product_model.dart';
import '../i18n/strings.g.dart';

class ProductManagementScreen extends ConsumerStatefulWidget {
  const ProductManagementScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<ProductManagementScreen> createState() =>
      _ProductManagementScreenState();
}

class _ProductManagementScreenState
    extends ConsumerState<ProductManagementScreen> {
  final TextEditingController _searchController = TextEditingController();
  String? _selectedCategory;
  String _searchQuery = '';

  final ScrollController _categoryScrollController = ScrollController();
  final ScrollController _productScrollController = ScrollController();

  @override
  void dispose() {
    _searchController.dispose();
    _categoryScrollController.dispose();
    _productScrollController.dispose();
    super.dispose();
  }

  Map<String, int> _getCategoryCounts(List<ProductModel> products) {
    final Map<String, int> counts = {};
    for (var product in products) {
      counts[product.categoryName] = (counts[product.categoryName] ?? 0) + 1;
    }
    return counts;
  }

  int _getAllUniqueCount(List<ProductModel> products) {
    final seen = <String>{};
    return products
        .where((p) => p.status != ProductStatus.hidden)
        .where((p) => seen.add(p.internalId))
        .length;
  }

  List<ProductModel> _getFilteredProducts(List<ProductModel> products) {
    final base = products.where((product) {
      if (product.status == ProductStatus.hidden) return false;
      return product.productName
          .toLowerCase()
          .contains(_searchQuery.toLowerCase());
    });

    Iterable<ProductModel> filtered;
    if (_selectedCategory == t.product_mgmt.sold_out) {
      filtered = base.where((p) => p.status == ProductStatus.soldOut);
    } else if (_selectedCategory == null) {
      final seen = <String>{};
      filtered = base.where((p) => seen.add(p.internalId));
    } else {
      filtered = base.where((p) => p.categoryName == _selectedCategory);
    }

    return filtered.toList();
  }

  Widget _buildCategoryTile(
    String title,
    int count,
    bool isSelected, {
    bool isAllCategory = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s8,
        vertical: AppSpacing.s4,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: AppRadius.bMd,
        child: InkWell(
          borderRadius: AppRadius.bMd,
          onTap: () {
            FocusScope.of(context).unfocus();
            setState(() {
              if (isAllCategory) {
                _selectedCategory = null;
              } else {
                _selectedCategory = isSelected ? null : title;
              }
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s12,
              vertical: AppSpacing.s12,
            ),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppStyles.kMainColor.withValues(alpha: 0.08)
                  : Colors.transparent,
              borderRadius: AppRadius.bMd,
              border: isSelected
                  ? Border.all(color: AppStyles.kMainColor, width: 1)
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: AppTextStyles.body.copyWith(
                      color:
                          isSelected ? AppStyles.kMainColor : AppStyles.gray9,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppSpacing.s8),
                Text(
                  t.product_mgmt.count(n: count.toString()),
                  style: AppTextStyles.bodySm.copyWith(
                    color: isSelected ? AppStyles.kMainColor : AppStyles.gray6,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorColumn(Object error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: AppStyles.kRed, size: 48),
          const SizedBox(height: AppSpacing.s16),
          Text(
            t.product_mgmt.error_load(error: error.toString()),
            textAlign: TextAlign.center,
            style: AppTextStyles.body.copyWith(color: AppStyles.gray6),
          ),
          const SizedBox(height: AppSpacing.s24),
          ElevatedButton.icon(
            icon: const Icon(Icons.refresh),
            label: Text(t.common.refresh),
            onPressed: () => ref.read(productProvider.notifier).refresh(),
            style: AppStyles.primaryButton(),
          ),
        ],
      ),
    );
  }

  // ─── 좌측 패널 (카테고리 + 검색) ────────────────────────────────────────

  Widget _buildLeftPanel() {
    return Container(
      margin: const EdgeInsets.only(
        left: AppSpacing.s12,
        top: AppSpacing.s4,
        bottom: AppSpacing.s4,
        right: AppSpacing.s4,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.bLg,
        boxShadow: AppElevation.soft,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.s12),
            child: TextField(
              controller: _searchController,
              decoration: AppStyles.filledInputDecoration(
                hintText: t.product_mgmt.search_placeholder,
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
          Expanded(
            child: Consumer(
              builder: (context, ref, child) {
                final productsAsync = ref.watch(productProvider);
                return productsAsync.when(
                  data: (products) {
                    final categoryCounts = _getCategoryCounts(products);
                    final categories = categoryCounts.keys.toList()..sort();

                    return RawScrollbar(
                      radius: const Radius.circular(AppRadius.sm),
                      thumbColor: AppStyles.gray4,
                      fadeDuration: const Duration(milliseconds: 300),
                      controller: _categoryScrollController,
                      child: ListView.builder(
                        controller: _categoryScrollController,
                        itemCount: categories.length + 2,
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            final allCount = _getAllUniqueCount(products);
                            final isSelected = _selectedCategory == null;
                            return _buildCategoryTile(
                              t.product_mgmt.all,
                              allCount,
                              isSelected,
                              isAllCategory: true,
                            );
                          }
                          if (index == 1) {
                            final soldOutCount = products
                                .where((p) => p.status == ProductStatus.soldOut)
                                .length;
                            final isSelected =
                                _selectedCategory == t.product_mgmt.sold_out;
                            return _buildCategoryTile(t.product_mgmt.sold_out,
                                soldOutCount, isSelected);
                          }
                          final category = categories[index - 2];
                          final count = categoryCounts[category]!;
                          final isSelected = category == _selectedCategory;
                          return _buildCategoryTile(
                              category, count, isSelected);
                        },
                      ),
                    );
                  },
                  loading: () => const _ProductGridSkeleton(),
                  error: (error, _) => _buildErrorColumn(error),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ─── 우측 패널 (헤더 + 그리드) ───────────────────────────────────────────

  Widget _buildRightPanel() {
    return Container(
      margin: const EdgeInsets.only(
        left: AppSpacing.s4,
        top: AppSpacing.s4,
        bottom: AppSpacing.s4,
        right: AppSpacing.s12,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.bLg,
        boxShadow: AppElevation.soft,
      ),
      clipBehavior: Clip.antiAlias,
      child: Consumer(
        builder: (context, ref, child) {
          final productsAsync = ref.watch(productProvider);
          return productsAsync.when(
            data: (products) {
              final filteredProducts = _getFilteredProducts(products);
              return Column(
                children: [
                  // 헤더
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s16,
                      vertical: AppSpacing.s12,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          t.product_mgmt
                              .total_count(n: filteredProducts.length),
                          style: AppTextStyles.titleSm
                              .copyWith(color: AppStyles.gray9),
                        ),
                        IconButton(
                          onPressed: () =>
                              ref.read(productProvider.notifier).refresh(),
                          icon: const Icon(
                            Icons.refresh_outlined,
                            size: 28,
                          ),
                          color: AppStyles.kMainColor,
                        ),
                      ],
                    ),
                  ),
                  const Divider(
                    color: AppStyles.gray3,
                    height: 1,
                    thickness: 1,
                  ),
                  // 그리드
                  Expanded(
                    child: RawScrollbar(
                      radius: const Radius.circular(AppRadius.sm),
                      thumbColor: AppStyles.gray4,
                      fadeDuration: const Duration(milliseconds: 300),
                      controller: _productScrollController,
                      child: GridView.builder(
                        controller: _productScrollController,
                        padding: const EdgeInsets.all(AppSpacing.s8),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 5,
                          childAspectRatio: 1,
                          crossAxisSpacing: AppSpacing.s8,
                          mainAxisSpacing: AppSpacing.s8,
                        ),
                        itemCount: filteredProducts.length,
                        itemBuilder: (context, index) => ProductCardWidget(
                          product: filteredProducts[index],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
            loading: () => const _ProductGridSkeleton(),
            error: (error, _) => _buildErrorColumn(error),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.translucent,
      child: ColoredBox(
        color: AppStyles.gray1,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: MediaQuery.sizeOf(context).width * 0.25,
              child: _buildLeftPanel(),
            ),
            Expanded(child: _buildRightPanel()),
          ],
        ),
      ),
    );
  }
}

/// 상품 관리 로딩 시 shimmer 스켈레톤 그리드
class _ProductGridSkeleton extends StatelessWidget {
  const _ProductGridSkeleton();

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(AppSpacing.s8),
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        childAspectRatio: 1,
        crossAxisSpacing: AppSpacing.s8,
        mainAxisSpacing: AppSpacing.s8,
      ),
      itemCount: 10,
      itemBuilder: (context, index) => Shimmer.fromColors(
        baseColor: AppStyles.gray2,
        highlightColor: AppStyles.gray1,
        child: Container(
          margin: const EdgeInsets.all(AppSpacing.s4),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: AppRadius.bLg,
          ),
        ),
      ),
    );
  }
}
