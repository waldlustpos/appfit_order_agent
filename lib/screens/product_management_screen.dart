import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:appfit_order_agent/constants/app_styles.dart';
import 'package:shimmer/shimmer.dart';
import 'package:appfit_order_agent/core/products/product_grouping.dart';
import 'package:appfit_order_agent/providers/product_provider.dart';
import 'package:appfit_order_agent/services/platform_service.dart';
import 'package:appfit_order_agent/widgets/product/product_card_widget.dart';
import 'package:appfit_order_agent/models/product_group.dart';
import 'package:appfit_order_agent/models/product_model.dart';
import 'package:appfit_order_agent/models/shop_category_model.dart';
import 'package:appfit_order_agent/i18n/strings.g.dart';
import 'package:appfit_order_agent/utils/logger.dart';

class ProductManagementScreen extends ConsumerStatefulWidget {
  const ProductManagementScreen({super.key});

  @override
  ConsumerState<ProductManagementScreen> createState() =>
      _ProductManagementScreenState();
}

class _ProductManagementScreenState
    extends ConsumerState<ProductManagementScreen> {
  final TextEditingController _searchController = TextEditingController();
  ProductGroupFilter _filter = const AllGroups();
  String _searchQuery = '';

  final ScrollController _categoryScrollController = ScrollController();
  final ScrollController _productScrollController = ScrollController();

  /// 그룹핑 결과 메모 — 좌/우 패널이 각각 Consumer 라 build 당 여러 번 호출된다.
  /// 입력(상품 목록 인스턴스 + 검색어)이 같으면 재사용한다. setState 를 부르지
  /// 않는 순수 캐시라 build 중 갱신해도 안전하다.
  List<ProductModel>? _memoSource;
  String? _memoQuery;
  List<ProductGroup>? _memoGroups;

  @override
  void dispose() {
    _searchController.dispose();
    _categoryScrollController.dispose();
    _productScrollController.dispose();
    super.dispose();
  }

  /// 화면에 표시할 그룹 목록(hidden 제외 + 검색어 적용 후 `(이름, 타입)` 으로 묶음).
  List<ProductGroup> _groups(List<ProductModel> products) {
    if (identical(products, _memoSource) &&
        _memoQuery == _searchQuery &&
        _memoGroups != null) {
      return _memoGroups!;
    }
    final groups = buildProductGroups(visibleProducts(products, _searchQuery));
    _memoSource = products;
    _memoQuery = _searchQuery;
    _memoGroups = groups;
    return groups;
  }

  /// 좌측 목록에 표시할 카테고리명 정본.
  ///
  /// 서버가 내려준 목록 순서(list order)를 그대로 유지한다 — `displayOrder`
  /// 필드는 정렬 기준이 아니었음이 확인되어 더 이상 쓰지 않는다. 옵션 버킷
  /// ('옵션')처럼 서버 카테고리가 아닌 앱의 인공 그룹은 상품에서 보충해 뒤에
  /// 가나다순으로 덧붙이며, 서버 목록을 아직 못 받았으면(순서 정보 자체가
  /// 없으므로) 전량 상품에서 역산해 가나다순으로 폴백한다.
  /// 소속 상품이 0개인 카테고리(= [counts] 에 없거나 0)는 목록에서 제외한다.
  List<String> _getCategoryNames(
    List<ProductModel> products,
    List<ShopCategoryModel>? serverCategories,
    Map<String, int> counts,
  ) {
    final productCategoryNames = products.map((p) => p.categoryName).toSet();

    if (serverCategories == null) {
      return (productCategoryNames.toList()..sort())
          .where((name) => (counts[name] ?? 0) > 0)
          .toList();
    }

    final ordered = <String>{
      for (final category in serverCategories) category.categoryName,
    };
    final extras = productCategoryNames.difference(ordered).toList()..sort();

    if (ordered.length != serverCategories.length) {
      // categoryName 기준 Set 이라 서버가 같은 이름의 카테고리를 여러 개(다른
      // categoryPosId) 내려주면 여기서 조용히 합쳐진다 — "서버는 22개인데 화면은
      // 그보다 적다" 문의가 나오면 이 로그로 어느 이름이 중복인지 확인한다.
      final nameCounts = <String, int>{};
      for (final c in serverCategories) {
        nameCounts[c.categoryName] = (nameCounts[c.categoryName] ?? 0) + 1;
      }
      final duplicates = nameCounts.entries.where((e) => e.value > 1).toList();
      logger.w('[상품관리] 서버 카테고리 ${serverCategories.length}개 중 '
          '이름 기준 고유값은 ${ordered.length}개 — categoryName 중복: '
          '${duplicates.map((e) => '${e.key}(${e.value})').join(', ')}');
    }
    logger.d('[상품관리] 좌측 목록: 서버기반 ${ordered.length}개 + '
        '상품역산 추가 ${extras.length}개(${extras.join(', ')}) '
        '= 총 ${ordered.length + extras.length}개');

    return [...ordered, ...extras]
        .where((name) => (counts[name] ?? 0) > 0)
        .toList();
  }

  /// 좌측 타일 1개. [target] 은 이 타일이 선택하는 필터다.
  ///
  /// 선택 상태를 번역 문자열이 아니라 값 타입으로 비교하므로, 로케일을 바꿔도
  /// 선택이 풀리지 않고 '품절'이라는 이름의 실제 카테고리와도 충돌하지 않는다.
  Widget _buildCategoryTile(
    String title,
    int count,
    ProductGroupFilter target,
  ) {
    final isSelected = _filter == target;
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
              // 전체는 항상 전체. 나머지는 다시 누르면 전체로 되돌린다(기존 동작).
              _filter = (target is AllGroups || !isSelected)
                  ? target
                  : const AllGroups();
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
                // 입력이 있을 때만 초기화 버튼 노출
                suffixIcon: _searchQuery.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      ),
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
          Expanded(
            child: Consumer(
              builder: (context, ref, child) {
                final productsAsync = ref.watch(productProvider);
                // 카테고리명·순서는 서버 목록이 정본이나 상품 0개 카테고리는
                // 숨긴다. 카운트는 updateProductsStatus 의 낙관적 갱신에
                // 반응해야 하므로 계속 productProvider 에서 파생한다.
                final serverCategories =
                    ref.watch(shopCategoryListProvider).valueOrNull;
                return productsAsync.when(
                  data: (products) {
                    // 카운트 단위는 상품이 아니라 **카드(그룹)** 다 — 그리드와
                    // 같은 정본을 써야 "N개인데 눌러보면 다름"이 안 난다.
                    final groups = _groups(products);
                    final categoryCounts = productGroupCategoryCounts(groups);
                    final categories = _getCategoryNames(
                      products,
                      serverCategories,
                      categoryCounts,
                    );
                    // 타일마다 재계산하지 않도록 build 당 1회만 집계한다.
                    final allCount = groups.length;
                    final soldOutCount =
                        groups.where((g) => g.isSoldOut).length;

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
                            return _buildCategoryTile(
                              t.product_mgmt.all,
                              allCount,
                              const AllGroups(),
                            );
                          }
                          if (index == 1) {
                            return _buildCategoryTile(
                              t.product_mgmt.sold_out,
                              soldOutCount,
                              const SoldOutGroups(),
                            );
                          }
                          final category = categories[index - 2];
                          // 서버에만 있고 상품이 0개인 카테고리는 counts 에 항목이
                          // 없다 — 널 단언 대신 0 으로 표시한다.
                          final count = categoryCounts[category] ?? 0;
                          return _buildCategoryTile(
                              category, count, CategoryGroups(category));
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
              final visibleGroups =
                  filterProductGroups(_groups(products), _filter);
              // 카드(그룹) 수. 좌측 타일 카운트와 항상 일치한다.
              // 카테고리 선택 중엔 "전체"라고 하면 혼동을 줘 카테고리명을 그대로 쓰고,
              // 좌측 타일 선택색(kMainColor)과 맞춰 카테고리명만 강조한다.
              final filter = _filter;
              final headerCountText = filter is CategoryGroups
                  ? Text.rich(
                      TextSpan(
                        style: AppTextStyles.titleSm
                            .copyWith(color: AppStyles.gray9),
                        children: [
                          TextSpan(
                            text: filter.categoryName,
                            style: TextStyle(
                              color: AppStyles.kMainColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          TextSpan(
                            text:
                                ' ${t.product_mgmt.count(n: visibleGroups.length)}',
                          ),
                        ],
                      ),
                    )
                  : Text(
                      t.product_mgmt.total_count(n: visibleGroups.length),
                      style: AppTextStyles.titleSm
                          .copyWith(color: AppStyles.gray9),
                    );
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
                        headerCountText,
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
                        itemCount: visibleGroups.length,
                        itemBuilder: (context, index) => ProductCardWidget(
                          // 일괄 변경 후 재정렬돼도 진행 스피너가 다른 카드에
                          // 붙지 않도록 그룹 고유 키를 고정한다.
                          key: ValueKey(visibleGroups[index].key),
                          group: visibleGroups[index],
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
