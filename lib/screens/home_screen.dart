import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:appfit_order_agent/screens/membership_screen.dart';
import 'package:appfit_order_agent/services/preference_service.dart';
import 'package:appfit_order_agent/utils/logger.dart';
import 'package:appfit_order_agent/i18n/strings.g.dart';
import 'package:appfit_order_agent/constants/app_styles.dart';
import 'package:appfit_order_agent/providers/product_provider.dart';
import 'package:appfit_order_agent/providers/providers.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async'; // StreamSubscription 사용 위해 추가
import 'dart:io'; // Platform 사용 위해 추가
import 'package:appfit_order_agent/services/local_server_service.dart';
import 'package:appfit_order_agent/services/platform_service.dart';
import 'package:appfit_order_agent/services/platform_bridge_service.dart'; // PlatformBridgeService 사용 위해 추가

import 'package:appfit_order_agent/services/overlay_service.dart';

import 'package:appfit_order_agent/widgets/home/app_bar_widget.dart';
import 'package:appfit_order_agent/widgets/home/tab_button_widget.dart';
import 'package:appfit_order_agent/screens/order_history_screen.dart';
import 'package:appfit_order_agent/screens/order_status_screen.dart';
import 'package:appfit_order_agent/screens/product_management_screen.dart';
import 'package:appfit_order_agent/widgets/home/drawer_menu.dart';
import 'package:appfit_order_agent/screens/settings_screen.dart';
import 'package:appfit_order_agent/widgets/common/common_dialog.dart';
import 'package:appfit_order_agent/widgets/common/fault_injection_ribbon.dart';
import 'package:appfit_order_agent/widgets/common/brand_install_banner.dart';
import 'package:appfit_order_agent/widgets/common/sync_status_banner.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:appfit_order_agent/services/monitoring/monitoring_sync_provider.dart';
import 'package:appfit_order_agent/screens/kds_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isOnline = true;
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  int _currentIndex = 0;
  StreamSubscription<List<ConnectivityResult>>?
      _connectivitySubscription; // 구독 변수 추가

  // 인터넷 연결 상태 관련 변수 추가
  DateTime? _lastDialogShownTime;
  Timer? _connectionCheckTimer;
  static const int _connectionCheckDelay = 3; // 연결 끊김 확인 지연시간(초)
  static const int _minDialogInterval = 30; // 다이얼로그 표시 최소 간격(초)

  // 알림음 관련 변수
  final AudioPlayer _audioPlayer = AudioPlayer();
  late PreferenceService _preferenceService;
  String _notificationSound = 'alert10.mp3';
  double _volume = 0.5;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);

    // 알림음 설정 로드
    _loadSoundSettings();

    _setupConnectivity();

    // 위젯 트리가 완전히 빌드된 후에 초기 데이터 로드
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadInitialData();
    });
  }

  Future<void> _loadInitialData() async {
    // 앱 실행 시 저장된 오더 토글값으로 서버 영업 상태 복원
    await _syncStoreStatusFromSavedToggle();

    try {
      // ProductProvider의 build() 메서드가 자동으로 상품을 로드함
      // 상품 로딩 완료를 기다림
      final productState = await ref.read(productProvider.future);
      logger.i('[HomeScreen] 상품 로딩 완료: ${productState.length}개');

      // KDS 모드가 아닐 때만 로컬 서버 처리
      final isKdsMode = ref.read(kdsModeProvider);
      if (!isKdsMode) {
        // LocalServerService 인스턴스 생성 (설정과 관계없이)
        final localServer = LocalServerService(ref);

        // 설정에 따라 서버 시작
        final preferenceService = ref.read(preferenceServiceProvider);
        final isServerEnabled = preferenceService.getLocalServerEnabled();

        if (isServerEnabled) {
          await localServer.startServer(products: productState);
          logger.i('[HomeScreen] 로컬 서버 시작 완료 (설정: 활성화)');
        } else {
          logger.i('[HomeScreen] 로컬 서버 인스턴스 생성 (설정: 비활성화)');
        }
      } else {
        logger.i('[HomeScreen] KDS 모드: 로컬 서버 시작 안함');
      }

      // 설정 재로드 확인
      logger.i('[HomeScreen] 초기 데이터 로드 후 설정 상태 확인');
      final orderState = ref.read(orderProvider);
      logger.i('[HomeScreen] 현재 자동접수 설정: ${orderState.isAutoReceipt}');

      // 초기화 완료 후 주문 목록 새로고침 (중복 호출 방지)
      logger.i('[initializeAsync] 4. 초기화 완료 후 주문 목록 새로고침');
      // _detectAndInitializeByInstallType에서 이미 refreshOrders를 호출하므로 중복 호출 방지
      // ref.read(orderProvider.notifier).refreshOrders();
    } catch (e, s) {
      logger.e('초기 데이터 로드 중 오류 발생', error: e, stackTrace: s);
    }
  }

  /// 앱 실행 시 로컬에 저장된 오더 토글값(KEY_ORDER_ON)으로 서버 영업 상태를 복원한다.
  /// 종료/로그아웃 시 매장을 CLOSED(오더 준비중)로 내리므로, 재실행 때 마지막으로
  /// 설정한 토글값(영업중이면 true)대로 서버 상태를 되돌린다.
  /// setIsOpen 내부에서 KDS+자동접수 OFF 시 생략 / 실패 시 롤백을 처리한다.
  Future<void> _syncStoreStatusFromSavedToggle() async {
    try {
      final savedOrderOn = ref.read(preferenceServiceProvider).getOrderOn();
      await ref.read(storeProvider.notifier).setIsOpen(savedOrderOn);
      logger.i('[HomeScreen] 앱 실행: 저장된 오더 토글($savedOrderOn)로 영업 상태 동기화');
    } catch (e, s) {
      logger.w('[HomeScreen] 오더 토글 동기화 실패(무시)', error: e, stackTrace: s);
    }
  }

  void _setupConnectivity() {
    // 구독 결과를 변수에 저장
    _connectivitySubscription = Connectivity()
        .onConnectivityChanged
        .listen((List<ConnectivityResult> results) {
      final bool newIsOnline =
          results.isNotEmpty && !results.contains(ConnectivityResult.none);

      // 현재 연결 타입 로깅
      String connectionTypes =
          results.map((result) => result.name).join(', '); // 예: "wifi, mobile"
      logToFile(
          tag: LogTag.SYSTEM,
          message:
              'Internet connection changed. Online: $newIsOnline, Types: [$connectionTypes]');

      // 오프라인 상태로 변경됨
      if (_isOnline && !newIsOnline) {
        _handleConnectionLost();
      }

      // 온라인 상태로 복구됨
      if (!_isOnline && newIsOnline) {
        _handleConnectionRestored();
      }

      setState(() {
        _isOnline = newIsOnline;
      });
    });
  }

  // 연결이 끊겼을 때 처리
  void _handleConnectionLost() {
    // 이미 타이머가 실행 중이면 취소하고 새로 시작
    _connectionCheckTimer?.cancel();

    // 연결이 일정 시간 이상 끊어져 있는지 확인하는 타이머 시작
    _connectionCheckTimer = Timer(Duration(seconds: _connectionCheckDelay), () {
      // 연결이 계속 끊어져 있으면 다이얼로그 표시
      if (!_isOnline) {
        _showConnectionLostDialog();
      }
    });
  }

  // 연결이 복구되었을 때 처리
  void _handleConnectionRestored() {
    _connectionCheckTimer?.cancel();

    // 예전에는 "소켓 재연결이 알아서 refreshOrders 를 부른다"고 보고 아무것도
    // 하지 않았다. 2026-08-07 장애가 그 전제를 반증했다 — 소켓이 애초에 끊기지
    // 않으면(끊김 감지에 14분이 걸렸다) 재연결 핸들러도 영영 돌지 않는다.
    // 복구 신호가 있을 때는 그 자리에서 재동기화한다. 중복은 내부 가드가 흡수.
    if (mounted) {
      logToFile(tag: LogTag.SYSTEM, message: '인터넷 연결 복구 감지 → 즉시 재동기화');
      ref.read(orderProvider.notifier).refreshOrders();
    }
  }

  // 알림음 설정 로드
  Future<void> _loadSoundSettings() async {
    _preferenceService = ref.read(preferenceServiceProvider);
    _notificationSound = _preferenceService.getSound();
    final volumeValue = _preferenceService.getVolume();
    _volume = volumeValue / 10.0;
    await _audioPlayer.setVolume(_volume);
    logger.d('알림음 설정 로드: 파일=$_notificationSound, 볼륨=$_volume');
  }

  // 알림음 재생
  Future<void> _playNotificationSound() async {
    try {
      await _audioPlayer.stop(); // 이미 재생 중인 소리 중지
      await _audioPlayer.play(AssetSource('sounds/$_notificationSound'));
      logToFile(
          tag: LogTag.SYSTEM, message: '인터넷 연결 끊김 알림음 재생: $_notificationSound');
    } catch (e, s) {
      logger.e('알림음 재생 중 오류 발생', error: e, stackTrace: s);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _connectivitySubscription?.cancel();
    _connectionCheckTimer?.cancel();
    // Sentry APPFIT-ORDER-AGENT-N: 이미 dispose 된 플레이어에 다시 dispose 가
    // 호출되면 IllegalStateException 이 발생하므로 안전하게 감싼다.
    try {
      _audioPlayer.dispose();
    } catch (e) {
      logger.w('[HomeScreen] AudioPlayer dispose 중 예외 무시: $e');
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 매장 정보 로드 시 Sentry 컨텍스트 업데이트
    ref.watch(monitoringSyncProvider);

    ref.listen<AppLifecycleState>(appLifecycleObserverProvider,
        (previous, next) async {
      logger.d('HomeScreen: AppLifecycleState changed from $previous to $next');

      if (next == AppLifecycleState.resumed) {
        logger.i('HomeScreen: App resumed, hiding overlay bubble.');
        if (Platform.isAndroid) {
          PlatformBridgeService().hideOverlay();
        }
      } else if (next == AppLifecycleState.paused) {
        // 시스템 버튼(홈, 멀티태스킹)으로 백그라운드 이동 시 오버레이 트리거
        // Android 7 및 구버전에서의 중복 호출 및 오류 메시지 최소화를 위해 paused 상태만 감지
        if (Platform.isAndroid) {
          final isOverlayActive =
              await PlatformBridgeService().isOverlayActive();
          if (!isOverlayActive) {
            logger.i('HomeScreen: App paused, showing overlay bubble');
            await PlatformBridgeService().showOverlay();
          }
        }
      }
    });

    return Scaffold(
      key: _scaffoldKey,
      resizeToAvoidBottomInset: false,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: HomeAppBarWidget(
          isOnline: _isOnline,
          onLogout: _exitApp,
          onMinimize: _handleMinimize,
          scaffoldKey: _scaffoldKey,
          isSettingsScreen: _currentIndex == 1 || _currentIndex == 2,
          onBackPressed: () {
            setState(() {
              _currentIndex = 0;
            });
          },
          onReconnect: _handleManualReconnect,
        ),
      ),
      drawer: DrawerMenu(
        currentIndex: _currentIndex,
        onItemSelected: _onDrawerItemSelected,
      ),
      body: ColoredBox(
        color: AppStyles.gray1,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (Widget child, Animation<double> animation) {
                  final bool slidesFromRight = child.key == const ValueKey(1) ||
                      child.key == const ValueKey(2);
                  final offsetAnimation = Tween<Offset>(
                    begin: Offset(slidesFromRight ? 1.0 : -1.0, 0.0),
                    end: Offset.zero,
                  ).animate(animation);

                  return SlideTransition(
                    position: offsetAnimation,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: child,
                    ),
                  );
                },
                child: _currentIndex == 0
                    ? const HomeContent(key: ValueKey(0))
                    : _currentIndex == 1
                        ? const SettingsScreen(key: ValueKey(1))
                        : const ProductManagementScreen(key: ValueKey(2)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exitApp() async {
    // 종료 직전 매장을 CLOSED(오더 준비중)로 전환. cleanup/disconnect 이전에 실행하여
    // 소켓/Dio 가 살아있는 동안 전송 완료를 최대한 보장한다. 실패해도 종료는 계속 진행.
    try {
      final storeId = ref.read(storeProvider).value?.storeId ?? '';
      final isKdsMode = ref.read(kdsModeProvider);
      final isKdsAcceptOrders = ref.read(orderProvider).isKdsAcceptOrders;
      if ((!isKdsMode || isKdsAcceptOrders) && storeId.isNotEmpty) {
        await ref
            .read(apiServiceProvider)
            .updateShopOperatingStatus(storeId, false);
        logger.i('[HomeScreen] 앱 종료: 매장 CLOSED(오더 준비중) 전환 완료');
      }
    } catch (e, s) {
      logger.w('[HomeScreen] 앱 종료 시 매장 CLOSED 전환 실패(무시)',
          error: e, stackTrace: s);
    }

    try {
      final socketNotifier = ref.read(appFitNotifierServiceProvider.notifier);

      // 순서 중요: 먼저 앱 전역 정리(OrderProvider/소켓/리스너/타이머/사운드/blink)
      ref.read(orderProvider.notifier).cleanupOnLogout();
      socketNotifier.disconnect();

      // 로컬 서버 중지
      final localServer = LocalServerService.instance;
      if (localServer != null) {
        await localServer.stopServer();
        logger.i('[HomeScreen] 앱 종료: 로컬 서버 중지 완료');
      }

      // ServerConfig usages removed

      logger.i('앱 종료 전 모든 연결 정리 완료');
    } catch (e, s) {
      logger.e('Error during app exit', error: e, stackTrace: s);
    }

    // 앱 종료 (Dart 구현 사용)
    try {
      // 1. 오버레이 숨기기 (Flutter Overlay Window)
      await OverlayService().hide();
    } catch (e, s) {
      logger.w('Error hiding overlay during exit', error: e, stackTrace: s);
    }

    // KDS 모드 초기화
    ref.read(kdsModeProvider.notifier).setKdsMode(false);

    // 2. 앱 종료 (플랫폼별 분기는 PlatformService.exitApp() 가 담당)
    await PlatformService.exitApp();
  }

  Future<void> _handleLogout() async {
    // 로그아웃 시 매장이 CLOSED(오더 준비중)로 전환되는 조건(메인모드 or KDS+자동접수ON)이면
    // 확인 다이얼로그에 "오더 준비중으로 변경됩니다" 안내를 조합해 노출한다.
    final isKdsMode = ref.read(kdsModeProvider);
    final isKdsAcceptOrders = ref.read(orderProvider).isKdsAcceptOrders;
    final willClose = !isKdsMode || isKdsAcceptOrders;

    final shouldLogout = await CommonDialog.showConfirmDialog(
      context: context,
      title: t.drawer.logout,
      content: willClose
          ? '${t.home.logout_confirm}\n${t.app_bar.store_closed_notice}'
          : t.home.logout_confirm,
      cancelText: t.common.cancel,
      confirmText: t.drawer.logout,
    );

    if (shouldLogout == null || !shouldLogout) return;

    try {
      final apiService = ref.read(apiServiceProvider);
      final socketNotifier = ref.read(appFitNotifierServiceProvider.notifier);
      final storeId = ref.read(storeProvider).value?.storeId ?? '';
      // Provider 의존성 전파 타이밍 이슈 방지: 정리는 UI 계층에서 우선 수행

      // 메인모드이거나 (KDS + 자동접수 ON) 이면 매장을 CLOSED(오더 준비중)로 전환.
      if (willClose && storeId.isNotEmpty) {
        await apiService.updateShopOperatingStatus(storeId, false);
      }

      socketNotifier.disconnect();
      // blink/신규건수 초기화 보장
      ref.read(blinkStateProvider.notifier).updateActiveOrderCount(0);
      ref.read(blinkStateProvider.notifier).stopBlinking();

      // 로컬 서버 중지
      final localServer = LocalServerService.instance;
      if (localServer != null) {
        await localServer.stopServer();
        logger.i('[HomeScreen] 로그아웃: 로컬 서버 중지 완료');
      }

      // credentials/JWT/소켓 cleanup은 Auth.logout() 단일 진입점에 위임
      await ref.read(authProvider.notifier).logout();

      // KDS 모드일 때는 별도 정리 불필요 (dispose에서 자동 처리됨)

      // KDS 모드 초기화
      ref.read(kdsModeProvider.notifier).setKdsMode(false);
      // orderProvider 정리 (ServerConfig.reset() 전에 실행)
      logger.i('[HomeScreen] 로그아웃 시 OrderProvider 정리 시작');
      ref.read(orderProvider.notifier).cleanupOnLogout();
      logger.i('[HomeScreen] 로그아웃 시 OrderProvider 정리 완료 - 모든 주문 데이터 초기화됨');

      // 매장 스코프 keepAlive 프로바이더 초기화 — 이전 매장의 카탈로그/주문내역/조회
      // 날짜가 다음 로그인까지 잔존하는 것을 방지(정본은 resetStoreScopedProviders).
      resetStoreScopedProviders(ref);
      // ServerConfig usages removed

      logger.i('로그아웃 시 모든 연결 정리 완료');

      if (mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
    } catch (e, s) {
      logger.e('Logout error', error: e, stackTrace: s);
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
    }
  }

  Future<void> _handleManualReconnect() async {
    await ref.read(authProvider.notifier).reconnect();
  }

  void _handleMinimize() async {
    try {
      logger.d('최소화 버튼 클릭됨');

      logToFile(tag: LogTag.UI_ACTION, message: '최소화 버튼 터치');

      final hasPermission = await PlatformService.checkOverlayPermission();

      if (!hasPermission) {
        if (mounted) {
          final shouldRequestPermission = await CommonDialog.showConfirmDialog(
            context: context,
            title: t.login.overlay_permission.title,
            content: t.login.overlay_permission.content,
            confirmText: t.login.overlay_permission.set,
            cancelText: t.common.cancel,
          );

          if (shouldRequestPermission == null || !shouldRequestPermission) {
            return;
          }
          await PlatformService.requestOverlayPermission();
          return;
        }
        return;
      }

      logToFile(tag: LogTag.UI_ACTION, message: 'Moving app to background');
      await PlatformService.moveToBackground();
    } catch (e, s) {
      logger.e('최소화 오류', error: e, stackTrace: s);

      if (mounted) {
        CommonDialog.showConfirmDialog(
          context: context,
          title: t.common.error_title,
          content: t.home.minimize_error,
          confirmText: t.common.confirm,
          cancelText: '',
        );
      }
    }
  }

  Future<void> _onDrawerItemSelected(int index) async {
    if (index == -1) {
      await _handleLogout();
    } else if (index == 2) {
      setState(() => _currentIndex = 2);
      _scaffoldKey.currentState?.closeDrawer();
    } else {
      setState(() {
        _currentIndex = index;
      });
      _scaffoldKey.currentState?.closeDrawer();
    }
  }

  void _showConnectionLostDialog() {
    // 위젯이 사라졌거나 이미 온라인 복구됐으면 표시하지 않는다.
    if (!mounted || _isOnline) return;

    // 직전 표시 후 최소 간격 이내면 과도한 반복 알림을 막기 위해 스킵.
    final now = DateTime.now();
    if (_lastDialogShownTime != null &&
        now.difference(_lastDialogShownTime!).inSeconds < _minDialogInterval) {
      return;
    }

    _lastDialogShownTime = now;
    _playNotificationSound();
    logToFile(tag: LogTag.SYSTEM, message: '인터넷 연결 오류 다이얼로그 표시');

    // 동일 다이얼로그가 이미 떠 있으면 CommonDialog 의 dedupe 가드가 중복 표시를 차단한다.
    // (인터넷 flapping 시 다이얼로그가 화면에 쌓이는 문제 방지)
    CommonDialog.showInfoDialog(
      context: context,
      title: t.login.internet_error_title,
      content: t.login.internet_error_msg,
      dedupeKey: 'internet_connection_error',
    );
  }
}

class HomeContent extends ConsumerWidget {
  const HomeContent({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedIndex = ref.watch(homeTabIndexProvider);
    final isKdsMode = ref.watch(kdsModeProvider);

    logger.d(
        'HomeContent build triggered. SelectedIndex: $selectedIndex, KDS Mode: $isKdsMode');

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: isKdsMode
          ? const KdsScreen(key: ValueKey('kds'))
          : _buildNormalMode(selectedIndex, ref),
    );
  }

  Widget _buildNormalMode(int selectedIndex, WidgetRef ref) {
    return Column(
      key: const ValueKey('normal'),
      children: [
        // 장애 주입 무장 리본 (개발 전용, 비무장 시 높이 0)
        const FaultInjectionRibbon(),
        // 서버 응답 지연 배너 — KDS 모드와 같은 위젯을 쓴다. 장애는 모드를
        // 가리지 않고, 두 모드 모두 같은 HTTP 파이프라인 위에서 돈다.
        const SyncStatusBanner(),
        // 설치된 앱과 매장 브랜드가 어긋났을 때만 뜬다(정상은 높이 0). 사람이
        // 앱을 교체해야 사라지는 조건이라 위쪽 배너들과 함께 상시 노출한다.
        const BrandInstallBanner(),
        Expanded(child: _buildNormalBody(selectedIndex, ref)),
      ],
    );
  }

  Widget _buildNormalBody(int selectedIndex, WidgetRef ref) {
    return Row(
      children: [
        Container(
          width: 120,
          decoration: const BoxDecoration(
            border: Border(
              right: BorderSide(color: AppStyles.gray3),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Expanded(
                child: TabButtonWidget(
                    label: t.home.tabs.order_status,
                    icon: Icons.dashboard,
                    isSelected: selectedIndex == 0,
                    onTap: () {
                      ref.read(homeTabIndexProvider.notifier).state = 0;
                      logToFile(tag: LogTag.UI_ACTION, message: '주문현황 탭 선택');
                    }),
              ),
              Expanded(
                child: TabButtonWidget(
                    label: t.home.tabs.order_history,
                    icon: Icons.history,
                    isSelected: selectedIndex == 1,
                    onTap: () {
                      ref.read(homeTabIndexProvider.notifier).state = 1;
                      logToFile(tag: LogTag.UI_ACTION, message: '주문내역 탭 선택');
                    }),
              ),
              Expanded(
                child: TabButtonWidget(
                    label: t.home.tabs.product_management,
                    icon: Icons.inventory,
                    isSelected: selectedIndex == 2,
                    onTap: () {
                      ref.read(homeTabIndexProvider.notifier).state = 2;
                      logToFile(tag: LogTag.UI_ACTION, message: '상품관리 탭 선택');
                    }),
              ),
              Expanded(
                child: TabButtonWidget(
                    label: t.home.tabs.membership,
                    icon: Icons.people,
                    isSelected: selectedIndex == 3,
                    onTap: () {
                      ref.read(homeTabIndexProvider.notifier).state = 3;
                      logToFile(tag: LogTag.UI_ACTION, message: '멤버십 탭 선택');
                    }),
              ),
            ],
          ),
        ),
        Expanded(
          child: _buildContent(selectedIndex),
        ),
      ],
    );
  }

  Widget _buildContent(int selectedIndex) {
    switch (selectedIndex) {
      case 0:
        return _buildOrderStatusTab();
      case 1:
        return _buildOrderHistoryTab();
      case 2:
        return _buildProductManagementTab();
      case 3:
        return _buildMembershipTab();
      default:
        return Center(child: Text(t.home.invalid_tab));
    }
  }

  Widget _buildOrderStatusTab() {
    return const OrderStatusScreen();
  }

  Widget _buildOrderHistoryTab() {
    return const OrderHistoryScreen();
  }

  Widget _buildProductManagementTab() {
    return const ProductManagementScreen();
  }

  Widget _buildMembershipTab() {
    return const MembershipScreen();
  }
}
