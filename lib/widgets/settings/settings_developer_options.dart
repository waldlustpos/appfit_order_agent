import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:appfit_order_agent/constants/app_styles.dart';
import 'package:appfit_order_agent/providers/providers.dart';
import 'package:appfit_order_agent/core/orders/order_queue_service.dart';
import 'package:appfit_order_agent/dev/mock_order_generator.dart' as mock_gen;
import 'package:appfit_order_agent/dev/net_fault_injector.dart';
import 'package:appfit_order_agent/screens/appfit_test_screen.dart';
import 'package:appfit_order_agent/i18n/strings.g.dart';
import 'package:appfit_order_agent/widgets/settings/settings_section_card.dart';
import 'package:appfit_order_agent/widgets/settings/settings_item_widget.dart';
import 'package:appfit_order_agent/widgets/settings/settings_label_test_section.dart';
import 'package:appfit_order_agent/widgets/custom_switch.dart';

/// 개발자 옵션 섹션.
///
/// 앱 버전을 5번 탭해야 표시되는 숨김 섹션으로,
/// 긴급모드, 서버환경, 테스트화면, 대량주문, 라벨고급설정 항목을 포함한다.
class SettingsDeveloperOptions extends ConsumerWidget {
  const SettingsDeveloperOptions({
    super.key,
    required this.forceSocketReconnect,
    required this.selectedEnv,
    required this.onForceSocketReconnectChanged,
    required this.onEnvChanged,
    // 라벨 테스트 섹션 props
    required this.labelAutoReplyMode,
    required this.labelUseFeedToTear,
    required this.labelUseBackToPrint,
    required this.labelUseCalibrate,
    required this.onAutoReplyModeChanged,
    required this.onFeedToTearChanged,
    required this.onBackToPrintChanged,
    required this.onCalibrateChanged,
    required this.isParanmanjanTestRunning,
    required this.onParanmanjanTest,
  });

  final bool forceSocketReconnect;
  final String selectedEnv;
  final void Function(bool) onForceSocketReconnectChanged;
  final void Function(String) onEnvChanged;

