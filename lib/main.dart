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
import 'package:appfit_order_agent/utils/logger.dart';
import 'package:appfit_core/appfit_core.dart'; // AppFit Core 추가
import 'firebase_options.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';

import 'config/app_env.dart'; // AppEnv 추가
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:appfit_order_agent/i18n/strings.g.dart';
import 'package:appfit_order_agent/providers/locale_provider.dart';
import 'package:appfit_order_agent/providers/rotation_provider.dart';
import 'services/monitoring/order_agent_monitoring_context.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 한국어 복수형 resolver 설정 (한국어는 복수형 구분 없음)
  LocaleSettings.setPluralResolver(
    locale: AppLocale.ko,
    cardinalResolver: (n, {zero, one, two, few, many, other}) =>
        other ?? zero ?? '',
    ordinalResolver: (n, {zero, one, two, few, many, other}) =>
        other ?? zero ?? '',
  );

  // 화면 방향을 가로(Landscape)로 고정
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // 저장된 환경 설정 읽기 (AppFitConfig.configure 이전에 초기화 필요)
  final preferenceServiceForEnv = PreferenceService();
  await preferenceServiceForEnv.init();
  final savedEnv = preferenceServiceForEnv.getEnvironment();
  final environment = switch (savedEnv) {
    'live' => AppFitEnvironment.live,
    'japanLive' => AppFitEnvironment.japanLive,
    'dev' => AppFitEnvironment.dev,
    'staging' => AppFitEnvironment.staging,
    _ => AppFitEnvironment.japanLive,
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

  try {
    // Firebase 초기화
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    logger.i('Firebase 초기화 완료');

    // 레거시 데이터 권한 확인
    await _checkLegacyDataPermissions();

    // PreferenceService 초기화
    final preferenceService = PreferenceService();
    await preferenceService.init();
    logger.i('PreferenceService 초기화 완료');

    // 저장된 시스템 회전 설정 복원 (ON 상태일 때만 — 권한 필요 없는 기본값은 호출 불필요)
    final savedRotation = preferenceService.getIsRotated180();
    if (savedRotation) {
      await PlatformService.setSystemRotation(true);
      logger.i('시스템 회전 설정 복원: 180도');
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
  logger.i('[SYSTEM]  앱 시작 — Appfit 주문 에이전트 v${ctx.appVersion} (${ctx.buildNumber})');
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
    }
  } catch (e) {
    logger.d('Failed to get device info: $e');
  }

  try {
    final pkgInfo = await PackageInfo.fromPlatform();
    appVersion = pkgInfo.version;
    buildNumber = pkgInfo.buildNumber;
  } catch (e) {
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

/// 레거시 데이터 접근 권한 확인 및 요청
Future<void> _checkLegacyDataPermissions() async {
  try {
    // 이미 마이그레이션이 완료되었는지 확인
    final prefs = await SharedPreferences.getInstance();
    final bool migrationCompleted =
        prefs.getBool('migration_completed') ?? false;

    if (migrationCompleted) {
      logger.i('마이그레이션이 이미 완료되었습니다. 권한 확인 건너뜀');
      return;
    }

    logger.i('레거시 데이터 접근 권한 확인 중...');
    final bool hasAccess = await PlatformService.checkLegacyDataAccess();

    if (!hasAccess) {
      logger.w('레거시 데이터 접근 권한이 없습니다. 권한 요청 시도...');
      // 권한 요청 후 다시 확인
      final bool accessAfterRequest =
          await PlatformService.checkLegacyDataAccess();
      logger.i('권한 요청 후 접근 가능 여부: $accessAfterRequest');

      if (!accessAfterRequest) {
        // 대체 방법 시도 (여러 패키지명)
        logger.w('기본 접근 권한을 얻지 못했습니다. 대체 방법 시도...');
        final alternativeResult =
            await PlatformService.tryAlternativeLegacyAccess();

        if (alternativeResult != null &&
            alternativeResult.containsKey('migration_success')) {
          final bool alternativeSuccess =
              alternativeResult['migration_success'] as bool? ?? false;
          logger.i('대체 접근 방법 결과: $alternativeSuccess');
        }
      }
    } else {
      logger.i('레거시 데이터 접근 권한이 있습니다.');
    }
  } catch (e, s) {
    logger.e('레거시 데이터 접근 권한 확인 중 오류 발생', error: e, stackTrace: s);
  }
}

class MyApp extends ConsumerWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 로캘 상태 감지
    final locale = ref.watch(localeNotifierProvider);
    // 화면 반전 상태 감지 (설정 화면 토글 UI 동기화용)
    ref.watch(rotationNotifierProvider);

    return TranslationProvider(
      child: MaterialApp(
        title: '코코넛 주문 에이전트',
        // i18n 설정
        locale: locale.flutterLocale,
        supportedLocales: AppLocaleUtils.supportedLocales,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,

        theme: ThemeData(
          primarySwatch: Colors.brown,
          useMaterial3: true,
          fontFamily: 'SpoqaHanSansNeo',
          appBarTheme: const AppBarTheme(
            elevation: 0,
            scrolledUnderElevation: 0,
            backgroundColor: Colors.white, // 앱바 배경색
            foregroundColor: Colors.black, // 앱바 텍스트 및 아이콘 색상
            surfaceTintColor: Colors.transparent, // 스크롤 시 색조 변화 제거
          ),
        ),
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
    } catch (e) {
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
