import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:appfit_order_agent/constants/app_styles.dart';
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

  // ScrollController 추가
  final ScrollController _categoryScrollController = ScrollController();
  final ScrollController _productScrollController = ScrollController();

  // 메인 컬러 정의

  @override
  void initState() {
    super.initState();
    // initState에서는 새로고침하지 않음 - Provider가 자동으로 데이터 로드
  }

  @override
  void dispose() {
    _searchController.dispose();
    // ScrollController 해제
    _categoryScrollController.dispose();
    _productScrollController.dispose();
    super.dispose();
  }

  // 카테고리별 상품 개수 계산
  Map<String, int> _getCategoryCounts(List<ProductModel> products) {
    final Map<String, int> counts = {};
    for (var product in products) {
      counts[product.categoryName] = (counts[product.categoryName] ?? 0) + 1;
    }
    return counts;
  }

  // 필터링된 상품 목록 가져오기
  List<ProductModel> _getFilteredProducts(List<ProductModel> products) {
    return products.where((product) {
      // 미노출 항목 숨김
      if (product.status == ProductStatus.hidden) return false;
      // 검색어 필터링
      final matchesSearch = product.productName
          .toLowerCase()
          .contains(_searchQuery.toLowerCase());

      // 카테고리 필터링
      bool matchesCategory;
      if (_selectedCategory == t.product_mgmt.sold_out) {
        // '품절' 카테고리가 선택된 경우 품절 상품만 표시
        matchesCategory = product.status == ProductStatus.soldOut;
      } else {
        // 일반 카테고리 선택 또는 카테고리 선택 안됨
        matchesCategory = _selectedCategory == null ||
            product.categoryName == _selectedCategory;
      }

      return matchesSearch && matchesCategory;
    }).toList();
  }

  // 카테고리 ListTile 위젯 생성
  Widget _buildCategoryTile(String title, int count, bool isSelected) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14.0),
          border: Border.all(
            color: isSelected ? AppStyles.kMainColor : Colors.transparent,
            width: 1,
          ),
        ),
        child: ListTile(
          splashColor: Colors.transparent,
          hoverColor: Colors.transparent,
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: isSelected ? AppStyles.kMainColor : null,
                  fontWeight: isSelected ? FontWeight.bold : null,
                ),
              ),
              Text(
                t.product_mgmt.count(n: count.toString()),
                style: TextStyle(
                  color: isSelected ? AppStyles.kMainColor : null,
                  fontWeight: isSelected ? FontWeight.bold : null,
                ),
              ),
            ],
          ),
          selected: isSelected,
          onTap: () {
            // 포커스 해제 및 키보드 숨기기
            FocusScope.of(context).unfocus();
            setState(() {
              _selectedCategory = isSelected ? null : title;
            });
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // 포커스 해제 및 키보드 숨기기
        FocusScope.of(context).unfocus();
      },
      // 제스처 감지가 자식 위젯의 이벤트를 방해하지 않도록 설정
      behavior: HitTestBehavior.translucent,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start, // 상단 정렬로 변경
        children: [
          // 좌측 영역 (1:3 비율) - 고정된 너비 사용
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.25,
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(
                    color: Colors.grey[300]!,
                  ),
                ),
              ),
              child: Column(
                children: [
                  // 검색창
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: t.product_mgmt.search_placeholder,
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              BorderSide(color: Colors.grey[400]!, width: 1),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              BorderSide(color: Colors.grey[400]!, width: 1),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              BorderSide(color: Colors.grey[400]!, width: 2),
                        ),
                        filled: true,
                        fillColor: Colors.grey[200],
                      ),
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value;
                        });
                      },
                    ),
                  ),

                  // 카테고리 목록
                  Expanded(
                    child: Consumer(
                      builder: (context, ref, child) {
                        final productsAsync = ref.watch(productProvider);
                        return productsAsync.when(
                            data: (products) {
                              final categoryCounts =
                                  _getCategoryCounts(products);
                              final categories = categoryCounts.keys.toList()
                                ..sort();

                              return RawScrollbar(
                                radius: const Radius.circular(10),
                                thumbColor: Colors.grey[400],
                                fadeDuration: const Duration(milliseconds: 300),
                                controller: _categoryScrollController,
                                child: ListView.builder(
                                  controller: _categoryScrollController,
                                  itemCount:
                                      categories.length + 1, // 품절 카테고리 추가
                                  itemBuilder: (context, index) {
                                    if (index == 0) {
                                      // 품절 카테고리
                                      final soldOutCount = products
                                          .where((p) =>
                                              p.status == ProductStatus.soldOut)
                                          .length;
                                      final isSelected = _selectedCategory ==
                                          t.product_mgmt.sold_out;
                                      return _buildCategoryTile(
                                          t.product_mgmt.sold_out,
                                          soldOutCount,
                                          isSelected);
                                    }

                                    // 일반 카테고리
                                    final category = categories[index - 1];
                                    final count = categoryCounts[category]!;
                                    final isSelected =
                                        category == _selectedCategory;
                                    return _buildCategoryTile(
                                        category, count, isSelected);
                                  },
                                ),
                              );
                            },
                            loading: () => const Center(
                                child: CircularProgressIndicator()),
                            error: (error, stack) {
                              // Center(child: Text('Error: $error')),
                              return Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.error_outline,
                                        color: Colors.red, size: 48),
                                    const SizedBox(height: 16),
                                    Text(
                                      t.product_mgmt
                                          .error_load(error: error.toString()),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(fontSize: 16),
                                    ),
                                    const SizedBox(height: 24),
                                    ElevatedButton.icon(
                                      icon: const Icon(Icons.refresh),
                                      label: Text(t.common.refresh),
                                      onPressed: () {
                                        ref
                                            .read(productProvider.notifier)
                                            .refresh();
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppStyles.kMainColor,
                                        foregroundColor: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            });
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 우측 영역 (상품 그리드)
          Expanded(
            child: Consumer(
              builder: (context, ref, child) {
                final productsAsync = ref.watch(productProvider);
                return productsAsync.when(
                  data: (products) {
                    final filteredProducts = _getFilteredProducts(products);
                    return Column(
                      children: [
                        // 전체 개수 표시
                        Padding(
                          padding: const EdgeInsets.only(
                              top: 16, left: 16, right: 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                t.product_mgmt
                                    .total_count(n: filteredProducts.length),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Row(
                                children: [
                                  IconButton(
                                    onPressed: () {
                                      // refresh 메서드 사용 (더 명확한 로깅)
                                      ref
                                          .read(productProvider.notifier)
                                          .refresh();
                                    },
                                    icon: const Icon(
                                      Icons.refresh_outlined,
                                      size: 30,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        // 상품 그리드
                        Expanded(
                          child: RawScrollbar(
                            radius: const Radius.circular(10),
                            thumbColor: Colors.grey[400],
                            fadeDuration: const Duration(milliseconds: 300),
                            controller: _productScrollController,
                            child: GridView.builder(
                              controller: _productScrollController,
                              padding: const EdgeInsets.all(8),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 5,
                                childAspectRatio: 1,
                                crossAxisSpacing: 8,
                                mainAxisSpacing: 8,
                              ),
                              itemCount: filteredProducts.length,
                              itemBuilder: (context, index) {
                                return ProductCardWidget(
                                  product: filteredProducts[index],
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, stack) => Center(child: Text('Error: $error')),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
