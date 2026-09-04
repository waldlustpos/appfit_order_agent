import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/services.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audioplayers/audioplayers.dart';
// import 'package:flutter_dotenv/flutter_dotenv.dart'; // Removed

import 'package:appfit_order_agent/services/label_printer/windows/windows_label_router.dart';
import 'package:appfit_order_agent/services/platform_service.dart';
import 'package:appfit_order_agent/services/preference_service.dart';
import 'package:appfit_order_agent/services/shutdown_signal_service.dart';
import 'package:appfit_order_agent/services/windows_bubble_service.dart';
import 'package:appfit_order_agent/services/windows_log_file_writer.dart';
import 'package:appfit_order_agent/dev/rebuild_counter_observer.dart';
import 'package:appfit_order_agent/utils/app_startup_updater.dart';
import 'package:appfit_order_agent/utils/windows_startup_maintenance.dart';
import 'package:appfit_order_agent/utils/logger.dart';
import 'package:appfit_order_agent/widgets/windows_bubble_overlay.dart';
import 'package:appfit_core/appfit_core.dart'; // AppFit Core 추가
import 'package:appfit_order_agent/firebase_options.dart';
import 'package:appfit_order_agent/screens/home_screen.dart';
import 'package:appfit_order_agent/screens/login_screen.dart';
import 'package:appfit_order_agent/screens/settings_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:sentry_flutter/sentry_flutter.dart' show Sentry;
import 'package:window_manager/window_manager.dart';

