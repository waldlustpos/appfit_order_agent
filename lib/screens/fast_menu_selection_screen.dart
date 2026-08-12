import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:appfit_order_agent/constants/app_styles.dart';
import 'package:appfit_order_agent/i18n/strings.g.dart';
import 'package:appfit_order_agent/models/product_model.dart';
import 'package:appfit_order_agent/providers/preference_provider.dart';
import 'package:appfit_order_agent/providers/product_provider.dart';
import 'package:appfit_order_agent/services/label_printer/fast_menu_policy.dart';

/// 빠른 제조 메뉴(우선 출력 대상) 지정 화면.
///
/// 서버 상품 응답에 제조시간 필드가 없어 매장이 직접 고른다. 선택은
/// `PreferenceService.setFastMenuIds` 로 매장별 키에 저장되며, 저장 시
/// [fastMenuPolicyProvider] 를 invalidate 해 판정을 즉시 갱신한다.
///
/// 상품관리 화면(`product_management_screen.dart`)의 그리드를 복제하지 않는다 —
/// 여기 필요한 것은 "체크 목록" 뿐이라 훨씬 가벼운 리스트로 충분하다.
class FastMenuSelectionScreen extends ConsumerStatefulWidget {
  const FastMenuSelectionScreen({super.key});

  @override
  ConsumerState<FastMenuSelectionScreen> createState() =>
      _FastMenuSelectionScreenState();
}

