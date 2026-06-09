import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:appfit_order_agent/constants/app_styles.dart';
import 'package:appfit_order_agent/providers/providers.dart';
import 'package:appfit_order_agent/core/orders/order_queue_service.dart';
import 'package:appfit_order_agent/dev/mock_order_generator.dart' as mock_gen;
import 'package:appfit_order_agent/dev/order_detail_fault_injector.dart';
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
        // 상세조회 강제 실패 (디버그 fault injection) — debug 빌드에서만 노출/동작
        if (kDebugMode)
          SettingsItemWidget(
            title: '상세조회 강제 실패 (디버그)',
            description: 'getOrder 를 인위적으로 실패시켜 재시도·복구·부분영수증 차단을 검증합니다. '
                '실제 소켓으로 들어오는 주문의 상세조회에 적용됩니다 '
                '(MOCK 대량주문은 상세조회를 거치지 않아 미적용).',
            isVertical: true,
            trailing: Wrap(
              spacing: AppSpacing.s8,
              runSpacing: AppSpacing.s8,
              children: [
                _faultButton(context, '503 x2 (재시도→성공)', 2,
                    OrderDetailFaultKind.serverError, Colors.deepOrange),
                _faultButton(context, '503 x99 (소진→복구)', 99,
                    OrderDetailFaultKind.serverError, Colors.red),
                _faultButton(context, '404 x1 (즉시실패)', 1,
                    OrderDetailFaultKind.notFound, Colors.brown),
                _faultButton(context, '타임아웃 x99', 99,
                    OrderDetailFaultKind.timeout, Colors.blueGrey),
                _faultClearButton(context),
              ],
            ),
          ),
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

  /// 상세조회 강제 실패 무장 버튼 (디버그 전용).
  Widget _faultButton(BuildContext context, String label, int count,
      OrderDetailFaultKind kind, Color color) {
    return ElevatedButton.icon(
      onPressed: () {
        OrderDetailFaultInjector.arm(count, kind);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('상세조회 강제 실패 무장: $label'),
            duration: const Duration(seconds: 2),
            backgroundColor: color,
          ),
        );
      },
      icon: const Icon(Icons.error_outline, size: 18),
      label: Text(label),
      style: AppStyles.primaryButton().copyWith(
        backgroundColor: WidgetStatePropertyAll(color),
      ),
    );
  }

  /// 상세조회 강제 실패 해제 버튼 (디버그 전용).
  Widget _faultClearButton(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: () {
        OrderDetailFaultInjector.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('상세조회 강제 실패 해제됨'),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.green,
          ),
        );
      },
      icon: const Icon(Icons.check_circle_outline, size: 18),
      label: const Text('해제'),
      style: AppStyles.primaryButton().copyWith(
        backgroundColor: const WidgetStatePropertyAll(Colors.grey),
      ),
    );
  }

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
