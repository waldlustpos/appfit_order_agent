import 'dart:io';
import 'dart:ui';
import 'package:flutter/services.dart';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
// import 'package:flutter_dotenv/flutter_dotenv.dart'; // Removed

import 'package:appfit_order_agent/services/platform_service.dart';
import 'package:appfit_order_agent/services/preference_service.dart';
import 'package:appfit_order_agent/services/windows_bubble_service.dart';
import 'package:appfit_order_agent/utils/app_startup_updater.dart';
import 'package:appfit_order_agent/utils/logger.dart';
import 'package:appfit_order_agent/widgets/windows_bubble_overlay.dart';
import 'package:appfit_core/appfit_core.dart'; // AppFit Core 추가
import 'firebase_options.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/settings_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:window_manager/window_manager.dart';

import 'config/app_env.dart'; // AppEnv 추가
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:appfit_order_agent/i18n/strings.g.dart';
import 'package:appfit_order_agent/providers/locale_provider.dart';
import 'package:appfit_order_agent/providers/rotation_provider.dart';
import 'services/monitoring/order_agent_monitoring_context.dart';
import 'constants/app_styles.dart';
import 'constants/brand_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Windows: 플로팅 버블 UX용 window_manager 초기화.
  if (Platform.isWindows) {
    try {
      await windowManager.ensureInitialized();
      await WindowsBubbleService.instance.init();
      LaunchAtStartup.instance.setup(
        appName: 'AppfitOrderAgent',
        appPath: Platform.resolvedExecutable,
      );
    } catch (e, s) {
      logger.e('Windows 초기화 실패', error: e, stackTrace: s);
    }
  }

  // 한국어 복수형 resolver 설정 (한국어는 복수형 구분 없음)
  LocaleSettings.setPluralResolver(
    locale: AppLocale.ko,
    cardinalResolver: (n, {zero, one, two, few, many, other}) =>
        other ?? zero ?? '',
    ordinalResolver: (n, {zero, one, two, few, many, other}) =>
        other ?? zero ?? '',
  );

  // 화면 방향을 가로(Landscape)로 고정 (모바일 전용)
  if (Platform.isAndroid || Platform.isIOS) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  // 저장된 환경 설정 읽기 (AppFitConfig.configure 이전에 초기화 필요)
  final preferenceServiceForEnv = PreferenceService();
  await preferenceServiceForEnv.init();
  final savedEnv = preferenceServiceForEnv.getEnvironment();
  final environment = switch (savedEnv) {
    'live' => AppFitEnvironment.live,
    'japanLive' => AppFitEnvironment.japanLive,
    'dev' => AppFitEnvironment.dev,
    'staging' => AppFitEnvironment.staging,
    _ => AppFitEnvironment.live,
  };

  // AppFit 공통 패키지 설정
  AppFitConfig.configure(
    environment: environment,
    requestSource: 'ORDER_AGENT',
  );

  logger.i(AppFitConfig.getConfigSummary());

  if (!AppEnv.hasKey) {
    logger
        .w('[Main] APPFIT_AES_KEY is missing. Check --dart-define arguments.');
  }

  // 기기 및 앱 정보 수집 (MonitoringService 초기화에 필요)
  final monitoringContext = await _buildMonitoringContext();
  _logStartupInfo(monitoringContext);

  // MonitoringService 초기화 (Sentry DSN이 있을 때만)
  if (AppEnv.hasSentryDsn) {
    await MonitoringService.instance.init(
      dsn: AppEnv.sentryDsn,
      context: monitoringContext,
    );
    logger.i('MonitoringService 초기화 완료');

    // Flutter UI 오류 (치명적 오류 자동 수집)
    FlutterError.onError = (details) {
      MonitoringService.instance.captureError(
        details.exception,
        details.stack,
        hint: 'Flutter fatal error: ${details.exceptionAsString()}',
      );
    };

    // Dart 비동기 미처리 오류 (Zone 외부 오류 자동 수집)
    PlatformDispatcher.instance.onError = (error, stack) {
      MonitoringService.instance.captureError(
        error,
        stack,
        hint: 'Unhandled async error',
      );
      return true;
    };
  } else {
    logger.w('[Main] SENTRY_DSN is missing. Monitoring disabled.');
  }

  // Windows: 앱 시작 시 OTA 자가 업데이트 체크 (로그인 이전).
  // 업데이트 설치 시 exit(0) 되므로 아래 runApp 이 실행되지 않는다.
  if (Platform.isWindows) {
    await runStartupUpdateFlow();
  }

  try {
    // Firebase 초기화 (Windows 는 firebase_options.dart 에 Windows 항목 없음 — skip)
    if (!Platform.isWindows) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      logger.i('Firebase 초기화 완료');
    } else {
      logger.i('Windows 플랫폼 — Firebase 초기화 skip');
    }

    // PreferenceService 초기화 (V2 마이그레이션 포함)
    final preferenceService = PreferenceService();
    await preferenceService.init();
    logger.i('PreferenceService 초기화 완료');

    // 브랜드 테마 적용 — runApp 이전에 AppStyles 의 활성 브랜드를 확정
    final savedBrand = BrandTheme.fromId(preferenceService.getBrandThemeId());
    AppStyles.applyBrand(savedBrand);
    logger.i('[Main] 브랜드 테마 적용: ${savedBrand.id}');

    // 저장된 시스템 회전 설정 복원 (Android 전용)
    if (!Platform.isWindows) {
      final savedRotation = preferenceService.getIsRotated180();
      if (savedRotation) {
        await PlatformService.setSystemRotation(true);
        logger.i('시스템 회전 설정 복원: 180도');
      }
    }

    // 앱 실행
    runApp(const ProviderScope(child: MyApp()));
  } catch (e, s) {
    logger.e('앱 초기화 중 오류 발생', error: e, stackTrace: s);
    MonitoringService.instance.captureError(e, s, hint: '앱 초기화 중 오류 발생');
    runApp(const ProviderScope(child: MyApp()));
  }
}

