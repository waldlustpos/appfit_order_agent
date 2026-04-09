import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:appfit_core/appfit_core.dart'; // AppFitConfig (패키지)
import 'package:appfit_order_agent/models/store_model.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../utils/logger.dart';
import '../services/platform_service.dart';
import '../services/preference_service.dart';
import '../services/migration/v2_migration_service.dart';
import '../services/appfit/appfit_providers.dart' as appfit_providers;
import '../providers/auth_provider.dart';
import '../providers/store_provider.dart';

import '../widgets/common/common_dialog.dart';
import '../constants/app_styles.dart';
import '../services/local_server_service.dart';
import '../providers/providers.dart';
import '../providers/kds_unified_providers.dart';
import '../providers/order_provider.dart';
import 'package:flutter/foundation.dart'; // For kDebugMode if needed
import 'package:appfit_order_agent/i18n/strings.g.dart';
import 'package:appfit_order_agent/providers/locale_provider.dart';
import 'package:appfit_order_agent/utils/print/label_painter.dart';
import 'package:appfit_order_agent/config/ota_config.dart';
import 'package:device_info_plus/device_info_plus.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

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
  bool _isSubDisplay = false;
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

          if(identification.isNotEmpty) {
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
    _selectedEnv = PreferenceService().getEnvironment();

    // 텍스트 필드 리스너는 불필요 — 로그인 버튼에서 ListenableBuilder로 처리

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // 로그인 정보 로드
      await _loadSavedLoginInfo();
      await _loadSubDisplaySetting();
      await _setWindowSoftInputMode('resize');

      // 화면이 표시된 후 권한 요청
      if (mounted) {
        await _requestAllPermissions();
      }

      // 업데이트 체크 (권한 요청 후) - 자동 업데이트 설정에 따라 게이팅
      if (mounted) {
        final preferenceService = PreferenceService();
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
      );
    }

    return hasConnection;
  }

  Future<void> _loadSavedLoginInfo() async {
    final preferenceService = PreferenceService();

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
    final preferenceService = PreferenceService();

    logger.i('로그인 정보 저장: _isSubDisplay=$_isSubDisplay');

    final storeId = _idController.text.trim();

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
    await preferenceService.setSubDisplay(_isSubDisplay);

    logger.i('설정 저장 완료');
  }

  /// 업데이트 체크
  Future<void> _checkForUpdate() async {
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
      logger.i('[OTA] 업데이트 체크 시작 - 기기: $manufacturer $model (Android $androidVersion)');
      logger.i('[OTA] versionUrl: ${OtaConfig.versionUrl}');

      final otaManager = OtaUpdateManager();

      final updateInfo = await otaManager.checkForUpdate(
        versionUrl: OtaConfig.versionUrl,
        downloadUrl: OtaConfig.downloadUrl,
      );

      if (updateInfo == null) {
        logger.w('[OTA] 버전 정보 없음 (updateInfo == null) - 업데이트 체크 생략');
      } else {
        logger.i('[OTA] 버전 확인 완료 - 현재: v${updateInfo.currentVersion}, 최신: v${updateInfo.latestVersion}, 업데이트필요: ${updateInfo.hasUpdate}');
      }

      if (updateInfo != null && updateInfo.hasUpdate && mounted) {
        logger.i('[OTA] 업데이트 다이얼로그 표시 - downloadUrl: ${updateInfo.downloadUrl}');
        final shouldDownload = await CommonDialog.showUpdateProgressDialog(
          context: context,
          updateInfo: updateInfo,
          onStartUpdate:
              (downloadUrl, destinationFilename, onEvent, onDone, onError) {
            logger.i('[OTA] 다운로드 시작 - url: $downloadUrl, dest: $destinationFilename');
            otaManager.executeUpdate(
              downloadUrl: downloadUrl,
              destinationFilename: destinationFilename,
              onStatus: (status, progress) {
                logger.d('[OTA] 다운로드 진행 - status: $status, progress: ${(progress * 100).toStringAsFixed(1)}%');
                onEvent(OtaDownloadEvent(status: status, progress: progress));
              },
              onDone: onDone,
              onError: onError,
            );
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
      final preferenceService = PreferenceService();
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
        await _login();
      } else {
        logger.w(
            '[LoginScreen] 자동 로그인 실패: 저장된 비밀번호가 없거나 비어 있습니다. (최초 1회 수동 로그인 필요)');
      }
    } catch (e, s) {
      logger.e('[LoginScreen] 자동 로그인 중 예외 발생', error: e, stackTrace: s);
    }
  }

  Future<void> _loadSubDisplaySetting() async {
    final preferenceService = PreferenceService();
    final isSubDisplay = preferenceService.getSubDisplay();
    setState(() {
      _isSubDisplay = isSubDisplay;
    });
  }

  Future<void> _login() async {
    logToFile(tag: LogTag.API, message: '로그인시도');

    // 인터넷 연결 확인
    final hasConnection = await _checkInternetConnection();
    if (!hasConnection) return;

    // 자동 로그인이 아닌 경우에만 form validation 실행
    if (!_isAutoLogin) {
      if (!_formKey.currentState!.validate()) {
        return;
      }
    }

    // 로그인 시도 전에 현재 선택된 탭의 모드 설정을 먼저 저장
    await _saveLoginInfo();

    setState(() {
      _isLoading = true;
    });

    try {
      // [FIX] 로그인 ID 대문자 강제 변환 (AppFit 소켓 채널 일치 보장)
      String storeId = _idController.text.trim().toUpperCase();

      final (success, rewardType, errorMessage) = await ref
          .read(authProvider.notifier)
          .login(storeId, _passwordController.text);

      if (success) {
        // TPCP 오버라이드: SUNMI + TPCP 매장은 자동 업데이트 체크 ON 유지
        final prefService = PreferenceService();
        if (!prefService.getUpdateTpcpOverrideDone()) {
          if (storeId.startsWith('TPCP') && Platform.isAndroid) {
            final deviceInfo = await DeviceInfoPlugin().androidInfo;
            if (deviceInfo.manufacturer.toLowerCase() == 'sunmi') {
              await prefService.setAutoCheckUpdate(true);
              logger.i('[LoginScreen] TPCP+SUNMI 감지: 자동 업데이트 체크 ON으로 오버라이드');
            }
          }
          await prefService.setUpdateTpcpOverrideDone(true);
        }

        await _setWindowSoftInputMode('pan');

        StoreModel? storeModel =
            await ref.read(storeProvider.notifier).setStoreModel(storeId);

        ref.read(storeProvider.notifier).setStoreRewardType(rewardType);

        String? storeName;
        if (storeModel != null) {
          storeName = storeModel.name;
        }

        if (mounted) {
          // 앱 버전 정보 가져오기 (ref.read 사용)
          final appInfo = await ref.read(appInfoProvider.future);

          logToFile(
              tag: LogTag.API,
              message:
                  '로그인성공: $storeId ${storeName ?? ''}, AppVersion: ${appInfo.version} (${appInfo.buildNumber}), 서브디스플레이: $_isSubDisplay');

          // 1. 네비게이션 및 모드 설정을 먼저 처리 (권한 요청보다 우선)
          if (_isSubDisplay) {
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
        CommonDialog.showErrorDialog(
            context: context, title: t.login.fail_title, content: e.toString());
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
    try {
      await platform.invokeMethod('saveStoreIdToNative',
          {'storeId': storeId, 'isKdsMode': isKdsMode, 'mainURL': mainURL});
    } on PlatformException catch (e) {
      logger.w("Failed to _saveStoreIdToNative: '${e.message}'.");
    }
  }

  // 로그인 폼 위젯
  Widget _buildLoginForm({required GlobalKey<FormState> formKey}) {
    return Form(
      key: formKey,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // KDS 모드 토글 상단 배치 (새로운 UI 디자인)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            margin: const EdgeInsets.only(bottom: 24),
            decoration: BoxDecoration(
              color: _isSubDisplay
                  ? AppStyles.kMainColor.withValues(alpha: 0.1)
                  : Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _isSubDisplay ? AppStyles.kMainColor : Colors.grey[300]!,
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.display_settings,
                      color: _isSubDisplay
                          ? AppStyles.kMainColor
                          : Colors.grey[600],
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '주방모니터(KDS) 전용 로그인',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight:
                            _isSubDisplay ? FontWeight.bold : FontWeight.w600,
                        color: _isSubDisplay
                            ? AppStyles.kMainColor
                            : Colors.grey[800],
                      ),
                    ),
                  ],
                ),
                Switch(
                  value: _isSubDisplay,
                  onChanged: (value) {
                    setState(() {
                      _isSubDisplay = value;
                    });
                  },
                  activeColor: AppStyles.kMainColor,
                  inactiveThumbColor: Colors.grey[400],
                  inactiveTrackColor: Colors.grey[300],
                ),
              ],
            ),
          ),

          // 아이디 입력 필드
          TextFormField(
            controller: _idController,
            decoration: AppStyles.filledInputDecoration(
              labelText: t.login.id_label,
              prefixIcon: const Icon(Icons.person),
            ),
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.next,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return t.login.id_placeholder;
              }
              return null;
            },
          ),
          const SizedBox(height: 16),

          // 비밀번호 입력 필드
          TextFormField(
            controller: _passwordController,
            decoration: AppStyles.filledInputDecoration(
              labelText: t.login.pw_label,
              prefixIcon: const Icon(Icons.lock),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
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
          const SizedBox(height: 24),

          // 로그인 버튼 — 텍스트 필드 변경 시 버튼만 리빌드되도록 ListenableBuilder 사용
          ListenableBuilder(
            listenable: Listenable.merge([_idController, _passwordController]),
            builder: (context, _) => ElevatedButton(
              onPressed: (_idController.text.trim().isEmpty ||
                      _passwordController.text.trim().isEmpty ||
                      _isLoading)
                  ? null
                  : _login,
              style: AppStyles.primaryButton(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ).copyWith(
                backgroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.disabled)) {
                    return AppStyles.gray4;
                  }
                  return AppStyles.kMainColor;
                }),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      t.login.button,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: Colors.white),
                    ),
            ),
          ),
          const SizedBox(height: 16),

          // 체크박스 영역
          Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Transform.scale(
                    scale: 1.3, // 체크박스 크기 30% 증가
                    child: Checkbox(
                      value: _isSaveId,
                      onChanged: (value) {
                        setState(() {
                          _isSaveId = value ?? false;
                        });
                      },
                      shape: const CircleBorder(), // 원형 디자인
                      fillColor: WidgetStateProperty.resolveWith<Color>(
                        (Set<WidgetState> states) {
                          if (states.contains(WidgetState.selected)) {
                            return AppStyles.green100; // green100 색상
                          }
                          return Colors.white;
                        },
                      ),
                    ),
                  ),
                  Text(t.login.save_id, style: const TextStyle(fontSize: 15)),
                  const SizedBox(width: 16),
                  Transform.scale(
                    scale: 1.3, // 체크박스 크기 30% 증가
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
                      shape: const CircleBorder(), // 원형 디자인
                      fillColor: WidgetStateProperty.resolveWith<Color>(
                        (Set<WidgetState> states) {
                          if (states.contains(WidgetState.selected)) {
                            return AppStyles.green100; // green100 색상
                          }
                          return Colors.white;
                        },
                      ),
                    ),
                  ),
                  Text(t.login.auto_login,
                      style: const TextStyle(fontSize: 15)),
                ],
              ),
            ],
          ),

        ],
      ),
    );
  }

  // 언어 선택 위젯
  Widget _buildLanguageSwitcher() {
    final currentLocale = ref.watch(localeNotifierProvider);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: AppLocale.values.map((locale) {
          final isSelected = currentLocale == locale;
          return GestureDetector(
            onTap: () {
              ref.read(localeNotifierProvider.notifier).changeLocale(locale);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? AppStyles.kMainColor : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                _getLocaleDisplay(locale),
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.grey[600],
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 12,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  String _envLabel(String env) => switch (env) {
        'live' => 'Live',
        'japanLive' => 'JP Live',
        'dev' => 'Dev',
        'staging' => 'Stage',
        _ => env,
      };

  Widget _buildEnvBadge() {
    return GestureDetector(
      onTap: _showEnvSelectDialog,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _envLabel(_selectedEnv),
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withOpacity(0.6),
            ),
          ),
          const SizedBox(width: 2),
          Icon(
            Icons.arrow_drop_down,
            size: 14,
            color: Colors.white.withOpacity(0.6),
          ),
        ],
      ),
    );
  }

  Future<void> _showEnvSelectDialog() async {
    final envOptions = ['dev', 'staging', 'live', 'japanLive'];

    final selected = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('서버 환경 선택'),
        children: envOptions.map((env) {
          final isSelected = env == _selectedEnv;
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(context, env),
            child: Row(
              children: [
                Icon(
                  isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                  size: 20,
                  color: isSelected ? Theme.of(context).primaryColor : Colors.grey,
                ),
                const SizedBox(width: 12),
                Text(
                  _envLabel(env),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );

    if (selected == null || selected == _selectedEnv) return;

    final preferenceService = PreferenceService();
    await preferenceService.setEnvironment(selected);

    final newEnvironment = switch (selected) {
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

    ref.invalidate(appfit_providers.appFitTokenManagerProvider);
    ref.invalidate(appfit_providers.appFitDioProvider);

    setState(() => _selectedEnv = selected);
    logger.i('[LoginScreen] 서버 환경 수동 변경: → $selected');
  }

  void _onDevAreaTap() {
    final now = DateTime.now();
    if (_lastDevTap != null && now.difference(_lastDevTap!).inMilliseconds > 1000) {
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
        title: const Text('개발 계정 선택'),
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
              child: Text('$name ($id)', style: const TextStyle(fontSize: 14)),
            );
          }),
          const Divider(),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context),
            child: const Center(
              child: Text('닫기', style: TextStyle(fontSize: 14, color: Colors.grey)),
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
          // 배경 이미지
          Container(
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/images/login-bg.png'),
                fit: BoxFit.cover,
              ),
            ),
          ),

          SafeArea(
            child: GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              behavior: HitTestBehavior.translucent,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 460,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.1),
                          spreadRadius: 1,
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(40.0),
                        child: _buildLoginForm(formKey: _formKey),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // 개발 계정 선택 (좌측 하단 연타)
          Positioned(
            bottom: 0,
            left: 0,
            child: GestureDetector(
              onTap: _onDevAreaTap,
              behavior: HitTestBehavior.opaque,
              child: const SizedBox(width: 80, height: 80),
            ),
          ),

          // 언어 선택 위젯 + 서버 환경 표시 (우측 상단)
          Positioned(
            top: 20,
            right: 20,
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _buildLanguageSwitcher(),
                  const SizedBox(height: 4),
                  _buildEnvBadge(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
