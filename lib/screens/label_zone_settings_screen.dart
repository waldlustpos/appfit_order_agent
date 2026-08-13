import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:appfit_order_agent/constants/app_styles.dart';
import 'package:appfit_order_agent/i18n/strings.g.dart';
import 'package:appfit_order_agent/models/product_model.dart';
import 'package:appfit_order_agent/providers/preference_provider.dart';
import 'package:appfit_order_agent/providers/product_provider.dart';
import 'package:appfit_order_agent/services/label_printer/label_target.dart';

/// 라벨 구역(제조 구역별 프린터 분담) 설정 화면.
///
/// 두 가지를 정한다 — 저장 위치도 의미도 다르므로 화면에서도 분리해 보여준다:
/// 1. **카테고리별 구역** = 매장 정책. 모든 단말이 같은 값을 가져야 한다.
/// 2. **이 단말이 출력할 구역** = 단말별 배치. 기기마다 다르다.
///
/// [FastMenuSelectionScreen] 과 같은 규약: 변경 즉시 저장하고
/// `ref.invalidate(labelTargetPolicyProvider)` 로 판정 캐시를 갱신한다
/// (SharedPreferences 는 변경 알림이 없다).
class LabelZoneSettingsScreen extends ConsumerStatefulWidget {
  const LabelZoneSettingsScreen({super.key});

  @override
  ConsumerState<LabelZoneSettingsScreen> createState() =>
      _LabelZoneSettingsScreenState();
}

