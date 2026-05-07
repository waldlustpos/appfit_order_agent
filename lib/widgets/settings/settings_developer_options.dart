import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../constants/app_styles.dart';
import '../../providers/providers.dart';
import '../../core/orders/order_queue_service.dart';
import '../../utils/mock_order_generator.dart' as mock_gen;
import '../../screens/appfit_test_screen.dart';
import 'package:appfit_order_agent/i18n/strings.g.dart';
import 'settings_section_card.dart';
import 'settings_item_widget.dart';
import 'settings_label_test_section.dart';
import '../../widgets/custom_switch.dart';

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
