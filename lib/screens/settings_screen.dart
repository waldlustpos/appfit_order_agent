import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:appfit_order_agent/config/app_env.dart';
import 'package:appfit_order_agent/utils/logger.dart';
import 'package:appfit_order_agent/utils/label_painter.dart';
import 'package:appfit_order_agent/providers/providers.dart';
import 'package:appfit_order_agent/providers/product_provider.dart';
import 'package:appfit_order_agent/constants/app_styles.dart';
import 'package:appfit_order_agent/services/platform_service.dart';
import 'package:appfit_order_agent/services/local_server_service.dart';
import 'package:appfit_order_agent/services/preference_service.dart';
import 'package:appfit_order_agent/services/windows_update_service.dart';
import 'package:appfit_order_agent/widgets/update/update_progress_dialog.dart';
import 'package:appfit_order_agent/widgets/common/common_dialog.dart';
import 'package:appfit_order_agent/services/appfit/appfit_providers.dart'
    as appfit_providers;
import 'package:appfit_order_agent/i18n/strings.g.dart';
import 'package:appfit_order_agent/config/ota_config.dart';
import 'package:appfit_order_agent/services/secure_storage_service.dart';
import 'package:appfit_order_agent/widgets/settings/settings_left_panel.dart';
import 'package:appfit_order_agent/widgets/settings/settings_right_panel.dart';
import 'package:appfit_core/appfit_core.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final PreferenceService _preferenceService;

  // ── 상태 변수 ──────────────────────────────────────────────────────────────
  bool _isAutoStart = false;
  bool _isAutoReceipt = true;
  bool _isPrintOrder = true;
  bool _isUseExternalPrinter = false;
  bool _isUseLabelPrinter = false;
  bool _isUseBuiltinPrinter = true;

  // 프린터 × 출력물 매트릭스 (내장/외부 × 주문서/영수증)
  bool _builtinPrintOrder = true;
  bool _builtinPrintReceipt = true;
  bool _externalPrintOrder = true;
  bool _externalPrintReceipt = true;
  bool _builtinPrintCall = true;
  bool _externalPrintCall = true;

  int _labelAutoReplyMode = 1;
  bool _labelUseFeedToTear = true;
  bool _labelUseBackToPrint = true;
  bool _labelUseCalibrate = false;
  bool _labelUseQrPrint = false;
  int _labelFilterMode = 0;
  int _labelLayoutVersion = 0;
  int _labelQrPayloadFormat = 0;

  bool _isKioskOrderVisible = false;
  bool _isKioskOrderSoundEnabled = false;
  bool _isShowOrderTypeBadge = false;
  bool _isOrderSourceColor = false;
  bool _isOrderHistoryScroll = true;
  bool _isIgnoreOtherDeviceKds = false;
  bool _isKdsAcceptOrders = false;
  bool _forceSocketReconnect = false;

  int _devOptionsTapCount = 0;
  bool _isDevOptionsVisible = false;

  int _notificationVolume = 5;
  String _selectedSound = 'alert10.mp3';
  int _alertCount = 3;
  int _printCount = 1;
  bool _isLocalServerEnabled = false;
  bool _isLocalServerRunning = false;
  bool _isRotated180 = false;
  bool _isAutoCheckUpdate = true;
  bool _isCheckingUpdate = false;
  UpdateInfo? _updateInfo;
  late String _selectedEnv;
  bool _isSoundGraphEnabled = false;
  String _soundGraphMarketId = '';

  @override
  void initState() {
    super.initState();
    _preferenceService = ref.read(preferenceServiceProvider);
    _selectedEnv = _preferenceService.getEnvironment();
    _setWindowSoftInputMode('resize');
    _loadSettings();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkUpdateFromSettings();
      // 프린터 연결 상태 자동 1회 갱신. USB hot-plug 이벤트 구독이 없어
      // checkConnection 은 앱 시작 시 1회만 도는데, 사용자가 USB 를 빼고
      // 설정 화면에 들어왔을 때 "연결됨" 이 stale 하게 표시되는 사고 방지.
      // 이후 갱신은 재연결 버튼으로 사용자가 직접 트리거.
      ref.read(printServiceProvider).checkConnection();
    });
  }

  // ── 설정 로드 / 저장 ───────────────────────────────────────────────────────

  void _loadSettings() {
    setState(() {
      _isAutoStart = _preferenceService.getAutoLaunch();
      _isAutoReceipt = _preferenceService.getAutoReceipt();
      logger.i('설정 화면 로드 - 자동접수 설정: $_isAutoReceipt');
      _isPrintOrder = _preferenceService.getUsePrint();
      _isUseBuiltinPrinter = _preferenceService.getUseBuiltinPrinter();
      _isUseExternalPrinter = _preferenceService.getUseExternalPrinter();
      _isUseLabelPrinter = _preferenceService.getUseLabelPrinter();
      _builtinPrintOrder = _preferenceService.getBuiltinPrintOrder();
      _builtinPrintReceipt = _preferenceService.getBuiltinPrintReceipt();
      _externalPrintOrder = _preferenceService.getExternalPrintOrder();
      _externalPrintReceipt = _preferenceService.getExternalPrintReceipt();
      _builtinPrintCall = _preferenceService.getBuiltinPrintCall();
      _externalPrintCall = _preferenceService.getExternalPrintCall();

      _labelAutoReplyMode = _preferenceService.getLabelAutoReplyMode();
      _labelUseFeedToTear = _preferenceService.getLabelUseFeedToTear();
      _labelUseBackToPrint = _preferenceService.getLabelUseBackToPrint();
      _labelUseCalibrate = _preferenceService.getLabelUseCalibrate();
      _labelUseQrPrint = _preferenceService.getLabelUseQrPrint();
      _labelFilterMode = _preferenceService.getLabelFilterMode();
      _labelLayoutVersion = _preferenceService.getLabelLayoutVersion();
      _labelQrPayloadFormat = _preferenceService.getLabelQrPayloadFormat();

      _isKioskOrderVisible = _preferenceService.getShowKioskOrder();
      _isKioskOrderSoundEnabled = _preferenceService.getKioskPrintAndSound();
      _isShowOrderTypeBadge = _preferenceService.getShowOrderTypeBadge();
      _isOrderSourceColor = _preferenceService.getOrderSourceColor();
      _isOrderHistoryScroll = _preferenceService.getOrderHistoryScroll();
      _isIgnoreOtherDeviceKds =
          _preferenceService.getIgnoreOtherDeviceTasksKds();
      _isKdsAcceptOrders = _preferenceService.getKdsAcceptOrders();
      _forceSocketReconnect = _preferenceService.getForceSocketReconnect();
      _notificationVolume = _preferenceService.getVolume();
      _selectedSound = _preferenceService.getSound();
      _alertCount = _preferenceService.getSoundNum();
      _printCount = _preferenceService.getPrintCount();
      _isLocalServerEnabled = _preferenceService.getLocalServerEnabled();
      _isLocalServerRunning = LocalServerService.instance?.isRunning ?? false;
      _isRotated180 = _preferenceService.getIsRotated180();
      _isAutoCheckUpdate = _preferenceService.getAutoCheckUpdate();
      _isSoundGraphEnabled = _preferenceService.getSoundGraphOn();
      _soundGraphMarketId = _preferenceService.getSoundGraphMarketId();
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
      await _preferenceService.setBuiltinPrintOrder(_builtinPrintOrder);
      await _preferenceService.setBuiltinPrintReceipt(_builtinPrintReceipt);
      await _preferenceService.setExternalPrintOrder(_externalPrintOrder);
      await _preferenceService.setExternalPrintReceipt(_externalPrintReceipt);
      await _preferenceService.setBuiltinPrintCall(_builtinPrintCall);
      await _preferenceService.setExternalPrintCall(_externalPrintCall);
      await _preferenceService.setLabelAutoReplyMode(_labelAutoReplyMode);
      await _preferenceService.setLabelUseFeedToTear(_labelUseFeedToTear);
      await _preferenceService.setLabelUseBackToPrint(_labelUseBackToPrint);
      await _preferenceService.setLabelUseCalibrate(_labelUseCalibrate);
      await _preferenceService.setLabelUseQrPrint(_labelUseQrPrint);
      await _preferenceService.setLabelFilterMode(_labelFilterMode);
      await _preferenceService.setLabelLayoutVersion(_labelLayoutVersion);
      await _preferenceService.setLabelQrPayloadFormat(_labelQrPayloadFormat);
      await _preferenceService.setShowKioskOrder(_isKioskOrderVisible);
      await _preferenceService.setKioskPrintAndSound(_isKioskOrderSoundEnabled);
      await _preferenceService.setShowOrderTypeBadge(_isShowOrderTypeBadge);
      await _preferenceService.setOrderSourceColor(_isOrderSourceColor);
      await _preferenceService.setOrderHistoryScroll(_isOrderHistoryScroll);
      await _preferenceService
          .setIgnoreOtherDeviceTasksKds(_isIgnoreOtherDeviceKds);
      await _preferenceService.setKdsAcceptOrders(_isKdsAcceptOrders);
      await _preferenceService.setVolume(_notificationVolume);
      await _preferenceService.setSound(_selectedSound);
      await _preferenceService.setSoundNum(_alertCount);
      await _preferenceService.setPrintCount(_printCount);
      await _preferenceService.setLocalServerEnabled(_isLocalServerEnabled);
      await _preferenceService.setSoundGraphOn(_isSoundGraphEnabled);
      await _preferenceService.setSoundGraphMarketId(_soundGraphMarketId);

      ref.read(orderHistoryScrollProvider.notifier).state =
          _isOrderHistoryScroll;
      ref.read(orderSourceColorProvider.notifier).state = _isOrderSourceColor;
    } catch (e) {
      logger.e('Error saving settings: $e');
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

  // ── 비즈니스 로직 ──────────────────────────────────────────────────────────

  Future<void> _handleModeSwitch() async {
    final isKdsMode = ref.read(kdsModeProvider);
    final title = isKdsMode
        ? t.settings.mode_switch.to_main
        : t.settings.mode_switch.to_kds;
    final content = isKdsMode
        ? t.settings.mode_switch.confirm_to_main
        : t.settings.mode_switch.confirm_to_kds;

    final bool? confirm = await CommonDialog.showConfirmDialog(
      context: context,
      title: title,
      content: content,
      confirmText: t.settings.mode_switch.btn_switch,
      cancelText: t.common.cancel,
    );

    if (confirm == true) {
      final newMode = !isKdsMode;
      await _preferenceService.setKdsMode(newMode);
      ref.read(kdsModeProvider.notifier).setKdsMode(newMode);

      if (newMode) {
        final localServer = LocalServerService.instance;
        if (localServer != null) {
          await localServer.stopServer();
          logger.i('[SettingsScreen] KDS 모드 전환: 로컬 서버 중지 완료');
        }
      }

      if (mounted) {
        // 모드 전환 후 설정 화면 유지: 홈 라우트 푸시로 스택을 날리지 않는다.
        // kdsModeProvider 변경으로 설정 화면 하단의 홈 화면은 자동으로 리빌드되며,
        // orderProvider.reloadSettings() 가 자동접수/폴링/소켓 등을 새 모드로 재구성한다.
        ref.read(orderProvider.notifier).reloadSettings();
      }
    }
  }

  Future<void> _checkUpdateFromSettings() async {
    if (!mounted) return;
    setState(() => _isCheckingUpdate = true);
    try {
      if (Platform.isWindows) {
        final winInfo = await WindowsUpdateService().checkForUpdate();
        if (mounted) {
          setState(() {
            _updateInfo = UpdateInfo(
              currentVersion: winInfo?.currentVersion ?? 0,
              latestVersion: winInfo?.latestVersion ?? 0,
              downloadUrl: winInfo?.downloadUrl ?? '',
              hasUpdate: winInfo?.hasUpdate ?? false,
            );
          });
        }
      } else {
        final otaManager = OtaUpdateManager();
        final info = await otaManager.checkForUpdate(
          versionUrl: OtaConfig.versionUrl,
          downloadUrl: OtaConfig.downloadUrl,
        );
        if (mounted) setState(() => _updateInfo = info);
      }
    } catch (_) {
      // 버전 확인 실패 — 무시
    } finally {
      if (mounted) setState(() => _isCheckingUpdate = false);
    }
  }

  Future<void> _performUpdateFromSettings() async {
    if (_updateInfo == null || !mounted) return;
    if (Platform.isWindows) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const UpdateProgressDialog(),
      );
      return;
    }
    final otaManager = OtaUpdateManager();
    await CommonDialog.showUpdateProgressDialog(
      context: context,
      updateInfo: _updateInfo!,
      onStartUpdate:
          (downloadUrl, destinationFilename, onEvent, onDone, onError) {
        otaManager.executeUpdate(
          downloadUrl: downloadUrl,
          destinationFilename: destinationFilename,
          onStatus: (status, progress) =>
              onEvent(OtaDownloadEvent(status: status, progress: progress)),
          onDone: onDone,
          onError: onError,
        );
      },
    );
  }

  Future<void> _onEnvChanged(String env) async {
    // 이전 환경 WebSocket을 먼저 해제해 configure 이후의 잔존 연결을 방지
    ref.read(authProvider.notifier).unauthenticate();

    await _preferenceService.setEnvironment(env);
    await _preferenceService.setEnvironmentManualOverride(true);

    final newEnvironment = switch (env) {
      'live' => AppFitEnvironment.live,
      'japanLive' => AppFitEnvironment.japanLive,
      'dev' => AppFitEnvironment.dev,
      'staging' => AppFitEnvironment.staging,
      _ => AppFitEnvironment.live,
    };
    AppFitConfig.configure(
        environment: newEnvironment, requestSource: 'ORDER_AGENT');

    final tokenManager = ref.read(appfit_providers.appFitTokenManagerProvider);
    await tokenManager.clearToken();
    await tokenManager.clearPassword();
    final secureStorage = SecureStorageService();
    await secureStorage.delete(SecureStorageService.appFitProjectId);
    await secureStorage.delete(SecureStorageService.appFitProjectApiKey);

    ref.invalidate(appfit_providers.appFitTokenManagerProvider);
    ref.invalidate(appfit_providers.appFitDioProvider);
    // appFitNotifierServiceProvider 는 invalidate 금지:
    // AppFitNotifierNotifier._coreService 가 `late final` 이라 build() 재실행 시
    // LateInitializationError 발생. disconnect() 만으로 이전 연결 정리 충분.

    await _preferenceService.clearLoginInfo();
    setState(() => _selectedEnv = env);

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text('환경 변경'),
          content: Text('$env 환경으로 변경되었습니다.\n로그인 화면으로 이동합니다.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                ref.read(authProvider.notifier).unauthenticate();
                Navigator.pushNamedAndRemoveUntil(
                    context, '/login', (route) => false);
              },
              child: Text(Translations.of(context).common.confirm),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _handleLocalServerChanged(bool value) async {
    setState(() => _isLocalServerEnabled = value);
    await _preferenceService.setLocalServerEnabled(value);

    final localServer = LocalServerService.instance;
    if (localServer == null) return;

    if (value) {
      try {
        final productState = ref.read(productProvider);
        if (productState.hasValue && productState.value != null) {
          await localServer.startServer(products: productState.value!);
        } else {
          await localServer.startServer();
        }
      } catch (_) {
        await localServer.startServer();
      }
      if (mounted) {
        final serverUrl = localServer.serverUrl;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('로컬 서버가 시작되었습니다.\nURL: ${serverUrl ?? "Unknown"}'),
            duration: const Duration(seconds: 4),
            backgroundColor: Colors.green,
          ),
        );
        setState(() => _isLocalServerRunning = localServer.isRunning);
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
        setState(() => _isLocalServerRunning = localServer.isRunning);
      }
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

  // ── 콜백 헬퍼 (setState + saveSettings) ──────────────────────────────────

  void _setAndSave(VoidCallback mutate) {
    setState(mutate);
    _saveSettings();
  }

  Future<void> _handleKdsAcceptOrdersChanged(bool value) async {
    if (!value) {
      _setAndSave(() => _isKdsAcceptOrders = false);
      await ref.read(orderProvider.notifier).updateKdsAcceptOrders(false);
      return;
    }

    final bool? confirm = await CommonDialog.showConfirmDialog(
      context: context,
      title: t.settings.kds_accept_orders.confirm_title,
      content: t.settings.kds_accept_orders.confirm_content,
      confirmText: t.common.confirm,
      cancelText: t.common.cancel,
    );

    if (confirm == true) {
      _setAndSave(() => _isKdsAcceptOrders = true);
      await ref.read(orderProvider.notifier).updateKdsAcceptOrders(true);
    }
  }

  // ── QR 테스트 라벨 출력 ─────────────────────────────────────────────────
  static const List<String> _qrTestSequence = [
    '10|P0001|SI0001|',
    '101|P0001|SI0001,SI0006|',
    '102|P0002|SI0001|',
    '103|P0002|SI0002|',
    '104|P0003|SI0001|',
    '105|P0003IS10002|',
    '106|P0004|S10002|',
    '107|P0004|SI0002|',
    '108|P0005|SI0002|',
    '109|P0005|SI0002|',
  ];

  bool _isQrTestRunning = false;

  Future<void> _runQrTestSequence() async {
    if (_isQrTestRunning) return;
    if (!_isUseLabelPrinter) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('라벨 프린터가 비활성화되어 있습니다.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    setState(() => _isQrTestRunning = true);
    final printService = ref.read(printServiceProvider);
    final total = _qrTestSequence.length;
    final orderTime = DateFormat('MM/dd\nHH:mm:ss').format(DateTime.now());
    int ok = 0;
    try {
      for (int i = 0; i < total; i++) {
        final qr = _qrTestSequence[i];
        final imageBytes = await LabelPainter.generateLabelImage(
          menuName: '아메리카노',
          options: const ['ICE', '샷추가'],
          shopOrderNo: qr.split('|').first,
          orderTime: orderTime,
          qrData: qr,
          memo: qr,
          orderIndex: i + 1,
          orderTotal: total,
          layoutVersion: _labelLayoutVersion,
        );
        final result = await printService.printLabel(
          imageBytes,
          orderNo: 'QRTEST',
          labelIndex: i + 1,
          totalLabels: total,
        );
        if (result) ok++;
        logToFile(
            tag: result ? LogTag.PLATFORM : LogTag.WARNING,
            message: '[QRTest] ${i + 1}/$total qr="$qr" '
                '${result ? "출력끝" : "실패"}');
      }
    } catch (e, s) {
      logger.e('[QRTest] 예외', error: e, stackTrace: s);
    } finally {
      if (mounted) {
        setState(() => _isQrTestRunning = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('QR 테스트 완료: $ok/$total 출력'),
            backgroundColor: ok == total ? Colors.green : Colors.orange,
          ),
        );
      }
    }
  }

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isKdsMode = ref.watch(kdsModeProvider);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SettingsLeftPanel(
              isKdsMode: isKdsMode,
              isRotated180: _isRotated180,
              isAutoStart: _isAutoStart,
              isIgnoreOtherDeviceKds: _isIgnoreOtherDeviceKds,
              isKdsAcceptOrders: _isKdsAcceptOrders,
              isAutoReceipt: _isAutoReceipt,
              isPrintOrder: _isPrintOrder,
              isUseBuiltinPrinter: _isUseBuiltinPrinter,
              isUseExternalPrinter: _isUseExternalPrinter,
              isUseLabelPrinter: _isUseLabelPrinter,
              isUseQrPrint: _labelUseQrPrint,
              builtinPrintOrder: _builtinPrintOrder,
              builtinPrintReceipt: _builtinPrintReceipt,
              externalPrintOrder: _externalPrintOrder,
              externalPrintReceipt: _externalPrintReceipt,
              builtinPrintCall: _builtinPrintCall,
              externalPrintCall: _externalPrintCall,
              labelFilterMode: _labelFilterMode,
              labelLayoutVersion: _labelLayoutVersion,
              labelQrPayloadFormat: _labelQrPayloadFormat,
              isShowOrderTypeBadge: _isShowOrderTypeBadge,
              isOrderSourceColor: _isOrderSourceColor,
              onModeSwitch: _handleModeSwitch,
              onRotated180Changed: (v) => setState(() => _isRotated180 = v),
              onAutoStartChanged: (v) => _setAndSave(() => _isAutoStart = v),
              onIgnoreOtherDeviceKdsChanged: (v) =>
                  _setAndSave(() => _isIgnoreOtherDeviceKds = v),
              onKdsAcceptOrdersChanged: _handleKdsAcceptOrdersChanged,
              onAutoReceiptChanged: (v) =>
                  _setAndSave(() => _isAutoReceipt = v),
              onPrintOrderChanged: (v) => _setAndSave(() {
                _isPrintOrder = v;
                if (!v) {
                  _isUseBuiltinPrinter = false;
                  _isUseExternalPrinter = false;
                } else {
                  if (!_isUseBuiltinPrinter && !_isUseExternalPrinter) {
                    _isUseBuiltinPrinter = true;
                  }
                }
              }),
              onUseBuiltinPrinterChanged: (v) =>
                  _setAndSave(() => _isUseBuiltinPrinter = v),
              onUseExternalPrinterChanged: (v) =>
                  _setAndSave(() => _isUseExternalPrinter = v),
              onUseLabelPrinterChanged: (v) =>
                  _setAndSave(() => _isUseLabelPrinter = v),
              onUseQrPrintChanged: (v) =>
                  _setAndSave(() => _labelUseQrPrint = v),
              onBuiltinPrintOrderChanged: (v) =>
                  _setAndSave(() => _builtinPrintOrder = v),
              onBuiltinPrintReceiptChanged: (v) =>
                  _setAndSave(() => _builtinPrintReceipt = v),
              onExternalPrintOrderChanged: (v) =>
                  _setAndSave(() => _externalPrintOrder = v),
              onExternalPrintReceiptChanged: (v) =>
                  _setAndSave(() => _externalPrintReceipt = v),
              onBuiltinPrintCallChanged: (v) =>
                  _setAndSave(() => _builtinPrintCall = v),
              onExternalPrintCallChanged: (v) =>
                  _setAndSave(() => _externalPrintCall = v),
              onLabelFilterModeChanged: (v) =>
                  _setAndSave(() => _labelFilterMode = v),
              onLabelLayoutVersionChanged: (v) =>
                  _setAndSave(() => _labelLayoutVersion = v),
              onLabelQrPayloadFormatChanged: (v) =>
                  _setAndSave(() => _labelQrPayloadFormat = v),
              onShowOrderTypeBadgeChanged: (v) =>
                  _setAndSave(() => _isShowOrderTypeBadge = v),
              onOrderSourceColorChanged: (v) =>
                  _setAndSave(() => _isOrderSourceColor = v),
              isSoundGraphEnabled: _isSoundGraphEnabled,
              soundGraphMarketId: _soundGraphMarketId,
              onSoundGraphEnabledChanged: (v) =>
                  _setAndSave(() => _isSoundGraphEnabled = v),
              onSoundGraphMarketIdChanged: (v) =>
                  _setAndSave(() => _soundGraphMarketId = v),
            ),
          ),
          const SizedBox(width: AppSpacing.s16),
          Expanded(
            child: SettingsRightPanel(
              isKdsMode: isKdsMode,
              notificationVolume: _notificationVolume,
              selectedSound: _selectedSound,
              alertCount: _alertCount,
              isKioskOrderVisible: _isKioskOrderVisible,
              isKioskOrderSoundEnabled: _isKioskOrderSoundEnabled,
              isLocalServerEnabled: _isLocalServerEnabled,
              isLocalServerRunning: _isLocalServerRunning,
              printCount: _printCount,
              isAutoCheckUpdate: _isAutoCheckUpdate,
              isCheckingUpdate: _isCheckingUpdate,
              updateInfo: _updateInfo,
              isDevOptionsVisible: _isDevOptionsVisible,
              devOptionsTapCount: _devOptionsTapCount,
              forceSocketReconnect: _forceSocketReconnect,
              selectedEnv: _selectedEnv,
              labelAutoReplyMode: _labelAutoReplyMode,
              labelUseFeedToTear: _labelUseFeedToTear,
              labelUseBackToPrint: _labelUseBackToPrint,
              labelUseCalibrate: _labelUseCalibrate,
              onVolumeChanged: (v) => setState(() => _notificationVolume = v),
              onVolumeChangeEnd: (_) => _saveSettings(),
              onSoundChanged: (v) => _setAndSave(() => _selectedSound = v),
              onAlertCountChanged: (v) => _setAndSave(() => _alertCount = v),
              onKioskOrderVisibleChanged: (v) => _setAndSave(() {
                _isKioskOrderVisible = v;
                if (!v) _isKioskOrderSoundEnabled = false;
              }),
              onKioskOrderSoundChanged: (v) =>
                  _setAndSave(() => _isKioskOrderSoundEnabled = v),
              onLocalServerChanged: _handleLocalServerChanged,
              onPrintCountChanged: (v) => _setAndSave(() => _printCount = v),
              onAutoCheckUpdateChanged: (v) {
                setState(() => _isAutoCheckUpdate = v);
                _preferenceService.setAutoCheckUpdate(v);
              },
              onCheckUpdate: _checkUpdateFromSettings,
              onPerformUpdate: _performUpdateFromSettings,
              onDevOptionsTap: () {
                if (!AppEnv.showInternalUi) return; // 릴리즈에선 진입 불가
                setState(() {
                  _devOptionsTapCount++;
                  if (_devOptionsTapCount >= 5) {
                    _isDevOptionsVisible = true;
                    _devOptionsTapCount = 0;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('개발자 옵션이 활성화되었습니다.'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                });
              },
              onForceSocketReconnectChanged: (v) {
                setState(() => _forceSocketReconnect = v);
                _preferenceService.setForceSocketReconnect(v);
                ref.read(orderProvider.notifier).updateEmergencyPoll(v);
                logToFile(tag: LogTag.UI_ACTION, message: '긴급모드 변경 -> $v');
              },
              onEnvChanged: _onEnvChanged,
              onAutoReplyModeChanged: (v) =>
                  _setAndSave(() => _labelAutoReplyMode = v),
              onFeedToTearChanged: (v) =>
                  _setAndSave(() => _labelUseFeedToTear = v),
              onBackToPrintChanged: (v) =>
                  _setAndSave(() => _labelUseBackToPrint = v),
              onCalibrateChanged: (v) =>
                  _setAndSave(() => _labelUseCalibrate = v),
              isParanmanjanTestRunning: _isQrTestRunning,
              onParanmanjanTest: _runQrTestSequence,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}
