import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:appfit_order_agent/utils/logger.dart';
import '../providers/providers.dart';
import '../providers/product_provider.dart';
import '../constants/app_styles.dart';
import '../services/platform_service.dart';
import '../services/local_server_service.dart';
import '../widgets/custom_switch.dart';
import '../services/preference_service.dart';
import 'package:audioplayers/audioplayers.dart';
import '../services/print_service.dart';
import 'package:appfit_order_agent/i18n/strings.g.dart';
import 'package:appfit_order_agent/providers/locale_provider.dart';
import '../widgets/common/common_dialog.dart';
import 'appfit_test_screen.dart';
import '../utils/mock_order_generator.dart' as __MockOrderGenerator;
import '../core/orders/order_queue_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final TextEditingController _serverUrlController = TextEditingController();
  final TextEditingController _storeIdController = TextEditingController();
  final TextEditingController _storeNameController = TextEditingController();

  final AudioPlayer _audioPlayer = AudioPlayer();
  final PreferenceService _preferenceService = PreferenceService();
  final ScrollController _leftScrollController = ScrollController();
  final ScrollController _rightScrollController = ScrollController();
  bool _isAutoStart = false;
  bool _isAutoReceipt = true;
  bool _isPrintOrder = true;
  bool _isUseExternalPrinter = false;
  bool _isUseLabelPrinter = false;
  bool _isUseBuiltinPrinter = true;
  bool _isKioskOrderVisible = false;
  bool _isKioskOrderSoundEnabled = false;
  bool _isOrderHistoryScroll = true; // 주문내역 보기설정 추가
  bool _isIgnoreOtherDeviceKds = false; // KDS 타 기기 이벤트 무시 설정 추가
  int _notificationVolume = 5;
  String _selectedSound = 'alert10.mp3';
  int _alertCount = 3;
  int _printCount = 1; // 주문서 출력 개수
  bool _isLocalServerEnabled = false; // 로컬 서버 활성화 상태

  // AudioPlayer 상태 관리를 위한 플래그 추가
  bool _isVolumeChanging = false;

  @override
  void initState() {
    super.initState();
    _setWindowSoftInputMode('resize');
    _loadSettings();
  }

  void _loadSettings() {
    setState(() {
      _storeIdController.text = _preferenceService.getStoreId() ?? '';
      _storeNameController.text = _preferenceService.getStoreName() ?? '';

      _isAutoStart = _preferenceService.getAutoLaunch();
      _isAutoReceipt = _preferenceService.getAutoReceipt();
      logger.i('설정 화면 로드 - 자동접수 설정: $_isAutoReceipt');
      _isPrintOrder = _preferenceService.getUsePrint();
      _isUseBuiltinPrinter = _preferenceService.getUseBuiltinPrinter();
      _isUseExternalPrinter = _preferenceService.getUseExternalPrinter();
      _isUseLabelPrinter = _preferenceService.getUseLabelPrinter();

      // 일반 모드에서는 저장된 설정을 사용
      _isKioskOrderVisible = _preferenceService.getShowKioskOrder();
      _isKioskOrderSoundEnabled = _preferenceService.getKioskPrintAndSound();

      _isOrderHistoryScroll = _preferenceService.getOrderHistoryScroll();
      _isIgnoreOtherDeviceKds =
          _preferenceService.getIgnoreOtherDeviceTasksKds();
      _notificationVolume = _preferenceService.getVolume();
      _selectedSound = _preferenceService.getSound();
      _alertCount = _preferenceService.getSoundNum();
      _printCount = _preferenceService.getPrintCount();
      _isLocalServerEnabled = _preferenceService.getLocalServerEnabled();
    });
  }

  Future<void> _saveSettings() async {
    try {
      await _preferenceService.setAutoLaunch(_isAutoStart);
      await _preferenceService.setAutoReceipt(_isAutoReceipt);
      logger.i('설정 저장 - 자동접수 설정: $_isAutoReceipt');
      await _preferenceService.setUsePrint(_isPrintOrder);
      await _preferenceService.setUseBuiltinPrinter(_isUseBuiltinPrinter);
      await _preferenceService.setUseExternalPrinter(_isUseExternalPrinter);
      await _preferenceService.setUseLabelPrinter(_isUseLabelPrinter);
      await _preferenceService.setShowKioskOrder(_isKioskOrderVisible);
      await _preferenceService.setKioskPrintAndSound(_isKioskOrderSoundEnabled);
      await _preferenceService.setOrderHistoryScroll(_isOrderHistoryScroll);
      await _preferenceService
          .setIgnoreOtherDeviceTasksKds(_isIgnoreOtherDeviceKds);
      await _preferenceService.setVolume(_notificationVolume);
      await _preferenceService.setSound(_selectedSound);
      await _preferenceService.setSoundNum(_alertCount);
      await _preferenceService.setPrintCount(_printCount);
      await _preferenceService.setLocalServerEnabled(_isLocalServerEnabled);

      // orderHistoryScrollProvider 상태 업데이트
      ref.read(orderHistoryScrollProvider.notifier).state =
          _isOrderHistoryScroll;

      // 저장 성공 시 SnackBar 표시 (선택적)
      if (mounted) {
        /*ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t.settings.save_success),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.green,
          ),
        );*/
      }
    } catch (e) {
      logger.e('Error saving settings', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t.settings.save_error(error: e.toString())),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handleModeSwitch(bool currentIsKdsMode) async {
    final title = currentIsKdsMode ? '메인 시스템으로 전환' : 'KDS 모드로 전환';
    final content = currentIsKdsMode
        ? '메인 시스템(일반 접수)으로 전환하시겠습니까?'
        : '주방모니터(KDS) 전용 시스템으로 전환하시겠습니까?';

    final bool? confirm = await CommonDialog.showConfirmDialog(
      context: context,
      title: title,
      content: content,
      confirmText: '전환하기',
      cancelText: '취소',
    );

    if (confirm == true) {
      final newMode = !currentIsKdsMode;
      // Preference 저장
      await _preferenceService.setSubDisplay(newMode);

      // 상태 업데이트
      ref.read(kdsModeProvider.notifier).setKdsMode(newMode);

      // KDS 모드로 전환 시 로컬 서버 중지 보장
      if (newMode) {
        final localServer = LocalServerService.instance;
        if (localServer != null) {
          await localServer.stopServer();
          logger.i('[SettingsScreen] KDS 모드 전환: 로컬 서버 중지 완료');
        }
      }

      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
        Future.delayed(const Duration(milliseconds: 100), () {
          ref.read(orderProvider.notifier).reloadSettings();
        });
      }
    }
  }

  Widget _buildModeSwitchItem(bool isKdsMode) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16.0),
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: isKdsMode
            ? AppStyles.kMainColor.withValues(alpha: 0.1)
            : Colors.blue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isKdsMode ? AppStyles.kMainColor : Colors.blue,
          width: 1.5,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                isKdsMode ? Icons.point_of_sale : Icons.kitchen,
                color: isKdsMode ? AppStyles.kMainColor : Colors.blue,
                size: 28,
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isKdsMode ? '메인 시스템으로 전환' : 'KDS 모드로 전환',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color:
                          isKdsMode ? AppStyles.kMainColor : Colors.blue[800],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isKdsMode ? '일반 접수 화면으로 변경합니다.' : '주방 전용 모니터로 변경합니다.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ],
          ),
          ElevatedButton(
            onPressed: () => _handleModeSwitch(isKdsMode),
            style: ElevatedButton.styleFrom(
              backgroundColor: isKdsMode ? AppStyles.kMainColor : Colors.blue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('전환하기',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _playSound(String soundFile) async {
    try {
      await _audioPlayer.play(AssetSource('sounds/$soundFile'));
    } catch (e) {
      logger.e('Error playing sound', error: e);
      // 사용자에게 SnackBar로 에러 알림 추가
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('알림음 재생 중 오류가 발생했습니다: $e'),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // 안전한 사운드 재생 메서드 (음량 조절용)
  Future<void> _playSoundSafely(String soundFile) async {
    try {
      await _audioPlayer.play(AssetSource('sounds/$soundFile'));
    } catch (e) {
      // AudioPlayer 재생 실패 시 재시도 (한 번만)
      logger.w('첫 번째 재생 시도 실패, 재시도: $e');
      try {
        await Future.delayed(const Duration(milliseconds: 100));
        await _audioPlayer.play(AssetSource('sounds/$soundFile'));
      } catch (retryError, retryStack) {
        logger.e('사운드 재생 재시도도 실패', error: retryError, stackTrace: retryStack);
        // 사용자에게 알림 (기존 SnackBar 로직 유지)
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('알림음 재생 중 오류가 발생했습니다: $retryError'),
              duration: const Duration(seconds: 3),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Widget _buildSettingItem({
    required String title,
    required String description,
    required Widget trailing,
    Widget? additionalContent,
    bool enabled = true,
    bool isVertical = false,
  }) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: IgnorePointer(
        ignoring: !enabled,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              child: isVertical
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          description,
                          style: TextStyle(
                            fontSize: 14,
                            color: enabled ? Colors.grey[600] : Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 12),
                        trailing,
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                description,
                                style: TextStyle(
                                  fontSize: 14,
                                  color:
                                      enabled ? Colors.grey[600] : Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        trailing,
                      ],
                    ),
            ),
            if (additionalContent != null) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: additionalContent,
              ),
            ],
            const Divider(),
          ],
        ),
      ),
    );
  }

  Widget _buildSoundButton(String value, String label) {
    final isSelected = _selectedSound == value;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: ElevatedButton(
        onPressed: () async {
          setState(() {
            _selectedSound = value;
            logToFile(tag: LogTag.UI_ACTION, message: '알림음 변경 -> $value');
          });
          await _saveSettings();
          await _playSound(value);
          ref.read(orderProvider.notifier).updateSoundSettings();
        },
        style: settingsButtonStyle(isSelected),
        child: Text(
          label,
          style: TextStyle(
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
        ),
      ),
    );
  }

  Widget _buildAlertCountButton(int value, String label) {
    final isSelected = _alertCount == value;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: ElevatedButton(
        onPressed: () async {
          setState(() {
            _alertCount = value;
          });
          await _preferenceService.setSoundNum(value);
          ref.read(orderProvider.notifier).updateSoundSettings();
          logToFile(tag: LogTag.UI_ACTION, message: '알림횟수 변경 -> $value회');
        },
        style: settingsButtonStyle(isSelected),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildPrintCountButton(int value, String label) {
    final isSelected = _printCount == value;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: ElevatedButton(
        onPressed: () async {
          setState(() {
            _printCount = value;
          });
          await _preferenceService.setPrintCount(value);
          logToFile(tag: LogTag.UI_ACTION, message: '주문서 출력 개수 변경 -> $value개');
        },
        style: settingsButtonStyle(isSelected),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildConnectionStatus({
    required bool isConnected,
    required VoidCallback onReconnect,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isConnected ? Icons.check_circle : Icons.error_outline,
            size: 16,
            color: isConnected ? Colors.green : Colors.red,
          ),
          const SizedBox(width: 8),
          Text(
            isConnected ? '연결됨' : '연결 안 됨',
            style: TextStyle(
              color: isConnected ? Colors.green[700] : Colors.red[700],
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            height: 28,
            child: ElevatedButton(
              onPressed: onReconnect,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.grey[800],
                elevation: 0,
                side: BorderSide(color: Colors.grey[400]!),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                textStyle: const TextStyle(fontSize: 12),
              ),
              child: const Text('재연결'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isKdsMode = ref.watch(kdsModeProvider);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 좌측 영역
        Expanded(
          child: Scrollbar(
            controller: _leftScrollController,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _leftScrollController,
              padding:
                  const EdgeInsets.only(left: 16.0, right: 16.0, top: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildModeSwitchItem(isKdsMode),
                  _buildSettingItem(
                    title: t.settings.language.title,
                    description: t.settings.language.desc,
                    trailing: _buildLanguageSwitcher(),
                    isVertical: true,
                  ),
                  _buildSettingItem(
                    title: t.settings.auto_start.title,
                    description: isKdsMode
                        ? t.settings.auto_start.desc
                        : t.settings.auto_start.desc_general,
                    isVertical: false,
                    trailing: CustomSwitch(
                      value: _isAutoStart,
                      activeColor: AppStyles.kMainColor,
                      inactiveColor: Colors.grey,
                      activeText: t.settings.auto_start.on,
                      inactiveText: t.settings.auto_start.off,
                      onChanged: (value) {
                        setState(() {
                          _isAutoStart = value;
                          logToFile(
                              tag: LogTag.UI_ACTION,
                              message: 'PC시작 시 자동 실행 변경 -> $value');
                        });
                        _saveSettings();
                      },
                    ),
                  ),
                  if (isKdsMode)
                    _buildSettingItem(
                      title: '타 기기 진행상태 알림 무시',
                      description:
                          '다른 KDS에서 픽업 요청 등 진행상태를 변경해도 내 화면의 주문이 새로고침되지 않습니다. (진행상태 최신화를 수동으로 통제하고 싶을 때 사용)',
                      trailing: CustomSwitch(
                        value: _isIgnoreOtherDeviceKds,
                        activeColor: AppStyles.kMainColor,
                        inactiveColor: Colors.grey,
                        activeText: t.settings.auto_start.on, // 'ON'
                        inactiveText: t.settings.auto_start.off, // 'OFF'
                        onChanged: (value) {
                          setState(() {
                            _isIgnoreOtherDeviceKds = value;
                            logToFile(
                                tag: LogTag.UI_ACTION,
                                message: 'KDS 타 기기 진행상태 무시 변경 -> $value');
                          });
                          _saveSettings();
                        },
                      ),
                    ),
                  if (!isKdsMode)
                    _buildSettingItem(
                      title: t.settings.auto_receipt.title,
                      description: t.settings.auto_receipt.desc,
                      trailing: CustomSwitch(
                        value: _isAutoReceipt,
                        activeColor: AppStyles.kMainColor,
                        inactiveColor: Colors.grey,
                        activeText: t.settings.auto_start.on,
                        inactiveText: t.settings.auto_start.off,
                        onChanged: (value) {
                          setState(() {
                            _isAutoReceipt = value;
                            logToFile(
                                tag: LogTag.UI_ACTION,
                                message: '픽업 오더 자동 접수 변경 -> $value');
                          });
                          logger.i('자동접수 설정 변경 - UI에서: $value');
                          _saveSettings();
                          ref
                              .read(orderProvider.notifier)
                              .updateAutoReceipt(value);
                        },
                      ),
                    ),
                  _buildSettingItem(
                    title: t.settings.print_order.title,
                    description: t.settings.print_order.desc,
                    trailing: CustomSwitch(
                      value: _isPrintOrder,
                      activeColor: AppStyles.kMainColor,
                      inactiveColor: Colors.grey,
                      activeText: t.settings.auto_start.on,
                      inactiveText: t.settings.auto_start.off,
                      onChanged: (value) {
                        setState(() {
                          _isPrintOrder = value;
                          if (!_isPrintOrder) {
                            _isUseBuiltinPrinter = false;
                            _isUseExternalPrinter = false;
                            // PrintService 캐시 업데이트
                            ref
                                .read(printServiceProvider)
                                .updatePrinterSettings(
                                  builtinPrinter: false,
                                  externalPrinter: false,
                                );
                          } else {
                            if (!_isUseBuiltinPrinter &&
                                !_isUseExternalPrinter) {
                              _isUseBuiltinPrinter = true;
                              // PrintService 캐시 업데이트
                              ref
                                  .read(printServiceProvider)
                                  .updatePrinterSettings(
                                    builtinPrinter: true,
                                    externalPrinter: false,
                                  );
                            }
                          }
                          logToFile(
                              tag: LogTag.UI_ACTION,
                              message: '주문서 출력 변경 -> $_isPrintOrder');
                        });
                        _saveSettings();
                      },
                    ),
                  ),
                  _buildSettingItem(
                    title: t.settings.builtin_printer.title,
                    description: t.settings.builtin_printer.desc,
                    enabled: _isPrintOrder,
                    trailing: CustomSwitch(
                      value: _isUseBuiltinPrinter,
                      activeColor: AppStyles.kMainColor,
                      inactiveColor: Colors.grey,
                      activeText: t.settings.auto_start.on,
                      inactiveText: t.settings.auto_start.off,
                      onChanged: (value) {
                        if (!_isPrintOrder) return;
                        setState(() {
                          _isUseBuiltinPrinter = value;
                          logToFile(
                              tag: LogTag.UI_ACTION,
                              message:
                                  '기기 내장 프린터 사용 변경 -> $_isUseBuiltinPrinter');
                        });
                        _saveSettings();
                        // PrintService 캐시 업데이트
                        ref.read(printServiceProvider).updatePrinterSettings(
                              builtinPrinter: _isUseBuiltinPrinter,
                            );
                      },
                    ),
                  ),
                  _buildSettingItem(
                    title: t.settings.external_printer.title,
                    description: t.settings.external_printer.desc,
                    enabled: _isPrintOrder,
                    trailing: CustomSwitch(
                      value: _isUseExternalPrinter,
                      activeColor: AppStyles.kMainColor,
                      inactiveColor: Colors.grey,
                      activeText: t.settings.auto_start.on,
                      inactiveText: t.settings.auto_start.off,
                      onChanged: (value) {
                        if (!_isPrintOrder) return;
                        setState(() {
                          _isUseExternalPrinter = value;
                          logToFile(
                              tag: LogTag.UI_ACTION,
                              message:
                                  '외부 프린터 사용 변경 -> $_isUseExternalPrinter');
                        });
                        _saveSettings();
                        // PrintService 캐시 업데이트
                        final printService = ref.read(printServiceProvider);
                        printService.updatePrinterSettings(
                          externalPrinter: _isUseExternalPrinter,
                        );
                        // 활성화 시 즉시 연결 확인
                        if (value) {
                          printService.checkConnection();
                        }
                      },
                    ),
                    additionalContent: Consumer(
                      builder: (context, ref, child) {
                        final status = ref.watch(printerStatusProvider);
                        return _buildConnectionStatus(
                          isConnected: status.isExternalConnected,
                          onReconnect: () =>
                              ref.read(printServiceProvider).checkConnection(),
                        );
                      },
                    ),
                  ),
                  _buildSettingItem(
                    title: t.settings.label_printer.title,
                    description: t.settings.label_printer.desc,
                    // enabled: _isPrintOrder, // 독립적으로 동작하도록 종속성 제거
                    trailing: CustomSwitch(
                      value: _isUseLabelPrinter,
                      activeColor: AppStyles.kMainColor,
                      inactiveColor: Colors.grey,
                      activeText: t.settings.auto_start.on,
                      inactiveText: t.settings.auto_start.off,
                      onChanged: (value) {
                        // if (!_isPrintOrder) return; // 독립적으로 동작하도록 종속성 제거
                        setState(() {
                          _isUseLabelPrinter = value;
                          logToFile(
                              tag: LogTag.UI_ACTION,
                              message: '라벨 프린터 사용 변경 -> $_isUseLabelPrinter');
                        });
                        _saveSettings();
                        // PrintService 캐시 업데이트
                        final printService = ref.read(printServiceProvider);
                        printService.updatePrinterSettings(
                          labelPrinter: _isUseLabelPrinter,
                        );
                        // 활성화 시 즉시 연결 확인
                        if (value) {
                          printService.checkConnection();
                        }
                      },
                    ),
                    additionalContent: Consumer(
                      builder: (context, ref, child) {
                        final status = ref.watch(printerStatusProvider);
                        return _buildConnectionStatus(
                          isConnected: status.isLabelConnected,
                          onReconnect: () =>
                              ref.read(printServiceProvider).checkConnection(),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // 우측 영역
        Expanded(
          child: Scrollbar(
            controller: _rightScrollController,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _rightScrollController,
              padding:
                  const EdgeInsets.only(left: 16.0, right: 16.0, top: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildSettingItem(
                    title: t.settings.volume.title,
                    description: t.settings.volume.desc,
                    trailing: SizedBox(
                      width: 300,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              Expanded(
                                child: Slider(
                                  value: _notificationVolume.toDouble(),
                                  min: 0,
                                  max: 10,
                                  label: _notificationVolume.round().toString(),
                                  onChanged: (value) {
                                    setState(() {
                                      _notificationVolume = value.toInt();
                                    });
                                  },
                                  onChangeEnd: (value) async {
                                    if (_isVolumeChanging) return;
                                    _isVolumeChanging = true;

                                    try {
                                      _saveSettings();

                                      try {
                                        await _audioPlayer.stop();
                                      } catch (e) {
                                        logger
                                            .d('AudioPlayer stop 실패 (무시): $e');
                                      }

                                      await Future.delayed(
                                          const Duration(milliseconds: 100));

                                      await _audioPlayer
                                          .setVolume(value / 10.0);

                                      var audioContext = AudioContext(
                                        android: const AudioContextAndroid(
                                          audioFocus: AndroidAudioFocus.none,
                                        ),
                                      );
                                      await _audioPlayer
                                          .setAudioContext(audioContext);

                                      await Future.delayed(
                                          const Duration(milliseconds: 50));

                                      await _playSoundSafely('alert10.mp3');

                                      ref
                                          .read(orderProvider.notifier)
                                          .updateSoundSettings();

                                      logToFile(
                                          tag: LogTag.UI_ACTION,
                                          message:
                                              '알림음 크기 변경 -> ${value.toInt()}');
                                    } catch (e, s) {
                                      logger.e('음량 변경 중 오류 발생',
                                          error: e, stackTrace: s);
                                    } finally {
                                      _isVolumeChanging = false;
                                    }
                                  },
                                  activeColor: AppStyles.kMainColor,
                                  inactiveColor:
                                      AppStyles.kMainColor.withOpacity(0.3),
                                ),
                              ),
                              Text(
                                '${_notificationVolume.round()}',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  _buildSettingItem(
                    title: t.settings.sound.title,
                    description: t.settings.sound.desc,
                    isVertical: true,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildSoundButton(
                            'sound1.mp3', t.settings.sound.sound1),
                        const SizedBox(width: 8),
                        _buildSoundButton(
                            'sound2.mp3', t.settings.sound.sound2),
                      ],
                    ),
                  ),
                  // 공통 설정 (KDS 모드와 일반 모드 모두)
                  _buildSettingItem(
                    title: t.settings.alert_count.title,
                    description: t.settings.alert_count.desc,
                    isVertical: true,
                    trailing: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildAlertCountButton(
                              1, t.settings.alert_count.count(n: 1)),
                          _buildAlertCountButton(
                              3, t.settings.alert_count.count(n: 3)),
                          _buildAlertCountButton(
                              5, t.settings.alert_count.count(n: 5)),
                          _buildAlertCountButton(
                              10, t.settings.alert_count.count(n: 10)),
                          _buildAlertCountButton(
                              0, t.settings.alert_count.unlimited),
                        ],
                      ),
                    ),
                  ),

                  // 로컬 서버 설정 (일반 모드에서만 표시)
                  if (!isKdsMode) ...[
                    _buildSettingItem(
                      title: t.settings.local_server.title,
                      description: t.settings.local_server.desc,
                      trailing: CustomSwitch(
                        value: _isLocalServerEnabled,
                        activeColor: AppStyles.kMainColor,
                        inactiveColor: Colors.grey,
                        activeText: 'ON',
                        inactiveText: 'OFF',
                        onChanged: (value) async {
                          setState(() {
                            _isLocalServerEnabled = value;
                          });
                          await _preferenceService.setLocalServerEnabled(value);

                          // Server Start/Stop Logic
                          final localServer = LocalServerService.instance;
                          if (localServer != null) {
                            if (value) {
                              try {
                                final productState = ref.read(productProvider);
                                if (productState.hasValue &&
                                    productState.value != null) {
                                  await localServer.startServer(
                                      products: productState.value!);
                                } else {
                                  await localServer.startServer();
                                }
                              } catch (e) {
                                logger.w('상품 데이터 로드 실패, 서버만 시작', error: e);
                                await localServer.startServer();
                              }

                              if (mounted) {
                                final serverUrl = localServer.serverUrl;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                        '로컬 서버가 시작되었습니다.\nURL: ${serverUrl ?? "Unknown"}'),
                                    duration: const Duration(seconds: 4),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                                setState(() {}); // Refresh for info box
                              }
                            } else {
                              await localServer.stopServer();
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('로컬 서버가 중지되었습니다.'),
                                    duration: Duration(seconds: 2),
                                    backgroundColor: Colors.orange,
                                  ),
                                );
                                setState(() {}); // Refresh for info box
                              }
                            }
                          }
                        },
                      ),
                    ),
                    if (_isLocalServerEnabled)
                      Padding(
                        padding: const EdgeInsets.only(
                            left: 16, right: 16, bottom: 16),
                        child: StatefulBuilder(
                          builder: (context, setState) {
                            final localServer = LocalServerService.instance;
                            final serverUrl = localServer?.serverUrl;
                            final localIp = localServer?.localIp;

                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: Colors.green.withOpacity(0.3)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    t.settings.local_server.info,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green[700],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    t.settings.local_server
                                        .ip(ip: localIp ?? 'Loading...'),
                                    style: TextStyle(color: Colors.green[600]),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    t.settings.local_server
                                        .port(port: localServer?.port ?? 8080),
                                    style: TextStyle(color: Colors.green[600]),
                                  ),
                                  if (serverUrl != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      t.settings.local_server
                                          .url(url: serverUrl),
                                      style:
                                          TextStyle(color: Colors.green[600]),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                  ],

                  // 주문서 출력 매수 설정
                  _buildSettingItem(
                    title: t.settings.print_count.title,
                    description: t.settings.print_count.desc,
                    isVertical: true,
                    trailing: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildPrintCountButton(
                              1, t.settings.print_count.count(n: 1)),
                          _buildPrintCountButton(
                              2, t.settings.print_count.count(n: 2)),
                          _buildPrintCountButton(
                              3, t.settings.print_count.count(n: 3)),
                          _buildPrintCountButton(
                              4, t.settings.print_count.count(n: 4)),
                          _buildPrintCountButton(
                              5, t.settings.print_count.count(n: 5)),
                        ],
                      ),
                    ),
                  ),
                  // KDS 모드일 때만 표시할 설정 (현재 미사용)
                  /*if (isKdsMode) ...[
                  _buildSettingItem(
                    title: '주문내역 보기설정',
                    description: '주문내역 표시 방식을 설정합니다.',
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildOrderHistoryScrollButton(true, '스크롤 O'),
                        _buildOrderHistoryScrollButton(false, '스크롤 X'),
                      ],
                    ),
                  ),
                ],*/

                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16.0, vertical: 8.0),
                    child: Text(
                      t.settings.developer_options.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                  _buildSettingItem(
                    title: t.settings.developer_options.appfit_test.title,
                    description: t.settings.developer_options.appfit_test.desc,
                    isVertical: true,
                    trailing: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const AppFitTestScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.science, size: 18),
                      label: Text(t.settings.developer_options.appfit_test.btn),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  _buildSettingItem(
                    title: '대량 주문 처리 테스트 (로컬)',
                    description:
                        '가상 주문을 대량으로 생성하여 내부 큐 파이프라인(순서 정렬, UI출력, 라벨/영수증 인쇄 등)을 테스트합니다.',
                    isVertical: true,
                    trailing: Wrap(
                      spacing: 8.0,
                      runSpacing: 8.0,
                      children: [
                        _buildBulkTestButton(10),
                        _buildBulkTestButton(50),
                        _buildBulkTestButton(100),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLanguageSwitcher() {
    final currentLocale = ref.watch(localeNotifierProvider);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: AppLocale.values.map((locale) {
        final isSelected = currentLocale == locale;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: ElevatedButton(
            onPressed: () {
              ref.read(localeNotifierProvider.notifier).changeLocale(locale);
              logToFile(
                  tag: LogTag.UI_ACTION,
                  message: '언어 변경 -> ${locale.languageCode}');
            },
            style: settingsButtonStyle(isSelected),
            child: Text(
              _getLocaleDisplay(locale),
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  String _getLocaleDisplay(AppLocale locale) {
    switch (locale) {
      case AppLocale.ko:
        return '한국어';
      case AppLocale.en:
        return 'English';
      case AppLocale.ja:
        return '日本語';
    }
  }

  Widget _buildBulkTestButton(int count) {
    return ElevatedButton.icon(
      onPressed: () {
        importMockGeneratorAndExecute(count);
      },
      icon: const Icon(Icons.bug_report, size: 18),
      label: Text('$count개 주문 전송'),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.amber[700],
        foregroundColor: Colors.white,
      ),
    );
  }

  void importMockGeneratorAndExecute(int count) {
    try {
      final mockOrders =
          __MockOrderGenerator.MockOrderGenerator.generateMockOrders(count);
      ref.read(orderQueueAppServiceProvider).enqueueAll(mockOrders);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$count개의 가상 주문이 큐에 추가되었습니다.'),
          duration: const Duration(seconds: 2),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e, s) {
      logger.e('Mock Order Generation Failed', error: e, stackTrace: s);
    }
  }

  Future<void> _setWindowSoftInputMode(String mode) async {
    try {
      await platform
          .invokeMethod(mode == 'pan' ? 'setAdjustPan' : 'setAdjustResize');
    } on PlatformException catch (e) {
      logger.w("Failed to set windowSoftInputMode: '${e.message}'.");
    }
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _storeIdController.dispose();
    _storeNameController.dispose();
    _audioPlayer.dispose();
    _leftScrollController.dispose();
    _rightScrollController.dispose();
    super.dispose();
  }

  settingsButtonStyle(bool isSelected) {
    return ElevatedButton.styleFrom(
      shape: RoundedRectangleBorder(
        side: BorderSide(
            color: isSelected ? AppStyles.kMainColor : AppStyles.gray4,
            width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      elevation: 0,
      backgroundColor: Colors.white,
      foregroundColor: isSelected ? AppStyles.kMainColor : AppStyles.gray6,
      minimumSize: const Size(60, 40),
    );
  }
}
