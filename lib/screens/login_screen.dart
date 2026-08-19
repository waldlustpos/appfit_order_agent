import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:appfit_order_agent/config/app_env.dart';
import 'package:appfit_order_agent/config/build_brand.dart';
import 'package:appfit_order_agent/widgets/common/app_loading_indicator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:appfit_core/appfit_core.dart'; // AppFitConfig (패키지)
import 'package:appfit_order_agent/models/store_model.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:appfit_order_agent/utils/logger.dart';
import 'package:appfit_order_agent/services/platform_service.dart';
import 'package:appfit_order_agent/services/windows_bubble_service.dart';
import 'package:appfit_order_agent/services/preference_service.dart';
import 'package:appfit_order_agent/utils/brand_registry.dart';
import 'package:appfit_order_agent/providers/brand_provider.dart';
import 'package:appfit_order_agent/services/migration/v2_migration_service.dart';
import 'package:appfit_order_agent/services/appfit/appfit_providers.dart'
    as appfit_providers;
import 'package:appfit_order_agent/services/secure_storage_service.dart';

import 'package:appfit_order_agent/widgets/common/app_icon_action.dart';
import 'package:appfit_order_agent/widgets/common/common_dialog.dart';
import 'package:appfit_order_agent/widgets/common/brand_logo.dart';
import 'package:appfit_order_agent/constants/app_styles.dart';
import 'package:appfit_order_agent/services/local_server_service.dart';
import 'package:appfit_order_agent/services/monitoring/monitoring_context_builder.dart';
import 'package:appfit_order_agent/providers/providers.dart';
// For kDebugMode if needed
import 'package:appfit_order_agent/i18n/strings.g.dart';
import 'package:appfit_order_agent/exceptions/api_error_mapper.dart'; // 예외 → 친화 메시지
import 'package:appfit_order_agent/providers/locale_provider.dart';
import 'package:appfit_order_agent/config/ota_config.dart';
import 'package:device_info_plus/device_info_plus.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _idController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _isSaveId = false;
  bool _isAutoLogin = false;
  bool _isKdsMode = false;
  String _selectedEnv = 'live';
  int _devTapCount = 0;
  DateTime? _lastDevTap;

  var tag = '로그인';

  @override
  void initState() {
    super.initState();

    /// 연결된 USB 디바이스 확인 및 라벨 프린터 식별

    Future<void> _checkUsbDevices() async {
      try {
        final devices = await PlatformService.getConnectedUsbDevices();
        if (devices.isEmpty) {
          logToFile(tag: LogTag.PLATFORM, message: '연결된 USB 디바이스가 없습니다.');
          logger.d('연결된 USB 디바이스가 없습니다.');
          return;
        }

        for (var device in devices) {
          final vendorId = device['vendorId'];
          final productId = device['productId'];
          final manufacturer = device['manufacturerName'] ?? 'Unknown';
          final productName = device['productName'] ?? 'Unknown';

          String identification = '';
          // Posbank VID: 0x1552 (5458)
          if (vendorId == 5458 || vendorId == 0x1552) {
            identification = ' [라벨 프린터 식별됨: Posbank]';
          }

          if (identification.isNotEmpty) {
            logToFile(
              tag: LogTag.PLATFORM,
              message:
                  ' - $productName ($manufacturer): VID=$vendorId, PID=$productId$identification',
            );
          }
        }
      } catch (e, s) {
        logger.e('USB 디바이스 확인 중 오류 발생', error: e, stackTrace: s);
      }
    }

    _checkUsbDevices();

    // 저장된 서버 환경 로드
    _selectedEnv = ref.read(preferenceServiceProvider).getEnvironment();

    // 텍스트 필드 리스너는 불필요 — 로그인 버튼에서 ListenableBuilder로 처리

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // 로그인 정보 로드
      await _loadSavedLoginInfo();
      await _loadKdsModeSetting();
      await _setWindowSoftInputMode('resize');

      // 화면이 표시된 후 권한 요청
      if (mounted) {
        await _requestAllPermissions();
      }

      // 업데이트 체크 (권한 요청 후) - 자동 업데이트 설정에 따라 게이팅
      if (mounted) {
        final preferenceService = ref.read(preferenceServiceProvider);
        if (preferenceService.getAutoCheckUpdate()) {
          await _checkForUpdate(); // 내부에서 _performAutoLogin() 호출
        } else {
          await _performAutoLogin();
        }
      }
    });
  }

  @override
  void dispose() {
    _idController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // 모든 권한 요청
  Future<void> _requestAllPermissions() async {
    try {
      // 1. 파일 권한 요청
      await _checkAndRequestFilePermissions();

      // 2. 오버레이 권한 선제적 확인 및 요청 (Android 14 포함 모든 버전 대응)
      if (Platform.isAndroid && mounted) {
        await _checkAndRequestOverlayPermission();
      }
    } catch (e, s) {
      logger.e('권한 요청 중 오류 발생', error: e, stackTrace: s);
      if (mounted) {
        await CommonDialog.showInfoDialog(
          context: context,
          title: t.common.error,
          content: t.login.permission_error,
        );
      }
    }
  }

  // 파일 권한 확인 및 요청
  Future<void> _checkAndRequestFilePermissions() async {
    logger.d('파일 권한 확인 중...');
    try {
      bool permissionGranted =
          await PlatformService.checkAndRequestFilePermissions();

      // 파일 권한은 OS 자체 권한 창만 표시 (추가 팝업 없음)
      logger.d('파일 권한 요청 완료: $permissionGranted');
    } catch (e, s) {
      logger.e('파일 권한 요청 중 오류 발생', error: e, stackTrace: s);
    }
  }

  // 인터넷 연결 상태 확인 메서드
  Future<bool> _checkInternetConnection() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    // 연결이 비어있거나 모든 연결이 none인 경우 인터넷 문제로 처리
    bool hasConnection = connectivityResult.isNotEmpty &&
        !connectivityResult.contains(ConnectivityResult.none);

    if (!hasConnection && mounted) {
      CommonDialog.showInfoDialog(
        context: context,
        title: t.login.internet_error_title,
        content: t.login.internet_error_msg,
        dedupeKey: 'internet_connection_error',
      );
    }

    return hasConnection;
  }

  Future<void> _loadSavedLoginInfo() async {
    final preferenceService = ref.read(preferenceServiceProvider);

    // V2 마이그레이션: 구앱 ID 매핑 처리
    await _handleV2IdMapping(preferenceService);

    // 저장된 ID와 비밀번호 불러오기
    final savedId = preferenceService.getId();
    final savedPassword = await preferenceService.getPassword(savedId ?? '');
    final isSaveId = preferenceService.getIsSaveId();
    final isAutoLogin = preferenceService.getIsAutoLogin();

    logger.i(
        '[LoginScreen] 로그인 정보 로드 시작: isSaveId = $isSaveId, isAutoLogin = $isAutoLogin, savedId = $savedId');

    if (savedId != null) {
      _idController.text = savedId;
    }
    if (savedPassword != null) {
      _passwordController.text = savedPassword;
    }

    setState(() {
      _isSaveId = isSaveId == 'T';
      _isAutoLogin = isAutoLogin == 'T';
    });

    // 디버그 모드인 경우 테스트 계정 정보 자동 입력
    /* if (kDebugMode) {
      _idController.text = 'TPCP00002';
      _passwordController.text = '1234';
      logger.i('[LoginScreen] 디버그 모드: 테스트 계정 정보가 설정되었습니다.');
    }*/
  }

  /// V2 마이그레이션: 구앱 ID → 신규 AppFit ID 매핑
  Future<void> _handleV2IdMapping(PreferenceService preferenceService) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final migrationOldId =
          prefs.getString(V2MigrationService.KEY_MIGRATED_OLD_ID);

      if (migrationOldId == null || migrationOldId.isEmpty) return;

      logger.i('[LoginScreen] V2 마이그레이션 ID 매핑 시작: $migrationOldId');

      final migrationService = V2MigrationService();
      final newId = await migrationService.fetchMappedId(migrationOldId);

      if (newId != null) {
        await preferenceService.saveId(newId);
        logger.i('[LoginScreen] V2 ID 매핑 완료: $migrationOldId → $newId');
      } else {
        logger.w('[LoginScreen] V2 ID 매핑 실패. 구앱 ID 유지: $migrationOldId');
      }

      // 매핑 시도 완료 — 키 제거하여 재실행 방지
      await prefs.remove(V2MigrationService.KEY_MIGRATED_OLD_ID);
    } catch (e, s) {
      logger.e('[LoginScreen] V2 ID 매핑 중 오류', error: e, stackTrace: s);
    }
  }

  Future<void> _saveLoginInfo() async {
    final preferenceService = ref.read(preferenceServiceProvider);

    logger.i('로그인 정보 저장: _isKdsMode=$_isKdsMode');

    // 매장 ID는 항상 대문자로 저장한다. savePassword 키('{id}_password')가
    // 대문자로 저장되어야 자동로그인 조회 시 getPassword(getId())(대문자)와
    // 일치한다. (소문자 로그인 시 비밀번호 키 불일치로 자동로그인이 깨지는 문제 방지)
    final storeId = _idController.text.trim().toUpperCase();

    if (_isSaveId) {
      await preferenceService.saveId(storeId);
    }
    if (_isAutoLogin) {
      await preferenceService.saveId(storeId);
      // 빈 비밀번호는 저장하지 않음 — 빈 문자열이 저장되면 다음 getPassword()에서
      // null을 반환하여 자동로그인이 영구적으로 실패하는 문제 방지
      if (_passwordController.text.isNotEmpty) {
        await preferenceService.savePassword(storeId, _passwordController.text);
      }
    } else {
      await preferenceService.clearLoginInfo();
    }

    await preferenceService.setSaveId(_isSaveId);
    await preferenceService.setAutoLogin(_isAutoLogin);
    await preferenceService.setKdsMode(_isKdsMode);

    logger.i('설정 저장 완료');
  }

  /// 업데이트 체크
  Future<void> _checkForUpdate() async {
    // Windows 는 앱 시작 시 runStartupUpdateFlow() 로 OTA 체크 완료.
    // flutter_downloader 는 Android/iOS 전용이므로 Windows 에서 skip.
    if (Platform.isWindows) {
      await _performAutoLogin();
      return;
    }
    try {
      // 기기 정보 로깅
      String manufacturer = 'unknown';
      String model = 'unknown';
      String androidVersion = 'unknown';
      if (Platform.isAndroid) {
        final deviceInfo = await DeviceInfoPlugin().androidInfo;
        manufacturer = deviceInfo.manufacturer;
        model = deviceInfo.model;
        androidVersion = deviceInfo.version.release;
      }
      logger.i(
          '[OTA] 업데이트 체크 시작 - 기기: $manufacturer $model (Android $androidVersion)');
      logger.i('[OTA] versionUrl: ${OtaConfig.versionUrl}');

      final otaManager = OtaUpdateManager();

      final updateInfo = await otaManager.checkForUpdate(
        versionUrl: OtaConfig.versionUrl,
        downloadUrl: OtaConfig.downloadUrl,
      );

      if (updateInfo == null) {
        logger.w('[OTA] 버전 정보 없음 (updateInfo == null) - 업데이트 체크 생략');
      } else {
        logger.i(
            '[OTA] 버전 확인 완료 - 현재: v${updateInfo.currentVersion}, 최신: v${updateInfo.latestVersion}, 업데이트필요: ${updateInfo.hasUpdate}');
      }

      if (updateInfo != null && updateInfo.hasUpdate && mounted) {
        logger
            .i('[OTA] 업데이트 다이얼로그 표시 - downloadUrl: ${updateInfo.downloadUrl}');
        final shouldDownload = await CommonDialog.showUpdateProgressDialog(
          context: context,
          updateInfo: updateInfo,
          onStartUpdate:
              (downloadUrl, destinationFilename, onEvent, onDone, onError) {
            logger.i(
                '[OTA] 다운로드 시작 - url: $downloadUrl, dest: $destinationFilename');
            otaManager.executeUpdate(
              downloadUrl: downloadUrl,
              destinationFilename: destinationFilename,
              onStatus: (status, progress) {
                logger.d(
                    '[OTA] 다운로드 진행 - status: $status, progress: ${(progress * 100).toStringAsFixed(1)}%');
                onEvent(OtaDownloadEvent(status: status, progress: progress));
              },
              onDone: onDone,
              onError: onError,
            );
          },
          onCancel: () {
            logger.i('[OTA] 사용자 다운로드 취소');
            otaManager.cancelUpdate();
          },
        );

        if (shouldDownload == true) {
          logger.i('[OTA] 업데이트 다운로드 완료 - 설치 진행');
        } else {
          logger.i('[OTA] 업데이트 다이얼로그 닫힘 (shouldDownload: $shouldDownload)');
        }
      }

      // 업데이트 체크 완료 후 자동 로그인 수행
      await _performAutoLogin();
    } catch (e, s) {
      logger.e('[OTA] 업데이트 체크 중 오류 발생', error: e, stackTrace: s);
      await _performAutoLogin();
    }
  }

  /// 자동 로그인 수행
  Future<void> _performAutoLogin() async {
    try {
      final preferenceService = ref.read(preferenceServiceProvider);
      final isAutoLogin = preferenceService.getIsAutoLogin();
      final savedId = preferenceService.getId();

      logger.i(
          '[LoginScreen] _performAutoLogin 시작: isAutoLogin=$isAutoLogin, savedId=$savedId');

      if (isAutoLogin != 'T') {
        logger.i('[LoginScreen] 자동 로그인 설정이 비활성화 상태입니다.');
        return;
      }

      if (savedId == null || savedId.isEmpty) {
        logger.w('[LoginScreen] 저장된 매장 ID가 없어 자동 로그인을 건너뜁니다.');
        return;
      }

      final savedPassword = await preferenceService.getPassword(savedId);

      // 자동 로그인 설정이 되어 있고 저장된 정보가 있다면 로그인 시도
      if (savedPassword != null && savedPassword.isNotEmpty && mounted) {
        logger.i('[LoginScreen] 자동 로그인 조건 충족. 로그인 시도 중... (ID: $savedId)');

        // 인터넷 연결 확인
        final hasConnection = await _checkInternetConnection();
        if (!hasConnection) {
          logger.w('[LoginScreen] 인터넷 연결이 없어 자동 로그인을 중단합니다.');
          return;
        }

        // 자동 로그인 수행
        await _login(isAutoAttempt: true);
      } else {
        logger.w(
            '[LoginScreen] 자동 로그인 실패: 저장된 비밀번호가 없거나 비어 있습니다. (최초 1회 수동 로그인 필요)');
      }
    } catch (e, s) {
      logger.e('[LoginScreen] 자동 로그인 중 예외 발생', error: e, stackTrace: s);
    }
  }

  Future<void> _loadKdsModeSetting() async {
    final preferenceService = ref.read(preferenceServiceProvider);
    final isKdsMode = preferenceService.getKdsMode();
    setState(() {
      _isKdsMode = isKdsMode;
    });
  }

  /// 주방모니터 탭 선택 시 '주문 접수' 설정 안내.
  ///
  /// KDS 모드는 KEY_KDS_ACCEPT_ORDERS 가 OFF(기본값)면 신규 주문을 직접 수신하지
  /// 않으므로, 주방모니터 단독 운영 매장은 로그인 후 설정에서 이 토글을 켜야 한다.
  /// 안내만 하고 모드 선택은 되돌리지 않는다.
  Future<void> _showKdsModeNotice() async {
    if (!mounted) return;
    logger.i('[LoginScreen] 주방모니터 모드 선택 - 주문 접수 설정 안내 표시');
    await CommonDialog.showInfoDialog(
      context: context,
      title: t.login.kds_notice.title,
      content: t.login.kds_notice.content,
    );
  }

  Future<void> _login({bool isAutoAttempt = false}) async {
    // 재진입 가드: 서버 자동전환(disconnect+자격증명 정리)이 스피너 표시보다
    // 먼저 끝나는 구간에서 연타하면 두 번째 로그인 시도가 겹쳐 들어간다.
    if (_isLoading) return;

    logToFile(tag: LogTag.API, message: '로그인시도');

    // 첫 await 이전에 즉시 로딩 상태로 전환해 버튼을 비활성화한다.
    setState(() {
      _isLoading = true;
    });

    try {
      // 인터넷 연결 확인
      final hasConnection = await _checkInternetConnection();
      if (!hasConnection) return;

      // 자동 로그인이 아닌 경우에만 form validation 실행
      if (!_isAutoLogin) {
        if (!_formKey.currentState!.validate()) {
          return;
        }
      }

      // 매장 ID 프리픽스로 서버 환경을 결정한다. 자동 로그인은 저장 ID·저장
      // 환경이 이전 세션에서 이미 정합이므로 개입하지 않는다.
      if (!isAutoAttempt) {
        final canProceed = await _resolveEnvironmentForStoreId(
          _idController.text.trim().toUpperCase(),
        );
        if (!canProceed) return;
      }

      // 로그인 시도 전에 현재 선택된 탭의 모드 설정을 먼저 저장
      await _saveLoginInfo();

      // [FIX] 로그인 ID 대문자 강제 변환 (AppFit 소켓 채널 일치 보장)
      String storeId = _idController.text.trim().toUpperCase();

      final (success, rewardType, errorMessage) = await ref
          .read(authProvider.notifier)
          .login(storeId, _passwordController.text);

      if (success) {
        // 브랜드 전환(로그아웃→다른 브랜드 로그인) 시 캐시형 currentBrandProvider 와
        // 그에 의존하는 provider(soundGraphHook/labelFilterStrategy)가 stale 되지 않도록
        // 무효화한다. 이 시점엔 getId()=새 매장이라 재계산이 올바른 브랜드를 반환한다.
        ref.invalidate(currentBrandProvider);

        // 다른 브랜드로 로그인했는데 이전 브랜드 전용 테마가 저장돼 있으면 기본
        // 테마로 되돌린다(호환 테마/같은 브랜드면 no-op). 색상의 실제 화면 반영은
        // 다음 앱 시작 시점이다(테마 변경은 재시작 기반). 로컬 storeId 사용 —
        // save-id/auto-login OFF 라 getId() 가 비어도 항상 정확한 매장을 가리킴.
        await ref
            .read(brandThemeNotifierProvider.notifier)
            .reconcileForStore(storeId);

        // 업데이트 채널 정책 재조정 (설치 후 최초 로그인 1회, 멱등 플래그로 게이팅).
        // 정책: `sunmiAppStoreUpdate` 브랜드(현재 MHST) + Sunmi 기기 = Sunmi App
        //   Store 채널 → 앱내 자동 OTA 체크 OFF. 그 외 모든 조합(비-MHST·비-Sunmi·
        //   Windows) = OTA 채널 → 자동 체크 ON.
        // 정책당 1회만 실행해 이후 사용자의 수동 토글을 덮어쓰지 않는다. 정책이 바뀌면
        // 기존 마커(KEY_UPDATE_TPCP_OVERRIDE_DONE)와 다른 새 플래그로 기존 기기를
        // 한 번 재조정한다.
        final prefService = ref.read(preferenceServiceProvider);
        if (!prefService.getUpdatePolicyReconciled()) {
          var useAppStore = false;
          if (Platform.isAndroid) {
            final deviceInfo = await DeviceInfoPlugin().androidInfo;
            final isSunmi = deviceInfo.manufacturer.toLowerCase() == 'sunmi';
            final brand = BrandRegistry.resolveOrNull(storeId);
            useAppStore = isSunmi &&
                (brand?.has(BrandFeature.sunmiAppStoreUpdate) ?? false);
            logger.i(
                '[LoginScreen] 업데이트 정책 재조정: sunmi=$isSunmi brand=${brand?.storeIdPrefix ?? '-'} → 자동체크=${!useAppStore}');
          }
          await prefService.setAutoCheckUpdate(!useAppStore);
          await prefService.setUpdatePolicyReconciled(true);
        }

        await _setWindowSoftInputMode('pan');

        StoreModel? storeModel =
            await ref.read(storeProvider.notifier).setStoreModel(storeId);

        ref.read(storeProvider.notifier).setStoreRewardType(rewardType);

        String? storeName;
        if (storeModel != null) {
          storeName = storeModel.name;
        }

        // 기기 관제(Fleet) 대상 매장 재판정. 목록은 OTA 정적 호스트에 있어
        // 앱 재배포 없이 파일럿 범위를 넓히거나 되돌릴 수 있다.
        // 정식 도입 전까지는 FleetConfig.enabled=false 라 조회 없이 즉시 반환한다.
        // 로그인을 막지 않도록 fire-and-forget 이며(조회 실패는 캐시로 판정),
        // pushReplacementNamed 로 이 위젯이 dispose 된 뒤 ref 를 만지지 않도록
        // 필요한 객체를 미리 캡처한다.
        final fleetTargets = ref.read(fleetStoreAllowlistServiceProvider);
        final fleetTargeted = ref.read(fleetTargetedProvider.notifier);
        unawaited(reconcileFleetTarget(fleetTargets, fleetTargeted, storeId));

        if (mounted) {
          // 앱 버전 정보 가져오기 (ref.read 사용)
          final appInfo = await ref.read(appInfoProvider.future);

          logToFile(
              tag: LogTag.API,
              message:
                  '로그인성공: $storeId ${storeName ?? ''}, AppVersion: ${appInfo.version} (${appInfo.buildNumber}), KDS모드: $_isKdsMode');

          // 1. 네비게이션 및 모드 설정을 먼저 처리 (권한 요청보다 우선)
          if (_isKdsMode) {
            // KDS 모드 활성화 전에 로컬 서버 중지
            final localServer = LocalServerService.instance;
            if (localServer != null) {
              await localServer.stopServer();
              logger.i('[LoginScreen] KDS 모드 전환: 로컬 서버 중지 완료');
            }

            // KDS 모드 활성화
            ref.read(kdsModeProvider.notifier).setKdsMode(true);
            Navigator.pushReplacementNamed(context, '/home');

            // 홈화면 진입 후 설정 재로드
            Future.delayed(const Duration(milliseconds: 100), () {
              ref.read(orderProvider.notifier).reloadSettings();
            });
          } else {
            // 일반 모드 활성화
            ref.read(kdsModeProvider.notifier).setKdsMode(false);
            Navigator.pushReplacementNamed(context, '/home');

            // 일반 모드에서도 설정 재로드
            Future.delayed(const Duration(milliseconds: 100), () {
              ref.read(orderProvider.notifier).reloadSettings();
            });
          }

          // 2. 네이티브 저장은 백그라운드에서 실행
          final isKdsMode = ref.read(kdsModeProvider);
          Future.microtask(() async {
            // native에 onDestroy등에서 사용할 storeId 저장
            await _saveStoreIdToNative(
                storeId, isKdsMode, AppFitConfig.baseUrl);
          });
        }
      } else {
        if (mounted) {
          logToFile(
              tag: LogTag.API,
              message: '로그인실패: ${errorMessage ?? '로그인에 실패했습니다.'}');
          CommonDialog.showErrorDialog(
              context: context,
              title: t.login.fail_title,
              content: errorMessage ?? t.login.fail_msg);
        }
      }
    } catch (e, s) {
      logToFile(tag: LogTag.ERROR, message: '로그인 중 오류 발생: $s');
      if (mounted) {
        // raw e.toString()(긴 DioException 영문) 대신 친화 메시지로 표시.
        final content = mapDioErrorToApiException(e, s, context: '로그인').message;
        CommonDialog.showErrorDialog(
            context: context, title: t.login.fail_title, content: content);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // 오버레이 권한 확인 및 요청
  Future<void> _checkAndRequestOverlayPermission() async {
    try {
      // 네이티브 메서드로 더 정확하게 체크 (특히 Android 7 대응)
      final hasPermission =
          await PlatformService.checkOverlayPermissionNative();

      if (!hasPermission && mounted) {
        // 권한이 없으면 안내 메시지 표시 후 권한 요청
        final shouldRequest = await CommonDialog.showConfirmDialog(
          context: context,
          title: t.login.overlay_permission.title,
          content: t.login.overlay_permission.content,
          confirmText: t.login.overlay_permission.set,
          cancelText: t.login.overlay_permission.later,
        );

        if (shouldRequest == true && mounted) {
          // 네이티브 메서드로 권한 요청 화면 이동
          await PlatformService.requestOverlayPermissionNative();
        }
      }
    } catch (e, s) {
      logToFile(tag: LogTag.ERROR, message: '오버레이 권한 확인 중 오류 발생: $s');
    }
  }

  Future<void> _setWindowSoftInputMode(String mode) async {
    try {
      await platform
          .invokeMethod(mode == 'pan' ? 'setAdjustPan' : 'setAdjustResize');
      logger.d("set windowSoftInputMode: '$mode'");
    } on PlatformException catch (e) {
      logger.w("Failed to set windowSoftInputMode: '${e.message}'.");
    }
  }

  Future<void> _saveStoreIdToNative(
      String storeId, bool isKdsMode, String mainURL) async {
    // 브랜드 slug(assetFolder)를 네이티브로 전달해 듀얼모니터 콘텐츠를
    // res/raw·res/drawable 에서 getIdentifier 로 찾게 한다. 미상 매장은 빈 slug
    // → 검은 화면(tpcp 폴백을 쓰지 않도록 resolveOrNull 사용).
    final slug = BrandRegistry.resolveOrNull(storeId)?.assetFolder ?? '';
    try {
      await platform.invokeMethod('saveStoreIdToNative', {
        'storeId': storeId,
        'isKdsMode': isKdsMode,
        'mainURL': mainURL,
        'slug': slug,
      });
    } on PlatformException catch (e) {
      logger.w("Failed to _saveStoreIdToNative: '${e.message}'.");
    }
  }

  // ──── UI 빌더 메서드 ──────────────────────────────────────────────────────

  Widget _buildFormPanel() {
    final t = Translations.of(context);
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(AppSpacing.s32),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(t.login.title, style: AppTextStyles.title),
              const SizedBox(height: AppSpacing.s24),

              // 아이디 입력 필드
              TextFormField(
                controller: _idController,
                decoration: AppStyles.filledInputDecoration(
                  labelText: t.login.id_label,
                  prefixIcon: const Icon(Icons.person),
                ),
                keyboardType: TextInputType.text,
                textInputAction: TextInputAction.next,
                // 매장 ID는 대문자로만 다룬다. 입력 단계에서 대문자로 강제하여
                // 토큰 캐시 shopCode / 소켓 채널 / 비밀번호 저장 키가 항상
                // 대문자 ID로 일치하도록 보장한다.
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  TextInputFormatter.withFunction(
                    (oldValue, newValue) => newValue.copyWith(
                      text: newValue.text.toUpperCase(),
                    ),
                  ),
                ],
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return t.login.id_placeholder;
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.s16),

              // 비밀번호 입력 필드
              TextFormField(
                controller: _passwordController,
                decoration: AppStyles.filledInputDecoration(
                  labelText: t.login.pw_label,
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  ),
                ),
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return t.login.pw_placeholder;
                  }
                  return null;
                },
                onFieldSubmitted: (_) => _login(),
              ),
              const SizedBox(height: AppSpacing.s12),

              // 체크박스 영역
              Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Transform.scale(
                    scale: 1.3,
                    child: Checkbox(
                      value: _isSaveId,
                      onChanged: (value) {
                        setState(() {
                          _isSaveId = value ?? false;
                        });
                      },
                      shape: const CircleBorder(),
                      fillColor: WidgetStateProperty.resolveWith<Color>(
                        (Set<WidgetState> states) {
                          if (states.contains(WidgetState.selected)) {
                            return AppStyles.green100;
                          }
                          return Colors.white;
                        },
                      ),
                    ),
                  ),
                  Text(t.login.save_id, style: AppTextStyles.body),
                  const SizedBox(width: AppSpacing.s16),
                  Transform.scale(
                    scale: 1.3,
                    child: Checkbox(
                      value: _isAutoLogin,
                      onChanged: (value) {
                        setState(() {
                          _isAutoLogin = value ?? false;
                          if (_isAutoLogin) {
                            _isSaveId = true;
                          }
                        });
                      },
                      shape: const CircleBorder(),
                      fillColor: WidgetStateProperty.resolveWith<Color>(
                        (Set<WidgetState> states) {
                          if (states.contains(WidgetState.selected)) {
                            return AppStyles.green100;
                          }
                          return Colors.white;
                        },
                      ),
                    ),
                  ),
                  Text(t.login.auto_login, style: AppTextStyles.body),
                ],
              ),
              const SizedBox(height: AppSpacing.s20),

              // 로그인 버튼 — 텍스트 필드 변경 시 버튼만 리빌드되도록 ListenableBuilder 사용
              ListenableBuilder(
                listenable:
                    Listenable.merge([_idController, _passwordController]),
                builder: (context, _) => ElevatedButton(
                  onPressed: (_idController.text.trim().isEmpty ||
                          _passwordController.text.trim().isEmpty ||
                          _isLoading)
                      ? null
                      : _login,
                  style: AppStyles.primaryButton(
                    minimumSize: const Size.fromHeight(52),
                  ).copyWith(
                    backgroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.disabled)) {
                        return AppStyles.gray4;
                      }
                      return AppStyles.kMainColor;
                    }),
                    textStyle: WidgetStateProperty.all(
                      AppTextStyles.titleSm,
                    ),
                  ),
                  child: _isLoading
                      ? const AppLoadingIndicator(
                          size: 20,
                          color: Colors.white,
                          strokeWidth: 2,
                        )
                      : Text(
                          t.login.button,
                          style: AppTextStyles.titleSm
                              .copyWith(color: Colors.white),
                        ),
                ),
              ),
              const SizedBox(height: AppSpacing.s24),

              // 모드 선택 세그먼티드 탭
              _ModeSegmentedTabs(
                isKdsMode: _isKdsMode,
                onChanged: (isKds) {
                  setState(() => _isKdsMode = isKds);
                  if (isKds) {
                    _showKdsModeNotice();
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeroPanel() {
    final locale = ref.watch(localeNotifierProvider);

    final String heroSubTitle = switch (locale) {
      AppLocale.ko => '주문 에이전트',
      AppLocale.en => 'Order Agent',
      AppLocale.ja => 'オーダーエージェント',
    };

    final brand = AppStyles.activeBrand;
    return Container(
      decoration: BoxDecoration(
        color: brand.loginGradient == null ? brand.loginBackground : null,
        gradient: brand.loginGradient,
      ),
      padding: const EdgeInsets.all(AppSpacing.s32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 로그인 로고는 매머드 flavor 빌드면 선택된 테마(기본 테마 포함)와
            // 무관하게 항상 매머드로 고정한다 — 런처 아이콘/이름과 같은 아티팩트
            // 정체성 요소로 취급(색상 테마는 여전히 activeBrand 를 따름).
            BuildBrand.isMammoth
                ? Image.asset(
                    'assets/images/brand/mammoth/logo.png',
                    height: 120,
                    fit: BoxFit.contain,
                  )
                : BrandLogo(
                    height: 120,
                    fallbackText: 'AppFit',
                    fallbackStyle: AppTextStyles.display.copyWith(
                      color: brand.onLoginBackground,
                      fontSize: 40,
                    ),
                  ),
            const SizedBox(height: AppSpacing.s32),
            Text(
              heroSubTitle,
              style: AppTextStyles.title.copyWith(
                color: brand.onLoginBackground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSplitCard() {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.bLg,
        boxShadow: AppElevation.card,
      ),
      child: ClipRRect(
        borderRadius: AppRadius.bLg,
        child: SizedBox.expand(
          child: Row(
            children: [
              Expanded(flex: 5, child: _buildHeroPanel()),
              Expanded(flex: 4, child: _buildFormPanel()),
            ],
          ),
        ),
      ),
    );
  }

  // 언어 선택 위젯
  Widget _buildLanguageSwitcher() {
    final currentLocale = ref.watch(localeNotifierProvider);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.bSm,
        boxShadow: AppElevation.soft,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s4,
        vertical: AppSpacing.s4,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: AppLocale.values.map((locale) {
          final isSelected = currentLocale == locale;
          return GestureDetector(
            onTap: () {
              ref.read(localeNotifierProvider.notifier).changeLocale(locale);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s12,
                vertical: AppSpacing.s8,
              ),
              decoration: BoxDecoration(
                color: isSelected ? AppStyles.kMainColor : Colors.transparent,
                borderRadius: AppRadius.bSm,
              ),
              child: Text(
                _getLocaleDisplay(locale),
                style: AppTextStyles.bodySm.copyWith(
                  color: isSelected ? Colors.white : AppStyles.gray6,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  String _envLabel(String env) => switch (env) {
        'live' => 'KR · Live',
        'japanLive' => 'JP · Live',
        'dev' => 'Dev',
        'staging' => 'Stage',
        _ => env,
      };

  /// 우상단 배지용 축약 라벨. 운영 환경은 지역(KR/JP)만 표시한다.
  String _envBadgeLabel(String env) => switch (env) {
        'live' => 'KR',
        'japanLive' => 'JP',
        _ => _envLabel(env),
      };

  /// 현재 서버 환경 배지(우상단, 릴리즈 포함 항상 표시). 탭하면 서버선택
  /// 다이얼로그가 열린다 — 릴리즈는 live/japanLive/staging 3종, 개발은 4종.
  Widget _buildEnvBadge() {
    return GestureDetector(
      onTap: _showEnvSelectDialog,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s8,
          vertical: AppSpacing.s4,
        ),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: AppRadius.bSm,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.24),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _envBadgeLabel(_selectedEnv),
              style: AppTextStyles.caption.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: AppSpacing.s4),
            const Icon(Icons.arrow_drop_down, size: 14, color: Colors.white),
          ],
        ),
      ),
    );
  }

  Widget _buildExitButton(BuildContext context) {
    final t = Translations.of(context);
    return AppIconAction(
      icon: Icons.power_settings_new,
      color: Colors.white,
      tooltip: t.app_bar.exit_app,
      onPressed: () {
        logToFile(
          tag: LogTag.UI_ACTION,
          message: '로그인 화면 앱 종료 버튼 터치',
        );
        _showExitConfirmationDialog(context);
      },
    );
  }

  Future<void> _showExitConfirmationDialog(BuildContext context) async {
    final t = Translations.of(context);
    final shouldExit = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
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
            child: Text(t.app_bar.exit_app_desc, style: AppTextStyles.body),
          ),
        ),
        actionsPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s24,
          vertical: AppSpacing.s24,
        ),
        actions: [
          ElevatedButton(
            style: AppStyles.outlinedButton(minimumSize: const Size(100, 45)),
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Text(t.common.cancel),
          ),
          ElevatedButton(
            style: AppStyles.primaryButton(minimumSize: const Size(100, 45)),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: Text(t.dialog.exit.confirm),
          ),
        ],
      ),
    );

    if (shouldExit == true) {
      logToFile(
        tag: LogTag.UI_ACTION,
        message: '로그인 화면 앱 종료 다이얼로그 -> 종료',
      );
      await PlatformService.exitApp();
    } else {
      logToFile(
        tag: LogTag.UI_ACTION,
        message: '로그인 화면 앱 종료 다이얼로그 -> 취소',
      );
    }
  }

  Future<void> _showEnvSelectDialog() async {
    final t = Translations.of(context);
    // 릴리즈 출고본은 dev 를 제외한 운영+staging 3종을 노출한다. dev 는 개발 빌드 전용.
    const envOptions = AppEnv.showInternalUi
        ? ['dev', 'staging', 'live', 'japanLive']
        : ['staging', 'live', 'japanLive'];

    final selected = await showDialog<String>(
      context: context,
      builder: (dialogCtx) {
        String tempSelected = _selectedEnv;
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              shape: const RoundedRectangleBorder(borderRadius: AppRadius.bLg),
              title: Row(
                children: [
                  Icon(
                    Icons.dns_outlined,
                    color: AppStyles.kMainColor,
                    size: 28,
                  ),
                  const SizedBox(width: AppSpacing.s12),
                  const Text('서버 환경 선택', style: AppTextStyles.title),
                ],
              ),
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: envOptions.map((env) {
                    final isSelected = env == tempSelected;
                    return InkWell(
                      onTap: () => setLocal(() => tempSelected = env),
                      borderRadius: AppRadius.bSm,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.s8,
                          vertical: AppSpacing.s12,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isSelected
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_off,
                              size: 26,
                              color: isSelected
                                  ? AppStyles.kMainColor
                                  : AppStyles.gray6,
                            ),
                            const SizedBox(width: AppSpacing.s12),
                            Text(
                              _envLabel(env),
                              style: AppTextStyles.body.copyWith(
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                                color: isSelected
                                    ? AppStyles.kMainColor
                                    : AppStyles.gray9,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              actionsPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s24,
                vertical: AppSpacing.s24,
              ),
              actions: [
                ElevatedButton(
                  style: AppStyles.outlinedButton(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s20,
                      vertical: AppSpacing.s12,
                    ),
                    minimumSize: const Size(100, 45),
                  ),
                  onPressed: () => Navigator.of(dialogCtx).pop(null),
                  child: Text(
                    t.common.cancel,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ElevatedButton(
                  style: AppStyles.primaryButton(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s20,
                      vertical: AppSpacing.s12,
                    ),
                    minimumSize: const Size(100, 45),
                  ),
                  onPressed: () => Navigator.of(dialogCtx).pop(tempSelected),
                  child: Text(
                    t.common.confirm,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (selected == null) return;
    if (selected == _selectedEnv) {
      // 변경이 없어도 명시적 확인으로 기록한다 — 미등록 프리픽스 로그인의
      // 1회 지정 다이얼로그가 같은 선택을 반복해서 묻지 않게 한다.
      await ref
          .read(preferenceServiceProvider)
          .setEnvironmentManualOverride(true);
      return;
    }

    await _applyEnvironment(selected, reason: '수동 선택');
  }

  /// 서버 환경 전환을 적용한다.
  ///
  /// 이전 환경 잔존 상태 제거: WebSocket 해제 → 환경 저장 → AppFitConfig 재구성
  /// → 자격증명/토큰 정리 → Provider invalidate. (서버 전환 후 재로그인 크래시
  /// 방어 시퀀스 — 순서 변경 금지)
  Future<void> _applyEnvironment(String env, {required String reason}) async {
    ref.read(authProvider.notifier).unauthenticate();

    final preferenceService = ref.read(preferenceServiceProvider);
    await preferenceService.setEnvironment(env);
    // 환경이 명시적으로 확정됐음을 기록한다(설정 화면 경로와 동일 정책).
    // 미등록 프리픽스 로그인의 1회 지정 다이얼로그 재출현을 막는다.
    await preferenceService.setEnvironmentManualOverride(true);

    final newEnvironment = switch (env) {
      'live' => AppFitEnvironment.live,
      'japanLive' => AppFitEnvironment.japanLive,
      'dev' => AppFitEnvironment.dev,
      'staging' => AppFitEnvironment.staging,
      _ => AppFitEnvironment.live,
    };
    AppFitConfig.configure(
      environment: newEnvironment,
      requestSource: 'ORDER_AGENT',
    );

    // Sentry environment 태그는 부팅 시 1회만 세팅되므로, 런타임 환경 전환 시
    // 여기서 다시 반영하지 않으면 알림에 이전 환경이 그대로 찍힌다.
    if (AppEnv.hasSentryDsn) {
      MonitoringService.instance
          .updateContext(await buildOrderAgentMonitoringContext());
    }

    final tokenManager = ref.read(appfit_providers.appFitTokenManagerProvider);
    await tokenManager.clearToken();
    await tokenManager.clearPassword();

    final secureStorage = SecureStorageService();
    await secureStorage.delete(SecureStorageService.appFitProjectId);
    await secureStorage.delete(SecureStorageService.appFitProjectApiKey);

    await preferenceService.clearLoginInfo();

    ref.invalidate(appfit_providers.appFitTokenManagerProvider);
    ref.invalidate(appfit_providers.appFitDioProvider);
    // appFitNotifierServiceProvider 는 invalidate 금지:
    // AppFitNotifierNotifier._coreService 가 `late final` 이라 build() 재실행 시
    // LateInitializationError 발생. disconnect() 만으로 이전 연결 정리 충분하며
    // 재로그인 시 같은 인스턴스에 새 shopCode/projectId/apiKey 로 connect() 호출.

    // 매장 스코프 상태 초기화(로그아웃 경로와 동일 정본). 이 메서드는 sign-in 전에만
    // 호출되므로(수동 선택 / 프리픽스 자동 전환) 진행 중인 로그인 상태를 건드리지 않는다.
    //
    // OrderProvider.cleanupOnLogout() 은 여기서 호출하지 않는다. 로그인 화면 시점의
    // OrderProvider 는 (a) 아직 생성 전이거나 (b) 로그아웃 때 이미 정리된 상태다.
    // read(orderProvider.notifier) 하면 정리하려다 오히려 소켓/타이머를 세우며
    // 생성시켜 버린다. 로그인 후 정리는 settings 의 환경 변경 경로가 담당한다.
    resetStoreScopedProviders(ref);

    if (mounted) {
      setState(() => _selectedEnv = env);
    }
    logger.i('[LoginScreen] 서버 환경 전환($reason): → $env');
  }

  /// 로그인 직전 매장 ID 프리픽스로 서버 환경을 결정한다.
  ///
  /// 공통 아티팩트는 live/japanLive 운영 세션에서만 동작한다(dev/staging
  /// 개발 테스트 보호). 비대칭 주의: live 에서 MHST(매머드 스테이징) 를
  /// 입력하면 staging 으로 넘어가지만, 그 뒤 staging 세션에서 MMTH 를
  /// 입력해도 자동으로 돌아오지 않는다 — 개발자가 고른 staging 을 앱이
  /// 임의로 뺏지 않기 위함이다. 되돌리려면 로그인 화면의 서버 선택에서
  /// 직접 고른다.
  ///
  /// 매머드 전용 아티팩트는 이 보호가 필요 없다(개발자가 아니라 매장
  /// 직원만 쓴다 — 서버 선택 배지 자체를 숨겼다). 그래서 현재 선택된 서버와
  /// 무관하게 완전 양방향 자동 전환한다: MHST 로그인 → staging, MMTH
  /// 로그인 → live.
  /// - 등록 브랜드: 그 매장 ID 프리픽스의 서버 환경(BrandMeta.environmentFor)과
  ///   현재 선택이 다르면 자동 전환한다. 같은 브랜드라도 프리픽스마다 서버가
  ///   다를 수 있다(매머드: MMTH=live, MHST=staging).
  /// - 미등록 프리픽스: 명시 선택 이력(manual override)이 없으면 서버선택
  ///   다이얼로그로 1회 지정을 요구한다. 취소하면 false → 로그인 중단.
  Future<bool> _resolveEnvironmentForStoreId(String storeId) async {
    if (!BuildBrand.isMammoth &&
        _selectedEnv != 'live' &&
        _selectedEnv != 'japanLive') {
      return true;
    }

    final brand = BrandRegistry.resolveOrNull(storeId);
    if (brand != null) {
      final target = brand.environmentFor(storeId);
      if (target != _selectedEnv) {
        await _applyEnvironment(target,
            reason: '브랜드 ${brand.storeIdPrefix} 프리픽스 자동');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Server → ${_envLabel(target)}')),
          );
        }
      }
      return true;
    }

    final preferenceService = ref.read(preferenceServiceProvider);
    if (preferenceService.getEnvironmentManualOverride()) return true;

    // 미등록 프리픽스 + 명시 이력 없음 → 서버를 1회 지정하게 한다.
    await _showEnvSelectDialog();
    return preferenceService.getEnvironmentManualOverride();
  }

  void _onDevAreaTap() {
    final now = DateTime.now();
    if (_lastDevTap != null &&
        now.difference(_lastDevTap!).inMilliseconds > 1000) {
      _devTapCount = 0;
    }
    _lastDevTap = now;
    _devTapCount++;

    if (_devTapCount >= 5) {
      _devTapCount = 0;
      _showDevAccountDialog();
    }
  }

  void _showDevAccountDialog() {
    const accounts = [
      ('매머드커피 테스트매장', 'MHST00001'),
      ('도쿄플라트 테스트매장', 'TPCP00002'),
    ];

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => SimpleDialog(
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.bLg),
        title: const Text('개발 계정 선택'),
        titleTextStyle: AppTextStyles.title,
        children: [
          ...accounts.map((account) {
            final (name, id) = account;
            return SimpleDialogOption(
              onPressed: () {
                Navigator.pop(context);
                setState(() {
                  _idController.text = id;
                  _passwordController.text = '1234';
                });
              },
              child: Text('$name ($id)', style: AppTextStyles.body),
            );
          }),
          const Divider(color: AppStyles.gray3),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context),
            child: Center(
              child: Text(
                '닫기',
                style: AppTextStyles.body.copyWith(color: AppStyles.gray6),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getLocaleDisplay(AppLocale locale) {
    switch (locale) {
      case AppLocale.ko:
        return '한국어';
      case AppLocale.en:
        return 'ENG';
      case AppLocale.ja:
        return '日本語';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          // 배경: 브랜드 그라데이션(또는 단색 폴백)
          Builder(builder: (_) {
            final brand = AppStyles.activeBrand;
            return Container(
              decoration: BoxDecoration(
                color:
                    brand.loginGradient == null ? brand.loginBackground : null,
                gradient: brand.loginGradient,
              ),
            );
          }),

          SafeArea(
            child: GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              behavior: HitTestBehavior.translucent,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 880,
                    maxHeight: 560,
                  ),
                  child: _buildSplitCard(),
                ),
              ),
            ),
          ),

          // 개발 계정 선택 (좌측 하단 연타) — 릴리즈 산출물에서는 숨김
          if (AppEnv.showInternalUi)
            Positioned(
              bottom: 0,
              left: 0,
              child: GestureDetector(
                onTap: _onDevAreaTap,
                behavior: HitTestBehavior.opaque,
                child: const SizedBox(width: 80, height: 80),
              ),
            ),

          // 종료 버튼 + 언어 선택 위젯 + 서버 환경 표시 (우측 상단)
          Positioned(
            top: AppSpacing.s20,
            right: AppSpacing.s20,
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _buildLanguageSwitcher(),
                      const SizedBox(width: AppSpacing.s4),
                      _buildExitButton(context),
                    ],
                  ),
                  // 매머드 전용 아티팩트는 서버 선택을 노출하지 않는다(매장이
                  // 고를 이유가 없는 항목). 개발 빌드에서는 QA 가 staging 을
                  // 오갈 수 있도록 유지 — 릴리즈 산출물에서만 숨김.
                  if (!BuildBrand.isMammoth || AppEnv.showInternalUi) ...[
                    const SizedBox(height: AppSpacing.s4),
                    _buildEnvBadge(),
                  ],
                ],
              ),
            ),
          ),

          // Windows frameless 창: 앱바가 없으므로 상단 40px을 투명 드래그 핸들로 배치.
          // translucent 동작이라 하위 위젯의 탭은 그대로 전달된다.
          if (Platform.isWindows)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 40,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onPanStart: (_) => windowManager.startDragging(),
                onDoubleTap: () =>
                    WindowsBubbleService.instance.restoreToDefaultPosition(),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── 모드 선택 세그먼티드 탭 ────────────────────────────────────────────────

class _ModeSegmentedTabs extends StatelessWidget {
  final bool isKdsMode;
  final void Function(bool isKds) onChanged;

  const _ModeSegmentedTabs({
    required this.isKdsMode,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    return Container(
      decoration: const BoxDecoration(
        color: AppStyles.gray2,
        borderRadius: AppRadius.bSm,
      ),
      padding: const EdgeInsets.all(AppSpacing.s4),
      child: Row(
        children: [
          Expanded(
            child: _tab(
              label: t.login.tabs.order,
              icon: Icons.point_of_sale,
              selected: !isKdsMode,
              onTap: () => onChanged(false),
            ),
          ),
          Expanded(
            child: _tab(
              label: t.login.tabs.kitchen,
              icon: Icons.display_settings,
              selected: isKdsMode,
              onTap: () => onChanged(true),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tab({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s12),
        decoration: selected
            ? const BoxDecoration(
                color: Colors.white,
                borderRadius: AppRadius.bSm,
                boxShadow: AppElevation.soft,
              )
            : const BoxDecoration(
                color: Colors.transparent,
                borderRadius: AppRadius.bSm,
              ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? AppStyles.kMainColor : AppStyles.gray6,
            ),
            const SizedBox(width: AppSpacing.s8),
            Text(
              label,
              style: AppTextStyles.body.copyWith(
                color: selected ? AppStyles.kMainColor : AppStyles.gray6,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