/// 앱 시작 시 기기/앱 정보를 로그로 기록
void _logStartupInfo(OrderAgentMonitoringContext ctx) {
  const sep = '[SYSTEM] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
  logger.i(sep);
  logger.i(
      '[SYSTEM]  앱 시작 — Appfit 주문 에이전트 v${ctx.appVersion} (${ctx.buildNumber})');
  logger.i('[SYSTEM]  기기: ${ctx.deviceManufacturer} ${ctx.deviceModel}');
  logger.i('[SYSTEM]  환경: ${ctx.environment}');
  logger.i(sep);
}

/// 기기/앱 정보를 수집하여 MonitoringContext 생성
Future<OrderAgentMonitoringContext> _buildMonitoringContext() async {
  String deviceModel = 'Unknown';
  String deviceManufacturer = 'Unknown';
  String appVersion = '';
  String buildNumber = '';

  try {
    final deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final info = await deviceInfo.androidInfo;
      deviceModel = info.model;
      deviceManufacturer = info.manufacturer;
    } else if (Platform.isIOS) {
      final info = await deviceInfo.iosInfo;
      deviceModel = info.model;
      deviceManufacturer = 'Apple';
    } else if (Platform.isWindows) {
      final info = await deviceInfo.windowsInfo;
      deviceModel = info.computerName;
      deviceManufacturer = 'Microsoft';
    }
  } catch (e, s) {
    logger.d('Failed to get device info: $e');
  }

  try {
    final pkgInfo = await PackageInfo.fromPlatform();
    appVersion = pkgInfo.version;
    buildNumber = pkgInfo.buildNumber;
  } catch (e, s) {
    logger.d('Failed to get package info: $e');
  }

  return OrderAgentMonitoringContext(
    appVersion: appVersion,
    buildNumber: buildNumber,
    deviceModel: deviceModel,
    deviceManufacturer: deviceManufacturer,
    environment: AppFitConfig.environment.name,
  );
}

// _checkLegacyDataPermissions 제거됨: V2 마이그레이션은 PreferenceService.init()에서 처리

ThemeData _buildTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: AppStyles.kMainColor,
    brightness: Brightness.light,
  ).copyWith(
    // 앱 전반에 쓰이는 상태 색상은 기존 팔레트 유지
    error: AppStyles.kRed,
    surface: AppStyles.gray1,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    fontFamily: 'Pretendard',

    // ── AppBar ─────────────────────────────────────────────────────────────
    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: Colors.white,
      foregroundColor: AppStyles.gray9,
      surfaceTintColor: Colors.transparent,
      iconTheme: const IconThemeData(color: AppStyles.gray9, size: 24),
      actionsIconTheme: const IconThemeData(color: AppStyles.gray9, size: 24),
      titleTextStyle: AppTextStyles.titleSm.copyWith(color: AppStyles.gray9),
    ),

    // ── 버튼 ───────────────────────────────────────────────────────────────
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppStyles.kMainColor,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.bSm),
        textStyle: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppStyles.kMainColor,
        side: BorderSide(color: AppStyles.kMainColor),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.bSm),
        textStyle: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppStyles.kMainColor,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.bSm),
        textStyle: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: AppStyles.gray9,
        highlightColor: AppStyles.kMainColor.withAlpha(20),
      ),
    ),

    // ── 카드 ───────────────────────────────────────────────────────────────
    cardTheme: const CardThemeData(
      elevation: 0,
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.bLg,
        side: BorderSide(color: AppStyles.gray3),
      ),
      margin: EdgeInsets.all(AppSpacing.s4),
    ),

    // ── 다이얼로그 ─────────────────────────────────────────────────────────
    dialogTheme: DialogThemeData(
      backgroundColor: AppStyles.gray1,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.bLg),
      elevation: 8,
      titleTextStyle: AppTextStyles.title.copyWith(color: AppStyles.gray9),
      contentTextStyle: AppTextStyles.body.copyWith(color: AppStyles.gray6),
    ),

    // ── TabBar ──────────────────────────────────────────────────────────────
    tabBarTheme: TabBarThemeData(
      labelColor: AppStyles.kMainColor,
      unselectedLabelColor: AppStyles.gray6,
      labelStyle: AppTextStyles.titleSm,
      unselectedLabelStyle: AppTextStyles.titleSm,
      indicatorColor: AppStyles.kMainColor,
      indicatorSize: TabBarIndicatorSize.tab,
      dividerColor: AppStyles.gray3,
    ),

    // ── 입력 필드 ──────────────────────────────────────────────────────────
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppStyles.gray2,
      border: const OutlineInputBorder(
        borderSide: BorderSide.none,
        borderRadius: AppRadius.bSm,
      ),
      enabledBorder: const OutlineInputBorder(
        borderSide: BorderSide.none,
        borderRadius: AppRadius.bSm,
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: AppStyles.kMainColor, width: 2),
        borderRadius: AppRadius.bSm,
      ),
      errorBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: AppStyles.kRed),
        borderRadius: AppRadius.bSm,
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s16,
        vertical: AppSpacing.s12,
      ),
    ),

    // ── 구분선 ─────────────────────────────────────────────────────────────
    dividerTheme: const DividerThemeData(
      color: AppStyles.gray3,
      thickness: 1,
      space: 1,
    ),

    // ── PopupMenu ──────────────────────────────────────────────────────────
    popupMenuTheme: PopupMenuThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 4,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.bMd),
      textStyle: AppTextStyles.body.copyWith(color: AppStyles.gray9),
    ),

    // ── 페이지 전환 ────────────────────────────────────────────────────────
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: ZoomPageTransitionsBuilder(),
        TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
      },
    ),
  );
}

