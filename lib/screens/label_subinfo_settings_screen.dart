import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:appfit_order_agent/constants/app_styles.dart';
import 'package:appfit_order_agent/i18n/strings.g.dart';
import 'package:appfit_order_agent/models/product_model.dart';
import 'package:appfit_order_agent/models/shop_option_group_model.dart';
import 'package:appfit_order_agent/providers/preference_provider.dart';
import 'package:appfit_order_agent/providers/product_provider.dart';
import 'package:appfit_order_agent/services/label_printer/label_output_policy.dart';
import 'package:appfit_order_agent/services/platform_service.dart';
import 'package:appfit_order_agent/widgets/settings/label_pick_tile.dart';

/// 라벨 서브정보(라벨 위쪽 강조 영역)에 올릴 옵션 그룹을 고르는 화면.
///
/// **고른 순서가 곧 인쇄 순서**이므로 선택된 행에 순번을 그린다. 상한은
/// [kLabelSubInfoMaxCount] — 58mm 레이아웃이 1줄 검정 바라 넘치면 잘린다.
class LabelSubInfoSettingsScreen extends ConsumerStatefulWidget {
  const LabelSubInfoSettingsScreen({super.key});

  @override
  ConsumerState<LabelSubInfoSettingsScreen> createState() =>
      _LabelSubInfoSettingsScreenState();
}

class _LabelSubInfoSettingsScreenState
    extends ConsumerState<LabelSubInfoSettingsScreen> {
  late List<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = [
      ...ref.read(preferenceServiceProvider).getLabelSubInfoGroups()
    ];
  }

  Future<void> _save() async {
    final ok = await ref
        .read(preferenceServiceProvider)
        .setLabelSubInfoGroups(_selected);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t.label_subinfo_select.save_failed),
      ));
      return;
    }
    ref.invalidate(labelOutputPolicyProvider);
  }

  Future<void> _toggle(String groupCode) async {
    final wasSelected = _selected.contains(groupCode);
    if (!wasSelected && _selected.length >= kLabelSubInfoMaxCount) {
      // 상한 도달 — 조용히 무시하지 않고 왜 안 되는지 알린다.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t.label_subinfo_select.max_notice(
          max: kLabelSubInfoMaxCount,
        )),
      ));
      return;
    }
    setState(() {
      // 해제하면 뒤 항목의 순번이 자동으로 당겨진다(목록 순서 = 인쇄 순서).
      if (wasSelected) {
        _selected.remove(groupCode);
      } else {
        _selected.add(groupCode);
      }
    });
    logToFile(
        tag: LogTag.UI_ACTION,
        message: '라벨 서브정보 옵션그룹 변경 -> ${_selected.join(",")}');
    await _save();
  }

  Future<void> _clearAll() async {
    setState(() => _selected = []);
    logToFile(tag: LogTag.UI_ACTION, message: '라벨 서브정보 옵션그룹 전체 해제');
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    final groupsAsync = ref.watch(shopOptionGroupListProvider);
    final productsAsync = ref.watch(productProvider);

    return Scaffold(
      backgroundColor: AppStyles.gray1,
      appBar: AppBar(
        title: Text(t.label_subinfo_select.title),
        backgroundColor: Colors.white,
        foregroundColor: AppStyles.gray9,
        elevation: 0,
      ),
      body: groupsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _buildNotice(t.label_subinfo_select.empty_catalog),
        data: (groups) {
          if (groups.isEmpty) {
            return _buildNotice(t.label_subinfo_select.empty_catalog);
          }
          // 옵션 예시는 있으면 좋은 보조 정보라 로딩 실패해도 화면을 막지 않는다.
          final samples = _optionSamples(productsAsync.value ?? const []);
          return Column(
            children: [
              _buildHeader(groups, samples),
              const Divider(height: 1, color: AppStyles.gray2),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s8, vertical: AppSpacing.s8),
                  itemCount: groups.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, color: AppStyles.gray2),
                  itemBuilder: (_, i) {
                    final g = groups[i];
                    final order = _selected.indexOf(g.groupCode);
                    final selected = order >= 0;
                    return LabelPickTile(
                      title: g.displayName,
                      subtitle: _subtitleFor(g, samples),
                      selected: selected,
                      orderBadge: selected ? order + 1 : null,
                      enabled:
                          selected || _selected.length < kLabelSubInfoMaxCount,
                      onTap: () => _toggle(g.groupCode),
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

  Widget _buildHeader(
    List<ShopOptionGroupModel> groups,
    Map<String, List<String>> samples,
  ) {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.label_subinfo_select.guide(max: kLabelSubInfoMaxCount),
            style: AppTextStyles.bodySm.copyWith(color: AppStyles.gray6),
          ),
          const SizedBox(height: AppSpacing.s12),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${t.label_subinfo_select.preview}: ${_previewText(samples)}',
                  style: AppTextStyles.body.copyWith(
                    color: AppStyles.gray9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (_selected.isNotEmpty) ...[
                const SizedBox(width: AppSpacing.s12),
                OutlinedButton(
                  onPressed: _clearAll,
                  child: Text(t.label_subinfo_select.clear_all),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// 라벨에 실제로 찍힐 모습 — 고른 그룹의 첫 옵션명을 순서대로 이어 붙인다.
  String _previewText(Map<String, List<String>> samples) {
    if (_selected.isEmpty) return t.label_subinfo_select.none;
    final parts = <String>[];
    for (final code in _selected) {
      final sample = samples[code];
      parts.add((sample == null || sample.isEmpty) ? code : sample.first);
    }
    return parts.join(' / ');
  }

  String? _subtitleFor(
    ShopOptionGroupModel g,
    Map<String, List<String>> samples,
  ) {
    final sample = samples[g.groupCode];
    if (sample == null || sample.isEmpty) return g.groupCode;
    return '${g.groupCode} — ${sample.join(', ')}';
  }

  /// 그룹코드 → 소속 옵션명 예시(최대 3). 그룹명만으로는 어느 그룹인지 알아보기
  /// 어려운 매장이 있어(예: "옵션1", "선택") 실제 옵션을 함께 보여준다.
  Map<String, List<String>> _optionSamples(List<ProductModel> products) {
    final result = <String, List<String>>{};
    for (final p in products) {
      if (p.type != ProductType.option) continue;
      if (p.categoryCode.isEmpty || p.productName.isEmpty) continue;
      final list = result.putIfAbsent(p.categoryCode, () => <String>[]);
      if (list.length < 3) list.add(p.productName);
    }
    return result;
  }

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
