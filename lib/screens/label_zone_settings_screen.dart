import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:appfit_order_agent/constants/app_styles.dart';
import 'package:appfit_order_agent/i18n/strings.g.dart';
import 'package:appfit_order_agent/models/product_model.dart';
import 'package:appfit_order_agent/providers/preference_provider.dart';
import 'package:appfit_order_agent/providers/product_provider.dart';
import 'package:appfit_order_agent/services/label_printer/label_target.dart';
import 'package:appfit_order_agent/services/platform_service.dart';
import 'package:appfit_order_agent/utils/label_painter.dart';

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

  /// USB 직접 제어 사용 여부. OFF 면 종전 Caysn 경로(프린터 1대).
  late bool _useUsbDirect;

  /// target id → USB 버스 번호.
  late Map<String, int> _targetBus;

  /// 지금 연결된 프린터의 버스 번호. null = 아직 안 읽음.
  List<int>? _connectedBuses;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    final prefs = ref.read(preferenceServiceProvider);
    _assignment = Map<String, String>.from(prefs.getLabelTargetAssignment());
    _localTargets = prefs.getLabelLocalTargets();
    _useUsbDirect = prefs.getLabelUseUsbDirect();
    _targetBus = Map<String, int>.from(prefs.getLabelTargetBusMap());
    if (_useUsbDirect) unawaited(_refreshDevices());
  }

  Future<void> _refreshDevices() async {
    final buses = await PlatformService.enumerateUsbLabelPrinters();
    if (!mounted) return;
    setState(() => _connectedBuses = buses);
  }

  Future<void> _setUseUsbDirect(bool value) async {
    setState(() => _useUsbDirect = value);
    await ref.read(preferenceServiceProvider).setLabelUseUsbDirect(value);
    if (value) await _refreshDevices();
  }

  Future<void> _assignBus(LabelTarget target, int? bus) async {
    setState(() {
      if (bus == null) {
        _targetBus.remove(target.id);
      } else {
        _targetBus[target.id] = bus;
      }
    });
    await ref.read(preferenceServiceProvider).setLabelTargetBusMap(_targetBus);
  }

  /// 지정 포트에 테스트 라벨 1장.
  ///
  /// **동일 기종은 외관으로 구별되지 않으므로 이것이 물리 확인의 유일한 수단이다.**
  /// 화면에서 "포트 3 = 구역 2" 라고 정해도, 실제로 어느 기계가 포트 3인지는
  /// 종이가 나오는 걸 봐야 안다.
  Future<void> _testPrint(int bus) async {
    if (_testing) return;
    setState(() => _testing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await LabelPainter.generateLabelImage(
        menuName: t.label_zone_select.direct_test,
        options: const [],
        shopOrderNo: 'P$bus',
        orderTime: DateFormat('MM/dd\nHH:mm:ss').format(DateTime.now()),
        memo: t.label_zone_select.direct_port(bus: bus),
      );
      final rc =
          await PlatformService.testPrintUsbLabel(bus: bus, imageBytes: bytes);
      if (!mounted) return;
      // 3분류 중 0=성공. 1/2 는 사용자 관점에서 "확인 필요" 로 묶는다 —
      // 설정 화면에서 재시도 정책을 흉내낼 이유가 없다.
      messenger.showSnackBar(SnackBar(
        content: Text(rc == 0
            ? t.label_zone_select.direct_test_sent(bus: bus)
            : t.label_zone_select.direct_test_failed(bus: bus)),
      ));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(t.label_zone_select.direct_test_failed(bus: bus)),
      ));
    } finally {
      if (mounted) setState(() => _testing = false);
    }
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
        _buildDirectSection(),
        const Divider(height: 1, color: AppStyles.gray3),
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

  /// USB 직접 제어 — 토글 + 연결된 프린터 목록 + 구역 배정 + 테스트 출력.
  ///
  /// Android 전용이다. Windows 백엔드는 싱글턴 구조라 여러 대를 다루지 못하고,
  /// 이 화면에서 켤 수 있게 하면 켜도 아무 일이 없는 스위치가 된다.
  Widget _buildDirectSection() {
    if (!Platform.isAndroid) return const SizedBox.shrink();
    final buses = _connectedBuses;
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.only(bottom: AppSpacing.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(t.label_zone_select.direct_section),
          SwitchListTile(
            value: _useUsbDirect,
            onChanged: _setUseUsbDirect,
            activeThumbColor: AppStyles.kMainColor,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: AppSpacing.s16),
            title: Text(t.label_zone_select.direct_toggle,
                style: AppTextStyles.body),
            subtitle: Text(
              t.label_zone_select.direct_hint,
              style: AppTextStyles.caption.copyWith(color: AppStyles.gray6),
            ),
          ),
          if (_useUsbDirect) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.s16, AppSpacing.s8, AppSpacing.s16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      t.label_zone_select.direct_devices,
                      style: AppTextStyles.bodySm
                          .copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  TextButton(
                    onPressed: _refreshDevices,
                    child: Text(t.label_zone_select.direct_refresh),
                  ),
                ],
              ),
            ),
            if (buses == null)
              const Padding(
                padding: EdgeInsets.all(AppSpacing.s16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (buses.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s16, vertical: AppSpacing.s8),
                child: Text(
                  t.label_zone_select.direct_none,
                  style: AppTextStyles.bodySm.copyWith(color: AppStyles.kRed),
                ),
              )
            else
              ...buses.map(_buildDeviceRow),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.s16, AppSpacing.s8, AppSpacing.s16, 0),
              child: Text(
                t.label_zone_select.direct_port_warning,
                style:
                    AppTextStyles.caption.copyWith(color: AppStyles.kMainColor),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 프린터 한 대 — 어느 구역을 맡을지 + 물리 확인용 테스트 출력.
  Widget _buildDeviceRow(int bus) {
    // 이 포트에 배정된 구역(역방향 조회). 한 포트에 여러 구역을 넣지 않는 이유:
    // "구역 하나 = 프린터 하나" 가 아니라 반대 방향으로 열어 두면 배정이 중복돼
    // 어느 쪽이 이기는지 화면에서 읽을 수 없다.
    LabelTarget? assigned;
    for (final e in _targetBus.entries) {
      if (e.value == bus) {
        assigned = LabelTarget(e.key);
        break;
      }
    }
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s16, vertical: AppSpacing.s4),
      child: Row(
        children: [
          SizedBox(
            width: 88,
            child: Text(
              t.label_zone_select.direct_port(bus: bus),
              style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: AppSpacing.s8,
              children: [
                for (final target in LabelTarget.selectable)
                  ChoiceChip(
                    label: Text(_zoneLabel(target)),
                    selected: assigned == target,
                    selectedColor: AppStyles.kMainColor,
                    labelStyle: AppTextStyles.bodySm.copyWith(
                      color:
                          assigned == target ? Colors.white : AppStyles.gray9,
                    ),
                    // 같은 칩을 다시 누르면 해제 — 배정을 지울 방법이 없으면
                    // 프린터를 뺀 뒤에도 유령 배정이 남는다.
                    onSelected: (_) =>
                        _assignBus(target, assigned == target ? null : bus),
                  ),
              ],
            ),
          ),
          TextButton(
            onPressed: _testing ? null : () => _testPrint(bus),
            child: Text(t.label_zone_select.direct_test),
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
