import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:appfit_order_agent/constants/app_styles.dart';
import 'package:appfit_order_agent/i18n/strings.g.dart';
import 'package:appfit_order_agent/models/shop_category_model.dart';
import 'package:appfit_order_agent/providers/preference_provider.dart';
import 'package:appfit_order_agent/providers/product_provider.dart';
import 'package:appfit_order_agent/services/label_printer/label_output_policy.dart';
import 'package:appfit_order_agent/services/platform_service.dart';
import 'package:appfit_order_agent/widgets/settings/label_pick_tile.dart';

/// 라벨로 출력할 상품 카테고리를 고르는 화면.
///
/// 설정 좌측 패널의 "라벨 출력 카테고리 지정" 이 ON 일 때만 진입할 수 있다.
/// 카테고리가 수십 개인 매장이 있어 다이얼로그 대신 전체 화면을 쓴다.
class LabelCategorySettingsScreen extends ConsumerStatefulWidget {
  const LabelCategorySettingsScreen({super.key});

  @override
  ConsumerState<LabelCategorySettingsScreen> createState() =>
      _LabelCategorySettingsScreenState();
}

class _LabelCategorySettingsScreenState
    extends ConsumerState<LabelCategorySettingsScreen> {
  late Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = {...ref.read(preferenceServiceProvider).getLabelCategoryKeys()};
  }

  Future<void> _save() async {
    final ok = await ref
        .read(preferenceServiceProvider)
        .setLabelCategoryKeys(_selected);
    if (!mounted) return;
    if (!ok) {
      // 매장 미확정 = 저장 스킵. 조용히 넘어가면 점주는 설정이 사라진 이유를
      // 알 수 없으므로 반드시 보이게 알린다.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t.label_category_select.save_failed),
      ));
      return;
    }
    // SharedPreferences 는 변경 알림이 없다 — 저장한 쪽이 무효화하는 계약.
    ref.invalidate(labelOutputPolicyProvider);
  }

  Future<void> _toggle(String key) async {
    setState(() {
      if (!_selected.remove(key)) _selected.add(key);
    });
    await _save();
  }

  Future<void> _toggleAll(List<ShopCategoryModel> categories) async {
    // 버튼 하나로 전체선택 ⇄ 전체해제. 선택이 0개면 "전체 선택", 그 외에는
    // "전체 해제" 로 라벨이 바뀐다.
    setState(() {
      if (_selected.isEmpty) {
        _selected = {
          for (final c in categories)
            labelCategoryKeyOf(c.categoryCode, c.categoryName),
        };
      } else {
        _selected = {};
      }
    });
    logToFile(
        tag: LogTag.UI_ACTION,
        message: '라벨 출력 카테고리 일괄 변경 -> ${_selected.length}개');
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(shopCategoryListProvider);

    return Scaffold(
      backgroundColor: AppStyles.gray1,
      appBar: AppBar(
        title: Text(t.label_category_select.title),
        backgroundColor: Colors.white,
        foregroundColor: AppStyles.gray9,
        elevation: 0,
      ),
      body: categoriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _buildNotice(t.label_category_select.empty_catalog),
        data: (categories) {
          if (categories.isEmpty) {
            return _buildNotice(t.label_category_select.empty_catalog);
          }
          return Column(
            children: [
              _buildHeader(categories),
              const Divider(height: 1, color: AppStyles.gray2),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s8, vertical: AppSpacing.s8),
                  itemCount: categories.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, color: AppStyles.gray2),
                  itemBuilder: (_, i) {
                    final c = categories[i];
                    final key =
                        labelCategoryKeyOf(c.categoryCode, c.categoryName);
                    return LabelPickTile(
                      title: c.categoryName,
                      subtitle: c.categoryCode.isEmpty ? null : c.categoryCode,
                      selected: _selected.contains(key),
                      onTap: () => _toggle(key),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader(List<ShopCategoryModel> categories) {
    final isEmpty = _selected.isEmpty;
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.label_category_select.guide,
            style: AppTextStyles.bodySm.copyWith(color: AppStyles.gray6),
          ),
          const SizedBox(height: AppSpacing.s12),
          Row(
            children: [
              Expanded(
                child: Text(
                  t.label_category_select.summary(
                    total: categories.length,
                    count: _selected.length,
                  ),
                  style: AppTextStyles.body.copyWith(
                    color: AppStyles.gray9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.s12),
              OutlinedButton(
                onPressed: () => _toggleAll(categories),
                child: Text(isEmpty
                    ? t.label_category_select.select_all
                    : t.label_category_select.clear_all),
              ),
            ],
          ),
          if (isEmpty) ...[
            const SizedBox(height: AppSpacing.s12),
            _buildEmptyMeansAll(),
          ] else ...[
            const SizedBox(height: AppSpacing.s8),
            Text(
              _selectedNames(categories),
              style: AppTextStyles.bodySm.copyWith(color: AppStyles.gray6),
            ),
          ],
        ],
      ),
    );
  }

  /// "전체 해제 == 전체 선택" 이라는 규약을 화면에서 문구로 해소한다 — 라벨을
  /// 아예 끄는 건 라벨 프린터 사용 스위치 쪽 일이라는 안내까지 함께 준다.
  Widget _buildEmptyMeansAll() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.s12),
      decoration: BoxDecoration(
        color: AppStyles.kAmberAlpha,
        borderRadius: AppRadius.bSm,
      ),
      child: Text(
        t.label_category_select.empty_means_all,
        style: AppTextStyles.bodySm.copyWith(color: AppStyles.gray9),
      ),
    );
  }

  String _selectedNames(List<ShopCategoryModel> categories) => categories
      .where((c) => _selected
          .contains(labelCategoryKeyOf(c.categoryCode, c.categoryName)))
      .map((c) => c.categoryName)
      .join(', ');

  Widget _buildNotice(String message) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s24),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: AppTextStyles.body.copyWith(color: AppStyles.gray6),
          ),
        ),
      );
}
