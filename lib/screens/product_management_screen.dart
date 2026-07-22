import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:appfit_order_agent/constants/app_styles.dart';
import 'package:shimmer/shimmer.dart';
import 'package:appfit_order_agent/providers/product_provider.dart';
import 'package:appfit_order_agent/services/platform_service.dart';
import 'package:appfit_order_agent/widgets/product/product_card_widget.dart';
import 'package:appfit_order_agent/models/product_model.dart';
import 'package:appfit_order_agent/models/shop_category_model.dart';
import 'package:appfit_order_agent/i18n/strings.g.dart';

class ProductManagementScreen extends ConsumerStatefulWidget {
  const ProductManagementScreen({super.key});

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

  /// 카테고리별 카운트 — 해당 카테고리를 선택했을 때 그리드에 실제로 표시되는 수.
  ///
  /// [_visibleBase] 를 통과시키므로 hidden 제외·검색어 반영이 그리드와 동일하다
  /// ("N개라고 써 있는데 눌러보면 비어 있음" 방지).
  Map<String, int> _getCategoryCounts(List<ProductModel> products) {
    final Map<String, int> counts = {};
    for (var product in _visibleBase(products)) {
      counts[product.categoryName] = (counts[product.categoryName] ?? 0) + 1;
    }
    return counts;
  }

  /// 좌측 목록에 표시할 카테고리명 정본.
  ///
  /// 서버 카테고리를 기준으로 삼아 **소속 상품이 0개인 카테고리도 노출**한다
  /// (상품에서 역산하면 빈 카테고리는 표현 자체가 불가능).
  /// 옵션 버킷('옵션')은 서버 카테고리가 아닌 앱의 인공 그룹이라 상품에서 보충하며,
  /// 서버 목록을 아직 못 받았으면 전량 상품에서 역산해 기존 동작으로 폴백한다.
  List<String> _getCategoryNames(
    List<ProductModel> products,
    List<ShopCategoryModel>? serverCategories,
  ) {
    final names = <String>{
      if (serverCategories != null)
        ...serverCategories.map((c) => c.categoryName),
      ...products.map((p) => p.categoryName),
    };
    return names.toList()..sort();
  }

  /// 화면에 노출될 수 있는 상품의 공통 base — hidden 제외 + 검색어 적용.
  ///
  /// 좌측 카운트와 우측 그리드가 **반드시 같은 base** 를 쓰도록 한 곳에 모았다.
  Iterable<ProductModel> _visibleBase(List<ProductModel> products) {
    final query = _searchQuery.toLowerCase();
    return products.where((product) {
      if (product.status == ProductStatus.hidden) return false;
      return product.productName.toLowerCase().contains(query);
    });
  }

  /// [category] 를 선택했을 때 그리드에 표시되는 상품 목록.
  ///
  /// `null` = 전체, [t.product_mgmt.sold_out] = 품절, 그 외 = 카테고리명.
  /// 좌측 타일 카운트도 이 결과의 길이와 일치해야 한다(그리드 = 카운트 단일 정본).
  ///
  /// 전체만 `internalId` 로 중복을 제거한다 — 같은 상품이 여러 카테고리에 속할 수
  /// 있어 카테고리별 합계는 전체보다 클 수 있고, 그게 정상이다.
  List<ProductModel> _productsFor(
    List<ProductModel> products,
    String? category,
  ) {
    final base = _visibleBase(products);

    if (category == t.product_mgmt.sold_out) {
      return base.where((p) => p.status == ProductStatus.soldOut).toList();
    }
    if (category == null) {
      final seen = <String>{};
      return base.where((p) => seen.add(p.internalId)).toList();
    }
    return base.where((p) => p.categoryName == category).toList();
  }

  List<ProductModel> _getFilteredProducts(List<ProductModel> products) =>
      _productsFor(products, _selectedCategory);

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
            logToFile(tag: LogTag.UI_ACTION, message: '상품관리 카테고리 선택: $title');
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
            onPressed: () {
              logToFile(tag: LogTag.UI_ACTION, message: '상품관리 새로고침 버튼 터치');
              ref.read(productProvider.notifier).refresh();
            },
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
                // 카테고리명은 서버 목록이 정본(상품 0개 카테고리 포함). 카운트는
                // updateProductStatus 의 낙관적 갱신에 반응해야 하므로 계속
                // productProvider 에서 파생한다.
                final serverCategories =
                    ref.watch(shopCategoryListProvider).valueOrNull;
                return productsAsync.when(
                  data: (products) {
                    final categoryCounts = _getCategoryCounts(products);
                    final categories =
                        _getCategoryNames(products, serverCategories);
                    // 타일마다 재계산하지 않도록 build 당 1회만 집계한다.
                    final allCount = _productsFor(products, null).length;
                    final soldOutCount =
                        _productsFor(products, t.product_mgmt.sold_out).length;

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
                            final isSelected = _selectedCategory == null;
                            return _buildCategoryTile(
                              t.product_mgmt.all,
                              allCount,
                              isSelected,
                              isAllCategory: true,
                            );
                          }
                          if (index == 1) {
                            final isSelected =
                                _selectedCategory == t.product_mgmt.sold_out;
                            return _buildCategoryTile(t.product_mgmt.sold_out,
                                soldOutCount, isSelected);
                          }
                          final category = categories[index - 2];
                          // 서버에만 있고 상품이 0개인 카테고리는 counts 에 항목이
                          // 없다 — 널 단언 대신 0 으로 표시한다.
                          final count = categoryCounts[category] ?? 0;
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
                          onPressed: () {
                            logToFile(
                                tag: LogTag.UI_ACTION,
                                message: '상품관리 새로고침 버튼 터치');
                            ref.read(productProvider.notifier).refresh();
                          },
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