class _LabelZoneSettingsScreenState
    extends ConsumerState<LabelZoneSettingsScreen> {
  /// categoryCode → target id. **primary 는 담지 않는다** — "미매핑 = primary" 가
  /// 자료구조의 기본값이라, 명시 저장하면 같은 뜻을 두 가지로 표현하게 된다.
  late Map<String, String> _assignment;

  /// 이 단말이 담당하는 target id. 비어 있으면 전부 담당(기본값).
  late Set<String> _localTargets;

  @override
  void initState() {
    super.initState();
    final prefs = ref.read(preferenceServiceProvider);
    _assignment = Map<String, String>.from(prefs.getLabelTargetAssignment());
    _localTargets = prefs.getLabelLocalTargets();
  }

  LabelTarget _targetOf(String categoryCode) {
    final id = _assignment[categoryCode];
    return (id == null || id.isEmpty) ? LabelTarget.primary : LabelTarget(id);
  }

  Future<void> _assign(String categoryCode, LabelTarget target) async {
    setState(() {
      if (target == LabelTarget.primary) {
        _assignment.remove(categoryCode);
      } else {
        _assignment[categoryCode] = target.id;
      }
    });
    final ok = await ref
        .read(preferenceServiceProvider)
        .setLabelTargetAssignment(_assignment);
    _afterSave(ok);
  }

  Future<void> _toggleLocal(LabelTarget target, bool selected) async {
    setState(() {
      if (selected) {
        _localTargets.add(target.id);
      } else {
        _localTargets.remove(target.id);
      }
    });
    final ok = await ref
        .read(preferenceServiceProvider)
        .setLabelLocalTargets(_localTargets);
    _afterSave(ok);
  }

  Future<void> _clearAll() async {
    setState(() {
      _assignment = <String, String>{};
      _localTargets = <String>{};
    });
    final prefs = ref.read(preferenceServiceProvider);
    final a = await prefs.setLabelTargetAssignment(_assignment);
    final b = await prefs.setLabelLocalTargets(_localTargets);
    _afterSave(a && b);
  }

  /// 저장 결과 처리 — 실패를 조용히 삼키면 "설정했는데 안 남는다" 가 된다.
  void _afterSave(bool ok) {
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.label_zone_select.save_failed)),
      );
      return;
    }
    ref.invalidate(labelTargetPolicyProvider);
  }

  String _zoneLabel(LabelTarget target) => switch (target.id) {
        'zone2' => t.label_zone_select.zone_2,
        'zone3' => t.label_zone_select.zone_3,
        _ => t.label_zone_select.zone_primary,
      };

  /// 카탈로그에서 (코드, 표시명) 카테고리 목록을 뽑는다.
  ///
  /// 배정 키는 **categoryCode** 다 — 표시명은 매장이 바꿀 수 있어 키로 못 쓴다.
  /// 코드가 비어 있는 상품은 배정 대상에서 제외한다(배정해도 조회가 안 된다).
  List<({String code, String name})> _categories(List<ProductModel> products) {
    final byCode = <String, String>{};
    for (final p in products) {
      if (p.type != ProductType.item) continue;
      if (p.status == ProductStatus.hidden) continue;
      if (p.categoryCode.isEmpty) continue;
      byCode.putIfAbsent(p.categoryCode,
          () => p.categoryName.isEmpty ? p.categoryCode : p.categoryName);
    }
    final list = byCode.entries
        .map((e) => (code: e.key, name: e.value))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productProvider);

    return Scaffold(
      backgroundColor: AppStyles.gray1,
      appBar: AppBar(
        title: Text(t.label_zone_select.title),
        actions: [
          if (_assignment.isNotEmpty || _localTargets.isNotEmpty)
            TextButton(
              onPressed: _clearAll,
              child: Text(t.label_zone_select.clear_all),
            ),
        ],
      ),
      body: productsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.s20),
            child: Text(
              t.label_zone_select.error_load(error: e.toString()),
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySm.copyWith(color: AppStyles.kRed),
            ),
          ),
        ),
        data: (products) => _buildBody(_categories(products)),
      ),
    );
  }

  Widget _buildBody(List<({String code, String name})> categories) {
    return ListView(
      children: [
        _buildGuide(),
        _buildLocalSection(),
        const Divider(height: 1, color: AppStyles.gray3),
        _buildSectionTitle(t.label_zone_select.assign_section),
        if (categories.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.s20),
            child: Text(
              t.label_zone_select.empty,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySm.copyWith(color: AppStyles.gray6),
            ),
          )
        else
          ...categories.map(_buildCategoryRow),
        const SizedBox(height: AppSpacing.s20),
      ],
    );
  }

  Widget _buildGuide() {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Text(
        t.label_zone_select.guide,
        style: AppTextStyles.bodySm.copyWith(color: AppStyles.gray6),
      ),
    );
  }

  /// "이 단말이 출력할 구역" — 아무것도 안 고르면 전부 출력이라는 점을 문구로
  /// 명시한다. 빈 집합의 의미를 화면에서 읽을 수 없으면 설정 실수를 부른다.
  Widget _buildLocalSection() {
    final none = _localTargets.isEmpty;
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.only(bottom: AppSpacing.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(t.label_zone_select.local_section),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s16),
            child: Wrap(
              spacing: AppSpacing.s8,
              runSpacing: AppSpacing.s8,
              children: LabelTarget.selectable.map((target) {
                final selected = _localTargets.contains(target.id);
                return FilterChip(
                  label: Text(_zoneLabel(target)),
                  selected: selected,
                  selectedColor: AppStyles.kMainColor,
                  labelStyle: AppTextStyles.bodySm.copyWith(
                    color: selected ? Colors.white : AppStyles.gray9,
                  ),
                  onSelected: (v) => _toggleLocal(target, v),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: AppSpacing.s8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s16),
            child: Text(
              none
                  ? t.label_zone_select.local_all
                  : t.label_zone_select.local_warning,
              style: AppTextStyles.caption.copyWith(
                color: none ? AppStyles.gray6 : AppStyles.kMainColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.s16, AppSpacing.s16, AppSpacing.s16, AppSpacing.s8),
      child: Text(
        text,
        style: AppTextStyles.bodySm.copyWith(
          color: AppStyles.gray9,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildCategoryRow(({String code, String name}) category) {
    final current = _targetOf(category.code);
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s16,
        vertical: AppSpacing.s8,
      ),
      margin: const EdgeInsets.only(bottom: 1),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(category.name, style: AppTextStyles.body),
                Text(
                  category.code,
                  style: AppTextStyles.caption.copyWith(color: AppStyles.gray6),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s12),
          Wrap(
            spacing: AppSpacing.s8,
            children: LabelTarget.selectable.map((target) {
              final selected = current == target;
              return ChoiceChip(
                label: Text(_zoneLabel(target)),
                selected: selected,
                selectedColor: AppStyles.kMainColor,
                labelStyle: AppTextStyles.bodySm.copyWith(
                  color: selected ? Colors.white : AppStyles.gray9,
                ),
                onSelected: (_) => _assign(category.code, target),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
