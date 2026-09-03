import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:appfit_order_agent/constants/app_styles.dart';
import 'package:appfit_order_agent/i18n/strings.g.dart';
import 'package:appfit_order_agent/models/shop_category_model.dart';
import 'package:appfit_order_agent/providers/preference_provider.dart';
import 'package:appfit_order_agent/providers/product_provider.dart';
import 'package:appfit_order_agent/screens/label_category_settings_screen.dart';
import 'package:appfit_order_agent/services/label_printer/label_output_policy.dart';
import 'package:appfit_order_agent/services/platform_service.dart';
import 'package:appfit_order_agent/widgets/custom_switch.dart';
import 'package:appfit_order_agent/widgets/settings/settings_item_widget.dart';

/// 설정 좌측 패널의 라벨 프린터 카드 안에 들어가는 "라벨 출력 카테고리 지정" 항목.
///
/// 라벨 sub-info 는 여기 없다 — 매장이 옵션그룹을 고르게 하는 안을 접고 브랜드
/// 전략으로 남겼다(`label_subinfo_strategy.dart`).
///
/// 설정 화면(`settings_screen.dart`)은 40여 개 상태를 패널로 prop drilling 하는
/// 구조라 여기에 항목을 더 얹으면 생성자가 계속 길어진다. `SettingsDualMonitorSection`
/// 처럼 **자기 완결형**으로 두고 prefs 를 직접 읽고 쓴다.
class SettingsLabelOutputItems extends ConsumerStatefulWidget {
  const SettingsLabelOutputItems({super.key});

  @override
  ConsumerState<SettingsLabelOutputItems> createState() =>
      _SettingsLabelOutputItemsState();
}

class _SettingsLabelOutputItemsState
    extends ConsumerState<SettingsLabelOutputItems> {
  bool _filterOn = false;

  @override
  void initState() {
    super.initState();
    _filterOn = ref.read(preferenceServiceProvider).getLabelCategoryFilterOn();
  }

  Future<void> _setFilterOn(bool value) async {
    setState(() => _filterOn = value);
    logToFile(tag: LogTag.UI_ACTION, message: '라벨 출력 카테고리 지정 변경 -> $value');
    final ok = await ref
        .read(preferenceServiceProvider)
        .setLabelCategoryFilterOn(value);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t.label_category_select.save_failed),
      ));
      // 저장 못 했으면 화면도 되돌린다 — 켜진 것처럼 보이는데 안 켜진 상태가
      // 제일 나쁘다.
      setState(() => _filterOn = !value);
      return;
    }
    ref.invalidate(labelOutputPolicyProvider);
  }

  Future<void> _open(Widget screen) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => screen),
    );
    // 선택 화면은 즉시 저장이라 복귀 후 요약만 다시 그린다.
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // 요약 문구용 이름 해석 — 아직 로딩 중이면 코드/개수만 보여준다.
    final categories = ref.watch(shopCategoryListProvider).value ?? const [];
    final prefs = ref.watch(preferenceServiceProvider);
    final selectedKeys = prefs.getLabelCategoryKeys();

    return SettingsItemWidget(
        title: t.settings.label_category_filter.title,
        description: _categoryDescription(categories, selectedKeys),
        isVertical: true,
        showDivider: false,
        trailing: Row(
          children: [
            CustomSwitch(
              value: _filterOn,
              activeColor: AppStyles.kMainColor,
              inactiveColor: AppStyles.gray4,
              activeText: t.settings.auto_start.on,
              inactiveText: t.settings.auto_start.off,
              onChanged: _setFilterOn,
            ),
            // 지정 ON 일 때만 설정 버튼이 나타난다 — OFF 면 고를 것이 없다.
            if (_filterOn) ...[
              const SizedBox(width: AppSpacing.s12),
              ElevatedButton.icon(
                onPressed: () => _open(const LabelCategorySettingsScreen()),
                icon: const Icon(Icons.checklist, size: 18),
                label: Text(t.settings.label_category_filter.btn_configure),
                style: AppStyles.primaryButton(),
              ),
            ],
          ],
        ));
  }

  String _categoryDescription(
    List<ShopCategoryModel> categories,
    Set<String> selectedKeys,
  ) {
    if (!_filterOn) return t.settings.label_category_filter.desc_off;
    // ON + 선택 0개 = 전체 출력. 이 상태가 "라벨이 안 나온다"로 오해되지 않도록
    // 문구로 못 박는다.
    if (selectedKeys.isEmpty) {
      return t.settings.label_category_filter.desc_none;
    }
    final names = categories
        .where((c) => selectedKeys
            .contains(labelCategoryKeyOf(c.categoryCode, c.categoryName)))
        .map((c) => c.categoryName)
        .toList();
    return t.settings.label_category_filter.desc_selected(
      total: categories.length,
      count: selectedKeys.length,
      names: names.isEmpty ? selectedKeys.join(', ') : names.join(', '),
    );
  }
}