class MyApp extends ConsumerWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 로캘 상태 감지
    final locale = ref.watch(localeNotifierProvider);
    // 화면 반전 상태 감지 (설정 화면 토글 UI 동기화용)
    ref.watch(rotationNotifierProvider);

    // Windows 버블 모드 처리.
    // _buildMainApp 을 ValueListenableBuilder 의 child 로 전달해 한 번만 빌드,
    // isBubbleMode 변경 시 MaterialApp 을 재생성하지 않고 Visibility 로
    // 숨김/표시만 전환 → Navigator 상태(로그인 후 홈) 보존.
    if (Platform.isWindows) {
      return ValueListenableBuilder<bool>(
        valueListenable: WindowsBubbleService.instance.isBubbleMode,
        builder: (context, isBubble, child) {
          return Directionality(
            textDirection: TextDirection.ltr,
            child: Stack(
              children: [
                Visibility(
                  visible: !isBubble,
                  maintainState: true,
                  child: child!,
                ),
                if (isBubble)
                  const MaterialApp(
                    debugShowCheckedModeBanner: false,
                    home: WindowsBubbleOverlay(),
                  ),
              ],
            ),
          );
        },
        child: _buildMainApp(locale),
      );
    }

    return _buildMainApp(locale);
  }

  Widget _buildMainApp(AppLocale locale) {
    return TranslationProvider(
      child: MaterialApp(
        title: 'Appfit 주문 에이전트',
        // i18n 설정
        locale: locale.flutterLocale,
        supportedLocales: AppLocaleUtils.supportedLocales,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,

        theme: _buildTheme(),
        builder: (context, child) {
          // WillPopScope로 뒤로가기 버튼 동작 제어
          return PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, [dynamic result]) async {
              logger.d('onPopInvokedWithResult: didPop=$didPop');
              await PlatformService.moveToBackground();
            },
            child: GestureDetector(
              // 화면의 다른 부분을 터치하면 키보드가 닫힘
              onTap: () {
                FocusManager.instance.primaryFocus?.unfocus();
              },
              // 제스처가 하위 위젯의 동작을 방해하지 않도록 설정
              behavior: HitTestBehavior.translucent,
              child: EdgeSwipeDetector(child: child!),
            ),
          );
        },
        initialRoute: '/login',
        routes: {
          '/login': (context) => const LoginScreen(),
          '/home': (context) => const HomeScreen(),
          '/settings': (context) => const SettingsScreen(),
        },
        debugShowCheckedModeBanner: true,
      ),
    );
  }
}

// Widget to detect edge swipes and show system UI
class EdgeSwipeDetector extends StatelessWidget {
  final Widget child;

  const EdgeSwipeDetector({
    Key? key,
    required this.child,
  }) : super(key: key);

  // Show system UI via method channel
  Future<void> _showSystemUI(String a) async {
    try {
      await platform.invokeMethod('showSystemUI');
    } catch (e, s) {
      logger.d('Error showing system UI: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Main app content
        child,

        // Bottom edge swipe detector - only enable this one
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 10, // Detection area height
          child: GestureDetector(
            onVerticalDragStart: (_) => _showSystemUI('Bottom'),
            child: Container(
              color: Colors.transparent,
            ),
          ),
        ),
      ],
    );
  }
}