  final int labelAutoReplyMode;
  final bool labelUseFeedToTear;
  final bool labelUseBackToPrint;
  final bool labelUseCalibrate;
  final void Function(int) onAutoReplyModeChanged;
  final void Function(bool) onFeedToTearChanged;
  final void Function(bool) onBackToPrintChanged;
  final void Function(bool) onCalibrateChanged;
  final bool isParanmanjanTestRunning;
  final VoidCallback onParanmanjanTest;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);

    return SettingsSectionCard(
      title: t.settings.developer_options.title,
      icon: Icons.developer_mode,
      children: [
        // 긴급 모드
        SettingsItemWidget(
          title: '긴급 모드',
          description: '서버 이상 대비: 주문 폴링 주기를 10초로 단축합니다.',
          trailing: CustomSwitch(
            value: forceSocketReconnect,
            activeColor: AppStyles.kMainColor,
            inactiveColor: AppStyles.gray4,
            activeText: 'ON',
            inactiveText: 'OFF',
            onChanged: (v) {
              onForceSocketReconnectChanged(v);
              ref.read(orderProvider.notifier).updateEmergencyPoll(v);
            },
          ),
        ),
        // 서버 환경
        SettingsItemWidget(
          title: '서버 환경',
          description: '현재 실행 중: $_currentEnvName | 재시작 후 반영됩니다.',
          isVertical: true,
          trailing: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'dev', label: Text('Dev')),
              ButtonSegment(value: 'staging', label: Text('Stage')),
              ButtonSegment(value: 'live', label: Text('Live')),
              ButtonSegment(value: 'japanLive', label: Text('JP Live')),
            ],
            selected: {selectedEnv},
            onSelectionChanged: (s) => onEnvChanged(s.first),
          ),
        ),
        // AppFit 테스트 화면
        SettingsItemWidget(
          title: t.settings.developer_options.appfit_test.title,
          description: t.settings.developer_options.appfit_test.desc,
          isVertical: true,
          trailing: ElevatedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const AppFitTestScreen(),
              ),
            ),
            icon: const Icon(Icons.science, size: 18),
            label: Text(t.settings.developer_options.appfit_test.btn),
            style: AppStyles.primaryButton().copyWith(
              backgroundColor: const WidgetStatePropertyAll(Colors.blue),
            ),
          ),
        ),
        // 대량 주문 처리 테스트
        SettingsItemWidget(
          title: '대량 주문 처리 테스트 (로컬)',
          description: '가상 주문을 대량으로 생성하여 내부 큐 파이프라인을 테스트합니다.',
          isVertical: true,
          showDivider: false,
          trailing: Wrap(
            spacing: AppSpacing.s8,
            runSpacing: AppSpacing.s8,
            children: [
              _bulkTestButton(context, ref, 10),
              _bulkTestButton(context, ref, 50),
              _bulkTestButton(context, ref, 100),
            ],
          ),
        ),
        // 네트워크 장애 주입 (fault injection) — 2026-08-07 매장 장애 재현·검증용
        if (kAllowFaultInjection) const _NetFaultSection(),
        // 파란만잔 브랜드 테스트 (QR 시퀀스 라벨 출력)
        SettingsItemWidget(
          title: '파란만잔 브랜드 테스트',
          description: 'QR 시퀀스 10장을 라벨로 출력합니다.',
          isVertical: true,
          trailing: ElevatedButton.icon(
            onPressed: isParanmanjanTestRunning ? null : onParanmanjanTest,
            icon: isParanmanjanTestRunning
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.qr_code_2, size: 18),
            label: Text(
                isParanmanjanTestRunning ? '출력 중...' : 'QR 테스트 라벨 출력 (10장)'),
            style: AppStyles.primaryButton().copyWith(
              backgroundColor: const WidgetStatePropertyAll(Colors.indigo),
            ),
          ),
        ),
        // 라벨 프린터 고급 설정
        SettingsLabelTestSection(
          labelAutoReplyMode: labelAutoReplyMode,
          labelUseFeedToTear: labelUseFeedToTear,
          labelUseBackToPrint: labelUseBackToPrint,
          labelUseCalibrate: labelUseCalibrate,
          onAutoReplyModeChanged: onAutoReplyModeChanged,
          onFeedToTearChanged: onFeedToTearChanged,
          onBackToPrintChanged: onBackToPrintChanged,
          onCalibrateChanged: onCalibrateChanged,
        ),
      ],
    );
  }

  String get _currentEnvName => selectedEnv;

  Widget _bulkTestButton(BuildContext context, WidgetRef ref, int count) {
    return ElevatedButton.icon(
      onPressed: () {
        try {
          final mockOrders =
              mock_gen.MockOrderGenerator.generateMockOrders(count);
          ref.read(orderQueueAppServiceProvider).enqueueAll(mockOrders);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$count개의 가상 주문이 큐에 추가되었습니다.'),
              duration: const Duration(seconds: 2),
              backgroundColor: Colors.green,
            ),
          );
        } catch (e) {
          // 오류 무시
        }
      },
      icon: const Icon(Icons.bug_report, size: 18),
      label: Text('$count개 주문 전송'),
      style: AppStyles.primaryButton().copyWith(
        backgroundColor: WidgetStatePropertyAll(Colors.amber[700]),
      ),
    );
  }
}

/// 네트워크 장애 주입 섹션.
///
/// 2026-08-07 매장 장애(HTTP 20~30초 타임아웃·DNS 실패·소켓 생존)를 실기기에서
/// 재현해, 동기화 배너·in-flight 락·버튼 스피너·새로고침 정직화·건강도 회복
/// 재동기화를 검증한다. 프리셋이 주(主)이고 상세 파라미터는 보조.
///
/// 무장하면 화면 상단에 빨간 리본이 떠 있고(패닉 해제 버튼 겸용), 10분 후
/// 자동 해제된다. 앱 재시작으로도 해제된다(의도된 안전장치 — 영속화 금지).
class _NetFaultSection extends StatelessWidget {
  const _NetFaultSection();

