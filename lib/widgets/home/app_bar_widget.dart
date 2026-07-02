import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:window_manager/window_manager.dart';
import 'package:appfit_order_agent/providers/providers.dart';
import 'package:appfit_order_agent/utils/logger.dart';
import 'package:appfit_order_agent/constants/app_styles.dart';
import 'package:appfit_order_agent/services/platform_service.dart';
import 'package:appfit_order_agent/services/windows_bubble_service.dart';
import 'package:appfit_order_agent/widgets/custom_switch.dart';
import 'package:appfit_order_agent/widgets/common/common_dialog.dart';
import 'package:appfit_order_agent/widgets/common/app_icon_action.dart';
import 'package:appfit_order_agent/widgets/common/app_loading_indicator.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:appfit_order_agent/dev/socket_burst_test.dart'
    as test_util; // [TEST]
import 'package:appfit_order_agent/i18n/strings.g.dart';
import 'package:appfit_order_agent/providers/locale_provider.dart';
import 'package:appfit_core/appfit_core.dart' as appfit_core;

// === New StatefulWidget for Time Display ===
class _CurrentTimeWidget extends ConsumerStatefulWidget {
  const _CurrentTimeWidget({Key? key}) : super(key: key);

  @override
  _CurrentTimeWidgetState createState() => _CurrentTimeWidgetState();
}

class _CurrentTimeWidgetState extends ConsumerState<_CurrentTimeWidget> {
  Timer? _timer;
  String _currentTime = '';
  // DateFormat 생성은 저사양 CPU 에서 매초 반복하기엔 아까운 비용 — 로캘 단위로 캐시.
  DateFormat? _dateFormat;
  AppLocale? _formatLocale;

