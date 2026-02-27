import 'dart:io';
import 'package:flutter/services.dart';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// import 'package:flutter_dotenv/flutter_dotenv.dart'; // Removed

import 'package:kokonut_order_agent/services/platform_service.dart';
import 'package:kokonut_order_agent/services/preference_service.dart';
import 'package:kokonut_order_agent/utils/logger.dart';
import 'package:appfit_core/appfit_core.dart'; // AppFit Core 추가
import 'firebase_options.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';

import 'config/app_env.dart'; // AppEnv 추가
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:kokonut_order_agent/i18n/strings.g.dart';
import 'package:kokonut_order_agent/providers/locale_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 한국어 복수형 resolver 설정 (한국어는 복수형 구분 없음)
  LocaleSettings.setPluralResolver(
    locale: AppLocale.ko,
    cardinalResolver: (n, {zero, one, two, few, many, other}) => other ?? zero ?? '',
    ordinalResolver: (n, {zero, one, two, few, many, other}) => other ?? zero ?? '',
  );

  // 화면 방향을 가로(Landscape)로 고정
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // AppFit 공통 패키지 설정
  AppFitConfig.configure(
    environment: AppFitEnvironment.staging,
    requestSource: 'ORDER_AGENT',
  );

  logger.i(AppFitConfig.getConfigSummary());

  if (!AppEnv.hasKey) {
    logger
        .w('[Main] APPFIT_AES_KEY is missing. Check --dart-define arguments.');
  }

  try {
    // 환경 변수 로드 (Removed dotenv.load)
    // await dotenv.load(fileName: '.env');
    // logger.i('환경 변수 로드 완료');

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


    // 앱 실행
    runApp(const ProviderScope(
      child: MyApp(),
    ));
  } catch (e, s) {
    logger.e('앱 초기화 중 오류 발생', error: e, stackTrace: s);
    runApp(const ProviderScope(
      child: MyApp(),
    ));
  }
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

Future<void> getDeviceInfo() async {
  DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
  String deviceModel = 'Unknown';
  String deviceManufacturer = 'Unknown';

  try {
    if (Platform.isAndroid) {
      AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
      deviceModel = androidInfo.model; // 예: "Pixel 6"
      deviceManufacturer = androidInfo.manufacturer; // 예: "Google"
    } else if (Platform.isIOS) {
      IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
      deviceModel = iosInfo.model; // 예: "iPhone"
      // iOS에서는 제조사 정보가 따로 제공되지 않음 (항상 "Apple")
      deviceManufacturer = "Apple";
      // iosInfo.utsname.machine 등을 통해 더 상세한 모델 식별자(예: "iPhone14,5")를 얻을 수 있습니다.
    }
    // 다른 플랫폼(웹, 리눅스 등)에 대한 처리도 추가 가능
  } catch (e) {
    logger.d('Failed to get device info: $e');
  }

  logToFile(
      tag: LogTag.SYSTEM,
      message:
          'Device Info: model=$deviceModel, manufacturer=$deviceManufacturer');
}

class MyApp extends ConsumerWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 로캘 상태 감지
    final locale = ref.watch(localeNotifierProvider);

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
          // 빌드 옵션에 따른 화면 180도 회전 처리
          Widget content = child!;
          if (AppEnv.isRotated180) {
            content = RotatedBox(
              quarterTurns: 2, // 180도 회전
              child: content,
            );
          }

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
              child: EdgeSwipeDetector(child: content),
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