  static const _presets = <_NetFaultPreset>[
    _NetFaultPreset(
      label: 'P1 매장 장애 재현',
      description: '전체 / DNS 실패 / 25초 / 무제한 — 배너·[API진단] 로그',
      color: Colors.red,
      config: NetFaultConfig(
        targets: {
          NetFaultTarget.orders,
          NetFaultTarget.orderDetail,
          NetFaultTarget.orderUpdate,
        },
        kind: NetFaultKind.dnsFailure,
        delay: Duration(seconds: 25),
      ),
    ),
    _NetFaultPreset(
      label: 'P2 느린 성공',
      description: '전체 / 지연만 / 25초 / 무제한 — 스피너·연타 차단, 배너는 안 떠야 정상',
      color: Colors.deepOrange,
      config: NetFaultConfig(
        targets: {
          NetFaultTarget.orders,
          NetFaultTarget.orderDetail,
          NetFaultTarget.orderUpdate,
        },
        kind: NetFaultKind.slowOnly,
        delay: Duration(seconds: 25),
      ),
    ),
    _NetFaultPreset(
      label: 'P3 상태변경 지연 실패',
      description: '상태변경만 / receiveTimeout / 20초 / 무제한 — KDS 스피너·in-flight 락',
      color: Colors.purple,
      config: NetFaultConfig(
        targets: {NetFaultTarget.orderUpdate},
        kind: NetFaultKind.receiveTimeout,
        delay: Duration(seconds: 20),
      ),
    ),
    _NetFaultPreset(
      label: 'P4 회복 전이',
      description: '목록만 / DNS 실패 / 즉시 / 2회 — 새로고침 2회로 배너, 3회째 소멸+재동기화',
      color: Colors.teal,
      config: NetFaultConfig(
        targets: {NetFaultTarget.orders},
        kind: NetFaultKind.dnsFailure,
        remaining: 2,
      ),
    ),
    _NetFaultPreset(
      label: 'P5 새로고침 상한',
      description: '목록만 / 지연만 / 90초 / 무제한 — 새로고침 60초 상한 발동',
      color: Colors.indigo,
      config: NetFaultConfig(
        targets: {NetFaultTarget.orders},
        kind: NetFaultKind.slowOnly,
        delay: Duration(seconds: 90),
      ),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<NetFaultConfig>(
      valueListenable: NetFaultInjector.state,
      builder: (context, cfg, _) {
        return SettingsItemWidget(
          title: '네트워크 장애 주입',
          description: '주문 API(목록/상세/상태변경)에 합성 장애를 주입해 열화 대응을 검증합니다. '
              '무장 시 화면 상단 빨간 리본(탭=해제), 10분 후 자동 해제. '
              '상세조회 지연은 소켓 재시도(x3)로 3배까지 늘어나므로 10초 이하 권장.',
          isVertical: true,
          trailing: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 현재 무장 상태
              if (cfg.isActive) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s8, vertical: AppSpacing.s4),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: AppRadius.bSm,
                    border: Border.all(color: Colors.red),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.warning_amber,
                          color: Colors.red, size: 18),
                      const SizedBox(width: AppSpacing.s4),
                      Text(
                        '무장중: ${cfg.targets.map(_targetName).join("·")} / '
                        '${cfg.kind.name} / ${cfg.delay.inSeconds}초 / '
                        '잔여 ${cfg.remaining ?? "∞"}',
                        style: const TextStyle(
                            color: Colors.red, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: AppSpacing.s8),
                      ElevatedButton(
                        onPressed: () {
                          NetFaultInjector.clear();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('네트워크 장애 주입 해제됨'),
                              duration: Duration(seconds: 2),
                              backgroundColor: Colors.green,
                            ),
                          );
                        },
                        style: AppStyles.primaryButton().copyWith(
                          backgroundColor:
                              const WidgetStatePropertyAll(Colors.green),
                        ),
                        child: const Text('해제'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.s8),
              ],
              // 프리셋 버튼
              Wrap(
                spacing: AppSpacing.s8,
                runSpacing: AppSpacing.s8,
                children: [
                  for (final p in _presets)
                    Tooltip(
                      message: p.description,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          NetFaultInjector.arm(p.config);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('${p.label} 무장 — ${p.description}'),
                              duration: const Duration(seconds: 3),
                              backgroundColor: p.color,
                            ),
                          );
                        },
                        icon: const Icon(Icons.network_check, size: 18),
                        label: Text(p.label),
                        style: AppStyles.primaryButton().copyWith(
                          backgroundColor: WidgetStatePropertyAll(p.color),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  static String _targetName(NetFaultTarget t) => switch (t) {
        NetFaultTarget.orders => '목록',
        NetFaultTarget.orderDetail => '상세',
        NetFaultTarget.orderUpdate => '상태변경',
      };
}

class _NetFaultPreset {
  final String label;
  final String description;
  final Color color;
  final NetFaultConfig config;

  const _NetFaultPreset({
    required this.label,
    required this.description,
    required this.color,
    required this.config,
  });
}