  @override
  void initState() {
    super.initState();
    _currentTime = t.app_bar.time_loading;

    // 현재 로캘 정보 가져오기
    final locale = ref.read(localeNotifierProvider);
    final localeStr = _getLocaleString(locale);

    // 해당 로캘의 날짜 포맷팅 초기화
    initializeDateFormatting(localeStr, null).then((_) {
      if (mounted) {
        _updateTime();
      }
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted) {
          _updateTime();
        }
      });
    }).catchError((error) {
      logger.e("Error initializing date formatting: $error");
      if (mounted) {
        setState(() {
          _currentTime = t.app_bar.time_error;
        });
      }
    });
  }

  String _getLocaleString(AppLocale locale) {
    if (locale == AppLocale.ja) return 'ja_JP';
    if (locale == AppLocale.en) return 'en_US';
    return 'ko_KR';
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _updateTime() {
    final locale = ref.read(localeNotifierProvider);
    // 로캘이 바뀐 경우에만 DateFormat 재생성 (설정에서 언어 변경 시 다음 틱에 반영)
    if (_dateFormat == null || locale != _formatLocale) {
      _formatLocale = locale;
      _dateFormat = DateFormat('MM.dd(E) a hh:mm', _getLocaleString(locale));
    }

    var formatted = _dateFormat!.format(DateTime.now());
    // 일본어와 한국어의 경우 오전/오후 명시적 변환 (포맷에 따라 다를 수 있음)
    if (locale == AppLocale.ko || locale == AppLocale.ja) {
      formatted = formatted
          .replaceAll('AM', t.app_bar.morning)
          .replaceAll('PM', t.app_bar.afternoon);
    }

    setState(() {
      _currentTime = formatted;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _currentTime,
      style: const TextStyle(
        fontSize: AppStyles.kAppBarTimeSize,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
      ),
    );
  }
}
// === End of _CurrentTimeWidget ===

class HomeAppBarWidget extends ConsumerStatefulWidget {
  final bool isOnline;
  final VoidCallback onLogout;
  final VoidCallback onMinimize;
  final GlobalKey<ScaffoldState> scaffoldKey;
  final bool isSettingsScreen;
  final VoidCallback? onBackPressed;
  final VoidCallback? onReconnect;

  const HomeAppBarWidget({
    Key? key,
    required this.isOnline,
    required this.onLogout,
    required this.onMinimize,
    required this.scaffoldKey,
    this.isSettingsScreen = false,
    this.onBackPressed,
    this.onReconnect,
  }) : super(key: key);

  @override
  ConsumerState<HomeAppBarWidget> createState() => _HomeAppBarWidgetState();
}

class _HomeAppBarWidgetState extends ConsumerState<HomeAppBarWidget> {
  // 네트워크 타입을 저장할 변수 추가 (최신 API는 리스트로 반환)
  List<ConnectivityResult> _connectionTypes = [];
  StreamSubscription? _connectivitySubscription;
  bool _isRefreshing = false; // 새로고침 중복 방지 플래그 추가
  bool _isExiting = false; // 앱 종료 진행 상태 플래그 추가

  @override
  void initState() {
    super.initState();

    // 초기 네트워크 상태 확인
    _initConnectivity();

    // 네트워크 상태 변화 감지를 위한 스트림 구독
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen(_updateConnectionStatus);
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  // 초기 연결 상태 확인
  Future<void> _initConnectivity() async {
    try {
      final result = await Connectivity().checkConnectivity();
      if (mounted) {
        setState(() {
          _connectionTypes = result;
        });
      }
    } catch (e, s) {
      logger.e('네트워크 상태 확인 중 오류 발생', error: e, stackTrace: s);
    }
  }

  // 연결 상태 업데이트
  void _updateConnectionStatus(List<ConnectivityResult> results) {
    if (mounted) {
      setState(() {
        _connectionTypes = results;
      });
    }
  }

  // 우선순위가 높은 네트워크 타입 가져오기
  ConnectivityResult _getPrimaryConnectionType() {
    // 네트워크 연결 없음
    if (_connectionTypes.isEmpty) {
      return ConnectivityResult.none;
    }

    // 연결 우선순위: 이더넷 > 와이파이 > 셀룰러 > VPN > 블루투스 > 기타
    if (_connectionTypes.contains(ConnectivityResult.ethernet)) {
      return ConnectivityResult.ethernet;
    } else if (_connectionTypes.contains(ConnectivityResult.wifi)) {
      return ConnectivityResult.wifi;
    } else if (_connectionTypes.contains(ConnectivityResult.mobile)) {
      return ConnectivityResult.mobile;
    } else if (_connectionTypes.contains(ConnectivityResult.vpn)) {
      return ConnectivityResult.vpn;
    } else if (_connectionTypes.contains(ConnectivityResult.bluetooth)) {
      return ConnectivityResult.bluetooth;
    } else {
      return _connectionTypes.first; // 첫 번째 연결 타입 반환
    }
  }

  // 네트워크 타입에 따른 아이콘 가져오기
  IconData _getNetworkIcon() {
    if (!widget.isOnline) {
      return Icons.signal_wifi_off; // 오프라인일 경우
    }

    ConnectivityResult primaryConnection = _getPrimaryConnectionType();

    switch (primaryConnection) {
      case ConnectivityResult.wifi:
        return Icons.wifi; // 와이파이 연결
      case ConnectivityResult.ethernet:
        return Icons.lan; // 이더넷 연결
      case ConnectivityResult.mobile:
        return Icons.signal_cellular_4_bar; // 셀룰러 연결
      case ConnectivityResult.vpn:
        return Icons.vpn_key; // VPN 연결
      case ConnectivityResult.bluetooth:
        return Icons.bluetooth; // 블루투스 연결
      case ConnectivityResult.none:
        return Icons.signal_wifi_off; // 연결 없음
      default:
        return Icons.network_check; // 기타/알 수 없음
    }
  }

  // 네트워크 타입에 따른 아이콘 색상 가져오기
  Color _getNetworkIconColor() {
    if (!widget.isOnline ||
        _getPrimaryConnectionType() == ConnectivityResult.none) {
      return Colors.red; // 오프라인일 경우
    }
    return Colors.green; // 온라인일 경우
  }

  // 새로고침 버튼 클릭 핸들러 분리
  void _handleRefresh() {
    if (_isRefreshing) return; // 이미 새로고침 중이면 무시

    setState(() {
      _isRefreshing = true;
    });

    ref.read(orderProvider.notifier).refreshOrders();
    logToFile(tag: LogTag.UI_ACTION, message: '새로고침버튼 터치');

    // 1.5초 후에 다시 새로고침 가능하도록 설정
    Future.delayed(const Duration(milliseconds: 3000), () {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isKdsMode = ref.watch(kdsModeProvider);
    final appBar = AppBar(
      elevation: 0,
      scrolledUnderElevation: 0,
      leading: IconButton(
        icon: Icon(widget.isSettingsScreen ? Icons.arrow_back : Icons.menu),
        onPressed: widget.isSettingsScreen
            ? widget.onBackPressed
            : () {
                widget.scaffoldKey.currentState?.openDrawer();
                logToFile(tag: LogTag.UI_ACTION, message: '햄버거버튼 선택');
              },
      ),
      title: _buildTitle(isKdsMode),
      bottom: isKdsMode
          ? null
          : const PreferredSize(
              preferredSize: Size.fromHeight(1),
              child: ColoredBox(
                color: AppStyles.gray3,
                child: SizedBox(height: 1, width: double.infinity),
              ),
            ),
    );

    // Windows frameless 창: 앱바 전체를 드래그 핸들로 감싼다.
    // translucent behavior라 자식(IconButton 등)의 onTap은 그대로 작동하고,
    // 드래그 시 windowManager.startDragging()이 호출된다.
    if (Platform.isWindows) {
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanStart: (_) => windowManager.startDragging(),
        onDoubleTap: () =>
            WindowsBubbleService.instance.restoreToDefaultPosition(),
        child: appBar,
      );
    }
    return appBar;
  }

  Widget _buildTitle(bool isKdsMode) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Center(
          child: GestureDetector(
            onLongPress: () {
              logger.w('시계 영역 롱프레스 감지 - 소켓 폭주 테스트 실행');
              _runSocketBurstTest(ref);
            },
            child: const _CurrentTimeWidget(),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildLeftActions(isKdsMode),
            _buildRightActions(isKdsMode),
          ],
        ),
      ],
    );
  }

  Widget _buildLeftActions(bool isKdsMode) {
    return Row(
      children: [
        // 매장명 및 주문 건수
        Row(
          children: [
            Consumer(
              builder: (context, ref, _) {
                final store = ref.watch(storeProvider);
                return Text(
                  store.value?.name ?? '',
                  style: const TextStyle(
                    fontSize: AppStyles.kAppBarTitleSize,
                    fontWeight: FontWeight.bold,
                  ),
                );
              },
            ),
            // 주문 건수 표시
            const SizedBox(width: 8),
            Consumer(
              builder: (context, ref, _) {
                // 배지가 쓰는 두 값만 select — stopBlinking 등 무관 필드 변경 시 리빌드 방지
                final (isBlinking, activeOrderCount) = ref.watch(
                    blinkStateProvider
                        .select((s) => (s.isBlinking, s.activeOrderCount)));
                return GestureDetector(
                  onTap: () {
                    if (isBlinking || activeOrderCount > 0) {
                      // OrderProvider의 stopBlinking 호출하여 점멸과 소리 함께 중지
                      ref.read(orderProvider.notifier).stopBlinking();
                      logToFile(
                          tag: LogTag.UI_ACTION,
                          message: '앱바 주문건수 터치로 알림음/점멸 중지');
                    }
                  },
                  child: Container(
                    height: 30,
                    margin: const EdgeInsets.only(left: 8),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: isBlinking
                          ? AppStyles.kMainColor.withValues(alpha: 0.5)
                          : AppStyles.kMainColor,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Center(
                      child: Text(
                        t.app_bar.new_order_count(n: activeOrderCount),
                        style: const TextStyle(
                          fontSize: AppStyles.kSectionCountSize,
                          fontWeight: FontWeight.normal,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(width: 8),
            // 새로고침 버튼 — KDS/일반 모드 공통
            AppIconAction(
              icon: Icons.refresh,
              onPressed: _handleRefresh,
              tooltip: t.common.refresh,
              isLoading: _isRefreshing,
            ),
            const SizedBox(width: 8),
            // 서브디스플레이 문구 추가 — isKdsMode는 파라미터로 전달됨
            if (isKdsMode)
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  t.app_bar.kds_mode,
                  style: const TextStyle(
                    fontSize: AppStyles.kAppBarTitleSize,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  // 현재 접속 서버 인디케이터 — dev/staging 등 비-운영 환경에서만 노출.
  // live / japanLive 운영 환경에서는 빈 위젯을 반환해 표시하지 않는다.
  Widget _buildServerIndicator() {
    final env = appfit_core.AppFitConfig.environment;
    if (env == appfit_core.AppFitEnvironment.live ||
        env == appfit_core.AppFitEnvironment.japanLive) {
      return const SizedBox.shrink();
    }

    final label = switch (env) {
      appfit_core.AppFitEnvironment.dev => 'DEV',
      appfit_core.AppFitEnvironment.staging => 'STAGING',
      _ => env.name.toUpperCase(),
    };

    return Container(
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppStyles.kAmber,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Colors.white,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildRightActions(bool isKdsMode) {
    return Row(
      children: [
        // 현재 접속 서버 표시 (live / japanLive 운영 환경 제외)
        _buildServerIndicator(),
        // 서브디스플레이 모드가 아닐 때만 오더 토글 스위치 표시
        Consumer(
          builder: (context, ref, _) {
            // KDS 모드라도 자동접수(isKdsAcceptOrders) ON 이면 영업상태 토글을 노출한다.
            // reactive: 설정화면에서 "주문 접수" 토글을 바꾸면 즉시 노출/숨김이 반영됨.
            final isKdsAcceptOrders =
                ref.watch(orderProvider.select((s) => s.isKdsAcceptOrders));
            final hideToggle = isKdsMode && !isKdsAcceptOrders;
            return hideToggle
                ? const SizedBox.shrink()
                : Row(
                    children: [
                      Text(
                        t.app_bar.order_toggle,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 8),
                      // 판매 상태 스위치
                      CustomSwitch(
                        value: ref.watch(storeProvider).value?.isOpen ?? false,
                        activeColor: AppStyles.kMainColor,
                        inactiveColor: AppStyles.gray4,
                        activeText: 'ON',
                        inactiveText: 'OFF',
                        onChanged: (value) async {
                          logToFile(
                              tag: LogTag.UI_ACTION,
                              message: '오더 스위치 터치: $value');

                          // ON/OFF 전환 시 확인 다이얼로그 표시
                          final shouldChange =
                              await CommonDialog.showConfirmDialog(
                            context: context,
                            title: value
                                ? t.app_bar.order_start_confirm_title
                                : t.app_bar.order_stop_confirm_title,
                            content: value
                                ? t.app_bar.order_start_confirm_content
                                : t.app_bar.order_stop_confirm_content,
                            confirmText: t.common.confirm,
                            cancelText: t.common.cancel,
                          );

                          if (shouldChange != true) {
                            logToFile(
                                tag: LogTag.UI_ACTION,
                                message: '오더 상태변경 팝업 취소로 닫기');
                            return; // 사용자가 취소를 선택하면 전환하지 않음
                          }

                          ref.watch(storeProvider.notifier).setIsOpen(value);
                          // 스낵바 대신 다이얼로그 표시
                          /* CommonDialog.showConfirmDialog(
                                      context: context,
                                      title: value ? '판매 시작' : '판매 중지',
                                      content:
                                          value ? '오더 판매가 시작되었습니다.' : '오더 판매가 중지되었습니다.',
                                      confirmText: '확인',
                                      cancelText: '',
                                    );*/
                        },
                      ),
                    ],
                  );
          },
        ),
        const SizedBox(width: 8),

        if (!isKdsMode)
          const SizedBox(
            height: 50.0, // AppBar의 기본 높이로 설정
            child: VerticalDivider(
              width: 20,
              thickness: 1.5,
              indent: 10,
              endIndent: 10,
              color: Colors.grey,
            ),
          ),

        const SizedBox(width: 8),
        // 인터넷 상태 아이콘 (비인터랙티브)
        AppIconAction(
          icon: _getNetworkIcon(),
          color: _getNetworkIconColor(),
          isStatus: true,
        ),
        const SizedBox(width: 4),
        // 소켓(실시간 주문) 연결 상태 아이콘 (3-state, disconnected시 탭 재연결)
        // 별도 Consumer: 재연결 flapping 시 앱바 전체가 아닌 아이콘만 리빌드.
        Consumer(
          builder: (context, ref, _) {
            final socketStatus = ref.watch(appFitNotifierServiceProvider);
            return AppIconAction(
              icon: socketStatus != appfit_core.ConnectionStatus.disconnected
                  ? Icons.sensors
                  : Icons.sensors_off,
              color: socketStatus.isConnected
                  ? Colors.green
                  : socketStatus == appfit_core.ConnectionStatus.reconnecting
                      ? Colors.orange
                      : Colors.red,
              tooltip: socketStatus.isConnected
                  ? '실시간 주문 수신 중'
                  : socketStatus == appfit_core.ConnectionStatus.reconnecting
                      ? '재연결 중...'
                      : '실시간 주문 연결 끊김 - 탭하여 재연결',
              onPressed:
                  socketStatus == appfit_core.ConnectionStatus.disconnected
                      ? widget.onReconnect
                      : null,
              isStatus:
                  socketStatus != appfit_core.ConnectionStatus.disconnected,
            );
          },
        ),
        const SizedBox(width: 8),
        // 최소화 버튼
        AppIconAction(
          icon: Icons.minimize_outlined,
          onPressed: widget.onMinimize,
        ),
        const SizedBox(width: 8),
        // 앱 종료 버튼
        AppIconAction(
          icon: Icons.power_settings_new,
          color: AppStyles.kRed,
          tooltip: t.app_bar.exit_app,
          onPressed: () {
            logToFile(tag: LogTag.UI_ACTION, message: '앱 종료 버튼 터치');
            _showExitConfirmationDialog(context, isKdsMode: isKdsMode);
          },
        ),
      ],
    );
  }

  // 앱 종료 확인 대화상자
  Future<void> _showExitConfirmationDialog(BuildContext context,
      {bool isKdsMode = false}) async {
    // 종료 시 매장이 CLOSED(오더 준비중)로 전환되는 조건(메인모드 or KDS+자동접수ON)이면
    // 다이얼로그 본문에 "오더 준비중으로 변경됩니다" 안내를 조합해 노출한다.
    final isKdsAcceptOrders = ref.read(orderProvider).isKdsAcceptOrders;
    final willClose = !isKdsMode || isKdsAcceptOrders;

    // StatefulBuilder를 사용하여 다이얼로그 내부 상태 관리
    // ignore: discarded_futures

    await showDialog<bool>(
      context: context,
      barrierDismissible: false, // 로딩 중에는 닫기 비활성화
      builder: (BuildContext dialogContext) {
        // StatefulBuilder를 사용하여 다이얼로그 내부에서 상태를 변경할 수 있도록 함
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Text(t.app_bar.exit_app, style: AppTextStyles.title),
              titlePadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s24,
                vertical: AppSpacing.s24,
              ),
              contentPadding: const EdgeInsets.fromLTRB(
                AppSpacing.s24,
                AppSpacing.s16,
                AppSpacing.s24,
                0,
              ),
              content: SizedBox(
                width: 400,
                height: 80,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    willClose
                        ? '${t.app_bar.exit_app_desc}\n${t.app_bar.store_closed_notice}'
                        : t.app_bar.exit_app_kds_desc,
                    style: AppTextStyles.body,
                  ),
                ),
              ),
              actionsPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s24,
                vertical: AppSpacing.s24,
              ),
              actions: <Widget>[
                ElevatedButton(
                  style: AppStyles.outlinedButton(
                    minimumSize: const Size(100, 45),
                  ),
                  onPressed: _isExiting
                      ? null
                      : () {
                          Navigator.of(dialogContext).pop(false);
                          logToFile(
                            tag: LogTag.UI_ACTION,
                            message: '앱 종료 다이얼로그 -> 취소',
                          );
                        },
                  child: Text(t.common.cancel),
                ),
                ElevatedButton(
                  style: AppStyles.primaryButton(
                    minimumSize: const Size(100, 45),
                  ),
                  onPressed: _isExiting
                      ? null
                      : () async {
                          setStateDialog(() => _isExiting = true);
                          logToFile(
                            tag: LogTag.UI_ACTION,
                            message: '앱 종료 다이얼로그 -> 종료 시작',
                          );

                          final store = ref.watch(storeProvider);
                          final storeId = store.value?.storeId ?? '';

                          // 여의도 IFC몰, 송파둘레길, 테스트매장 — 종료 전 로그 업로드
                          if (storeId.toLowerCase().contains('k0130556') ||
                              storeId.toLowerCase().contains('k0130789') ||
                              storeId.toLowerCase().contains('k0130101') ||
                              storeId.toLowerCase().contains('k0130084')) {
                            try {
                              await ref
                                  .read(appLifecycleObserverProvider.notifier)
                                  .uploadLogsOnExit();
                              logToFile(
                                tag: LogTag.SYSTEM,
                                message: '앱 종료 전 로그 업로드 성공',
                              );
                            } catch (e) {
                              logToFile(
                                tag: LogTag.ERROR,
                                message: '앱 종료 전 로그 업로드 실패: $e',
                              );
                            }
                          }

                          if (mounted) widget.onLogout();
                        },
                  child: _isExiting
                      ? const AppLoadingIndicator(
                          size: 20,
                          color: Colors.white,
                          strokeWidth: 2,
                        )
                      : Text(t.dialog.exit.confirm),
                ),
              ],
            );
          },
        );
      },
    ).then((value) {
      if (mounted && _isExiting && value == false) {
        setState(() {
          _isExiting = false;
        });
      }
    });
  }

  void _runSocketBurstTest(WidgetRef ref) {
    test_util.SocketBurstTest(ref)
        .simulateBurst(count: 10, duration: const Duration(milliseconds: 1000));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(t.app_bar.burst_test_start),
        duration: const Duration(seconds: 2),
        backgroundColor: Colors.redAccent,
      ),
    );
  }
}