import 'package:appfit_order_agent/config/app_env.dart'; // AppEnv 추가
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:appfit_order_agent/i18n/strings.g.dart';
import 'package:appfit_order_agent/providers/fleet_provider.dart';
import 'package:appfit_order_agent/providers/sales_off_provider.dart';
import 'package:appfit_order_agent/providers/locale_provider.dart';
import 'package:appfit_order_agent/providers/rotation_provider.dart';
import 'package:appfit_order_agent/services/monitoring/monitoring_context_builder.dart';
import 'package:appfit_order_agent/services/monitoring/order_agent_monitoring_context.dart';
import 'package:appfit_order_agent/config/build_brand.dart';
import 'package:appfit_order_agent/constants/app_styles.dart';
import 'package:appfit_order_agent/constants/brand_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 알림음이 매장 배경음악(BGM)을 죽이지 않도록 전역 오디오 컨텍스트를 먼저
  // 확정한다. audioplayers 기본값은 AUDIOFOCUS_GAIN 이라 BGM 앱에
  // AUDIOFOCUS_LOSS(영구 상실)를 통보해 재생이 멈추고 자동 복구되지 않는다.
  // none 은 포커스 요청 자체를 하지 않아 BGM 과 믹스되며, 다른 앱이 포커스를
  // 내주지 않아 알림음이 무음이 되는 경우도 함께 사라진다.
  //
  // 네이티브 플러그인이 이 값을 defaultAudioContext 로 보관하고 이후 생성되는
  // 모든 AudioPlayer 가 상속하므로 runApp 이전에 걸어야 한다.
  // (Windows 는 "not supported on Windows" 로그만 남기므로 Android 한정)
  // 플랫폼 채널이 응답하지 않아도 앱 기동을 막지 않도록 best-effort 2초.
  // 실패해도 SoundService 가 재생 직전에 같은 설정을 다시 건다.
  if (Platform.isAndroid) {
    try {
      await AudioPlayer.global
          .setAudioContext(
            AudioContext(
              android: const AudioContextAndroid(
                audioFocus: AndroidAudioFocus.none,
              ),
            ),
          )
          .timeout(const Duration(seconds: 2));
    } catch (e, s) {
      logger.w('전역 AudioContext 설정 실패 (알림음 재생 자체에는 영향 없음)',
          error: e, stackTrace: s);
    }
  }

  // Windows: 플로팅 버블 UX용 window_manager 초기화.
  if (Platform.isWindows) {
    try {
      await windowManager.ensureInitialized();
      await WindowsBubbleService.instance.init();
      LaunchAtStartup.instance.setup(
        appName: 'AppfitOrderAgent',
        appPath: Platform.resolvedExecutable,
      );
      unawaited(WindowsLogFileWriter.deleteOldLogs());
      // 라벨 프린터 NativeCallable / USB 핸들 누수 방어. 앱이 detached 로
      // 진입할 때 (창 닫기, 시스템 종료, 업데이터 재시작) SDK 콜백을 정리한다.
      WidgetsBinding.instance.addObserver(_LabelPrinterLifecycleObserver());
    } catch (e, s) {
      logger.e('Windows 초기화 실패', error: e, stackTrace: s);
    }
  }

  // 한국어 복수형 resolver 설정 (한국어는 복수형 구분 없음)
  // slang 4: 동기 변형(setPluralResolverSync), lazy:false 전제
  LocaleSettings.setPluralResolverSync(
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
  // 단일 빌드: 서버는 런타임 저장값(로그인 화면 서버선택 + 매장 ID 프리픽스
  // 자동 전환)으로 결정한다. 릴리즈는 live/japanLive/staging 만 허용하며 dev
  // 잔존값은 live 로 클램프한다(개발 빌드에서 넘어온 기기 방어).
  var environment = switch (savedEnv) {
    'live' => AppFitEnvironment.live,
    'japanLive' => AppFitEnvironment.japanLive,
    'dev' => AppFitEnvironment.dev,
    'staging' => AppFitEnvironment.staging,
    _ => AppFitEnvironment.live,
  };
  if (kReleaseMode && environment == AppFitEnvironment.dev) {
    environment = AppFitEnvironment.live;
    // 저장값도 함께 정정해 로그인 화면 배지·프리픽스 자동 전환 로직과
    // 어긋나지 않게 한다.
    await preferenceServiceForEnv.setEnvironment('live');
  }

  // AppFit 공통 패키지 설정
  AppFitConfig.configure(
    environment: environment,
    requestSource: 'ORDER_AGENT',
  );

  logger.i(AppFitConfig.getConfigSummary());

  // 전원종료 영업 OFF 경로의 진단 호스트 등록(Android 전용). 채널 핸들러는
  // ProviderScope 안의 salesOffSyncProvider 가 건다.
  await ShutdownSignalService.syncProbeHost();

  if (!AppEnv.hasKey) {
    logger
        .w('[Main] APPFIT_AES_KEY is missing. Check --dart-define arguments.');
  }

  // 기기 및 앱 정보 수집 (MonitoringService 초기화에 필요)
  final monitoringContext = await buildOrderAgentMonitoringContext();
  // 기기 시리얼(예: H092W24A1G00862). Sunmi 는 프린터 서비스 폴링이 있어 시작
  // 지연을 막기 위해 1초 타임아웃 best-effort.
  String? deviceSerial;
  try {
    deviceSerial = await PlatformService.getDeviceSerial()
        .timeout(const Duration(seconds: 1), onTimeout: () => null);
    // 읽었으면 캐시에 남긴다 — 안 남기면 DeviceIdentityService 가 같은 네이티브
    // 조회를 한 번 더 해서 부팅 경로가 Sunmi 프린터 서비스를 두 번 두드린다.
    if (deviceSerial != null && deviceSerial.isNotEmpty) {
      await preferenceServiceForEnv.setCachedDeviceSerial(deviceSerial);
    }
  } catch (_) {}
  _logStartupInfo(monitoringContext, deviceSerial);

  // MonitoringService 초기화 (Sentry DSN이 있을 때만)
  if (AppEnv.hasSentryDsn) {
    await MonitoringService.instance.init(
      dsn: AppEnv.sentryDsn,
      context: monitoringContext,
    );
    logger.i('MonitoringService 초기화 완료');

    // 로그인 전 이벤트도 기기를 특정할 수 있게 식별 태그를 먼저 심는다. Windows
    // 는 시리얼이 없어 설치 UUID 가 유일한 식별자이고, 로그인 전 구간에는 OTA
    // 자가 업데이트(runStartupUpdateFlow)가 있어 실제로 사고가 나는 자리다.
    // 로그인 후에는 DeviceInventoryReporter 가 같은 정본으로 다시 심는다.
    final serial = deviceSerial;
    if (serial != null && serial.isNotEmpty) {
      Sentry.configureScope((scope) {
        scope.setTag('device_serial', serial);
        scope.setTag('device_id', serial); // DeviceIdentity 와 같은 우선순위
      });
    } else {
      final installId = await preferenceServiceForEnv.getOrCreateInstallId();
      Sentry.configureScope((scope) => scope.setTag('device_id', installId));
    }

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
  // 디버그 모드에서는 --build-number 주입 없이 실행되어 서버 버전과
  // 어긋난 채 OTA 가 트리거될 수 있으므로 skip.
  if (Platform.isWindows && kReleaseMode) {
    await runStartupUpdateFlow();
  } else if (Platform.isWindows) {
    logger.i('[Main] Debug 모드 — Windows OTA 업데이트 체크 skip');
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

    // Windows per-user 설치 전환 뒤처리 — 자동실행 레지스트리 경로 갱신 +
    // Defender 예외 자가진단. 어느 작업도 실패가 기동을 막지 않는다.
    //
    // 이 위치는 runStartupUpdateFlow()(업데이트 설치 시 exit(0)) **이후**라,
    // 실제 업데이트가 설치되는 회차에는 실행되지 않고 정상 기동 회차에만 돈다.
    await runWindowsStartupMaintenance(preferenceService);

    // Windows: 라벨 프린터 사용 ON 이면 시작 시점에 USB 포트를 미리 연다.
    // 첫 인쇄 지연 제거 + 설정 화면 연결 상태가 즉시 정확히 표시되도록 함.
    // 실패해도 polling/lazy fallback 이 살아있어 앱 시작을 차단하지 않는다.
    //
    // (Android 대응물은 PrintService._runStartupConnectionCheck 에 있다 —
    //  라벨 토글 캐시와 warm-up 재시도 스케줄러가 그쪽에 있어서다.)
    if (Platform.isWindows && preferenceService.getUseLabelPrinter()) {
      final mode = preferenceService.getLabelAutoReplyMode();
      unawaited(WindowsLabelRouter.instance.warmupOpen(autoReplyMode: mode));
    }

    // 브랜드 테마 적용 — runApp 이전에 AppStyles 의 활성 브랜드를 확정
    // 저장값이 전혀 없는 경우(신규 설치·한 번도 선택한 적 없음)에만 매머드
    // flavor 빌드는 로그인 전부터 매머드 테마로 프리시드한다. 사용자가 설정
    // 화면에서 명시적으로 "기본 테마"를 선택해 저장한 경우는 그 선택을 그대로
    // 존중한다 — 여기서 다시 덮어쓰면 설정의 테마 선택 자체가 무의미해진다.
    final savedId = preferenceService.getBrandThemeId();
    final savedBrand = savedId != null
        ? BrandTheme.fromId(savedId)
        : (BuildBrand.isMammoth
            ? BrandTheme.mammothCoffee
            : BrandTheme.appfitDefault);
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
    runApp(
      ProviderScope(
        // [DEV] 리빌드 카운트 검증용 옵저버 (release 영향 없음 — kDebugMode 가드).
        observers: kDebugMode ? [RebuildCounterObserver()] : const [],
        child: const MyApp(),
      ),
    );
  } catch (e, s) {
    logger.e('앱 초기화 중 오류 발생', error: e, stackTrace: s);
    MonitoringService.instance.captureError(e, s, hint: '앱 초기화 중 오류 발생');
    runApp(
      ProviderScope(
        // [DEV] 리빌드 카운트 검증용 옵저버 (release 영향 없음 — kDebugMode 가드).
        observers: kDebugMode ? [RebuildCounterObserver()] : const [],
        child: const MyApp(),
      ),
    );
  }
}

/// 앱 시작 시 기기/앱 정보를 로그로 기록
void _logStartupInfo(OrderAgentMonitoringContext ctx, String? deviceSerial) {
  const sep = '[SYSTEM] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
  final serialSuffix = (deviceSerial != null && deviceSerial.isNotEmpty)
      ? ' ($deviceSerial)'
      : '';
  logger.i(sep);
  logger.i(
      '[SYSTEM]  앱 시작 — Appfit 주문 에이전트 v${ctx.appVersion} (${ctx.buildNumber})');
  logger.i(
      '[SYSTEM]  기기: ${ctx.deviceManufacturer} ${ctx.deviceModel}$serialSuffix');
  logger.i('[SYSTEM]  환경: ${ctx.environment}');
  logger.i(sep);
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
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 로캘 상태 감지
    final locale = ref.watch(localeNotifierProvider);
    // 화면 반전 상태 감지 (설정 화면 토글 UI 동기화용)
    ref.watch(rotationNotifierProvider);
    // 기기 관제 보고 활성화. home_screen 이 아니라 여기인 이유는 로그인 화면에
    // 머무는 기기(설치했는데 로그인 안 된 기기)도 관제에 보여야 하기 때문이다.
    // 실제 기동 여부는 대상 매장 화이트리스트가 가른다(fleetEnabledProvider).
    ref.watch(fleetSyncProvider);
    // 기기 전원종료·앱 종료 시 매장 CLOSED 전환. fleet 과 같은 이유로 여기다 —
    // 로그인 전 기기도 배선은 되어 있어야 하고(가드는 서비스 안에 있다), 화면
    // 전환에 따라 리스너가 붙었다 떨어졌다 하면 안 된다.
    ref.watch(salesOffSyncProvider);

    // Windows 버블 모드 처리.
    // _buildMainApp 을 ValueListenableBuilder 의 child 로 전달해 한 번만 빌드,
    // isBubbleMode 변경 시 MaterialApp 을 재생성하지 않고 Visibility 로
    // 숨김/표시만 전환 → Navigator 상태(로그인 후 홈) 보존.
    if (Platform.isWindows) {
      return ValueListenableBuilder<bool>(
        valueListenable: WindowsBubbleService.instance.isBubbleMode,
        builder: (context, isBubble, child) {
          // 메인 앱은 항상 일반 모드 창 크기(originalSize)로 layout. 버블 모드
          // 진입 시 윈도우가 80x80으로 줄어들어도 Positioned가 child의 layout
          // 영역을 originalSize로 lock해서, KDS 카드 그리드의 LayoutBuilder /
          // MediaQuery가 size 변화를 보지 않는다. 이게 없으면 AnimatedContainer
          // (cardSizeAnimDuration)가 height 트랜지션을 재생해 "카드 펼쳐짐"
          // 애니메이션이 복귀 시 반복된다.
          final lockedSize = WindowsBubbleService.instance.originalSize;
          return Directionality(
            textDirection: TextDirection.ltr,
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  width: lockedSize.width,
                  height: lockedSize.height,
                  child: Visibility(
                    visible: !isBubble,
                    maintainState: true,
                    maintainAnimation: true,
                    maintainSize: true,
                    child: child!,
                  ),
                ),
                if (isBubble)
                  const Positioned.fill(
                    child: MaterialApp(
                      debugShowCheckedModeBanner: false,
                      home: WindowsBubbleOverlay(),
                    ),
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
    super.key,
    required this.child,
  });

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

/// 매장 PC 장기 운영 시 NativeCallable 콜백 누수 방어. Windows 전용으로
/// main() 에서 한 번만 등록한다.
class _LabelPrinterLifecycleObserver with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached && Platform.isWindows) {
      try {
        WindowsLabelRouter.instance.dispose();
        logger.i('WindowsLabelRouter dispose (lifecycle detached)');
      } catch (e, s) {
        logger.w('WindowsLabelRouter dispose 예외', error: e, stackTrace: s);
      }
    }
  }
}