class _FastMenuSelectionScreenState
    extends ConsumerState<FastMenuSelectionScreen> {
  final TextEditingController _searchController = TextEditingController();

  /// 화면에서 편집 중인 선택 집합. 상품의 `productId` + `internalId` 를 함께 담는다
  /// (주문의 shopItemId 가 둘 중 어느 쪽으로도 오기 때문 — FastMenuPolicy 주석 참조).
  late Set<String> _selectedIds;

  String _searchQuery = '';
  String? _selectedCategory;

  @override
  void initState() {
    super.initState();
    _selectedIds = ref.read(preferenceServiceProvider).getFastMenuIds();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 한 상품이 선택되었는지. 저장 형식이 ID 2개라 어느 쪽이든 있으면 선택으로 본다.
  bool _isSelected(ProductModel p) =>
      _selectedIds.contains(p.productId) ||
      (p.internalId.isNotEmpty && _selectedIds.contains(p.internalId));

  void _toggle(ProductModel p, bool selected) {
    setState(() {
      final ids = <String>{p.productId, p.internalId}
          .where((e) => e.isNotEmpty)
          .toSet();
      if (selected) {
        _selectedIds.addAll(ids);
      } else {
        _selectedIds.removeAll(ids);
      }
    });
    _persist();
  }

  /// 변경 즉시 저장한다.
  ///
  /// 화면 이탈(PopScope) 시점에 저장하지 않는 이유: 그때는 위젯이 이미
  /// dispose 되는 중이라 `await` 이후의 `ref.invalidate` 가 "ref after dispose"
  /// 로 터진다 — 저장은 되고 판정 캐시만 갱신되지 않는 어중간한 상태가 된다.
  /// 토글 1회 = `setString` 1회라 비용도 무시할 수 있다.
  Future<void> _persist() async {
    final ok =
        await ref.read(preferenceServiceProvider).setFastMenuIds(_selectedIds);
    if (!mounted) return;
    if (!ok) {
      // 매장 ID 미확정 등 — 조용히 삼키면 "설정했는데 안 남는다" 가 된다.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.fast_menu_select.save_failed)),
      );
      return;
    }
    // 판정 캐시 갱신 — SharedPreferences 는 변경 알림이 없어 명시 invalidate 가 계약.
    ref.invalidate(fastMenuPolicyProvider);
  }

  /// 목록에 노출할 상품 — 옵션/미노출 상품 제외 + 동일 상품 중복 제거.
  ///
  /// 중복 제거는 필터 **뒤에** 한다. 카테고리 필터가 걸린 상태에서 먼저 접으면
  /// 다른 카테고리 사본만 남아 목록에서 통째로 사라질 수 있다.
  List<ProductModel> _visible(List<ProductModel> products) {
    final query = _searchQuery.trim().toLowerCase();
    return dedupeProductsByIdentity(products.where((p) {
      if (p.type != ProductType.item) return false;
      if (p.status == ProductStatus.hidden) return false;
      if (_selectedCategory != null && p.categoryName != _selectedCategory) {
        return false;
      }
      if (query.isEmpty) return true;
      return p.productName.toLowerCase().contains(query);
    }));
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productProvider);

    // 저장은 토글 즉시(_persist). 화면 이탈 시점 저장은 dispose 경합이 있어 쓰지 않는다.
    return Scaffold(
      backgroundColor: AppStyles.gray1,
      appBar: AppBar(
        title: Text(t.fast_menu_select.title),
        actions: [
          if (_selectedIds.isNotEmpty)
            TextButton(
              onPressed: () {
                setState(() => _selectedIds = <String>{});
                _persist();
              },
              child: Text(t.fast_menu_select.clear_all),
            ),
        ],
      ),
      body: productsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.s20),
            child: Text(
              t.fast_menu_select.error_load(error: e.toString()),
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySm.copyWith(color: AppStyles.kRed),
            ),
          ),
        ),
        data: (products) => _buildBody(products),
      ),
    );
  }

  Widget _buildBody(List<ProductModel> products) {
    final visible = _visible(products);
    // 카테고리 칩은 **중복 제거 전** 목록에서 뽑아야 한다 — 접고 나면 두 번째
    // 이후 카테고리가 사라진다.
    final itemProducts = products
        .where((p) =>
            p.type == ProductType.item && p.status != ProductStatus.hidden)
        .toList();
    final categories = itemProducts
        .map((p) => p.categoryName)
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    // 개수·칩은 상품 단위로 센다. 저장 집합은 상품당 ID 2개이고, 카탈로그는
    // 카테고리마다 사본을 갖고 있어서 접지 않으면 양쪽으로 부풀려진다.
    final selected =
        dedupeProductsByIdentity(itemProducts.where(_isSelected)).toList();

    return Column(
      children: [
        _buildHeader(categories, selected.length),
        const Divider(height: 1, color: AppStyles.gray3),
        _buildSelectedSection(selected),
        const Divider(height: 1, color: AppStyles.gray3),
        Expanded(
          child: visible.isEmpty
              ? Center(
                  child: Text(
                    t.fast_menu_select.empty,
                    style:
                        AppTextStyles.bodySm.copyWith(color: AppStyles.gray6),
                  ),
                )
              : ListView.separated(
                  itemCount: visible.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, color: AppStyles.gray2),
                  itemBuilder: (context, i) {
                    final product = visible[i];
                    final selected = _isSelected(product);
                    return CheckboxListTile(
                      value: selected,
                      onChanged: (v) => _toggle(product, v ?? false),
                      activeColor: AppStyles.kMainColor,
                      controlAffinity: ListTileControlAffinity.leading,
                      title:
                          Text(product.productName, style: AppTextStyles.body),
                      subtitle: Text(
                        product.categoryName,
                        style: AppTextStyles.caption
                            .copyWith(color: AppStyles.gray6),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// 지정된 메뉴를 한눈에 보여주는 영역.
  ///
  /// 아래 목록은 검색·카테고리 필터가 걸리므로, 필터를 바꾸면 이미 고른 메뉴가
  /// 화면에서 사라진다. 여기서 **필터와 무관하게 전체 지정 현황**을 보여주고
  /// 칩을 눌러 바로 해제할 수 있게 한다.
  Widget _buildSelectedSection(List<ProductModel> selected) {
    return Container(
      width: double.infinity,
      color: AppStyles.kMainColorAlpha,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s16,
        vertical: AppSpacing.s12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.fast_menu_select.selected_section,
            style: AppTextStyles.bodySm.copyWith(
              color: AppStyles.gray9,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: AppSpacing.s8),
          if (selected.isEmpty)
            Text(
              t.fast_menu_select.selected_empty,
              style: AppTextStyles.bodySm.copyWith(color: AppStyles.gray6),
            )
          else
            // 많이 고르면 화면을 다 잡아먹으므로 높이를 묶고 안에서 스크롤한다.
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 108),
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: AppSpacing.s8,
                  runSpacing: AppSpacing.s8,
                  children: selected
                      .map((p) => InputChip(
                            label: Text(p.productName),
                            labelStyle: AppTextStyles.bodySm
                                .copyWith(color: Colors.white),
                            backgroundColor: AppStyles.kMainColor,
                            deleteIconColor: Colors.white,
                            visualDensity: VisualDensity.compact,
                            onDeleted: () => _toggle(p, false),
                          ))
                      .toList(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader(List<String> categories, int selectedCount) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  t.fast_menu_select.guide,
                  style: AppTextStyles.bodySm.copyWith(color: AppStyles.gray6),
                ),
              ),
              const SizedBox(width: AppSpacing.s12),
              Text(
                t.fast_menu_select.selected_count(n: selectedCount),
                style: AppTextStyles.bodySm.copyWith(
                  color: AppStyles.kMainColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: t.fast_menu_select.search_placeholder,
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
              border: OutlineInputBorder(borderRadius: AppRadius.bSm),
            ),
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
          const SizedBox(height: AppSpacing.s12),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: categories.length + 1,
              separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.s8),
              itemBuilder: (context, i) {
                final isAll = i == 0;
                final name = isAll ? null : categories[i - 1];
                final selected = _selectedCategory == name;
                return ChoiceChip(
                  label: Text(isAll ? t.fast_menu_select.all : name!),
                  selected: selected,
                  selectedColor: AppStyles.kMainColor,
                  labelStyle: AppTextStyles.bodySm.copyWith(
                    color: selected ? Colors.white : AppStyles.gray9,
                  ),
                  onSelected: (_) => setState(() => _selectedCategory = name),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
