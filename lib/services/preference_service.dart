import 'package:shared_preferences/shared_preferences.dart';
import 'package:appfit_order_agent/config/app_env.dart';
import 'package:appfit_order_agent/services/platform_service.dart';
import 'package:appfit_order_agent/utils/brand_registry.dart';
import 'package:appfit_order_agent/utils/currency_unit.dart';
import 'package:appfit_order_agent/utils/logger.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:device_info_plus/device_info_plus.dart';

import 'dart:convert';

import 'package:appfit_order_agent/services/migration/v2_migration_service.dart';

import 'dart:math';

class PreferenceService {
  static const String PREFERENCES_NAME = "KOKONUT_AGENT";
  static const methodChannel =
      MethodChannel('co.kr.waldlust.order.receive.appfit_order_agent');

  static const String KEY_MID = "KOKONUT_M_ID";
  static const String KEY_PWD = "KOKONUT_M_PWD";
  static const String KEY_STORE_ID = "KOKONUT_STORE_ID";
  static const String KEY_STORE_NAME = "KOKONUT_STORE_NAME";
  // 프로젝트명(=브랜드명). /v0/project/info 의 projectName. 로그인 시 저장.
  static const String KEY_PROJECT_NAME = "APPFIT_PROJECT_NAME";
  static const String KEY_REWARD_TYPE = "KOKONUT_STORE_TYPE";
  static const String KEY_WAIT_MIN = "KEY_WAIT_MIN";
  static const String KEY_AUTO_RECEIPT = "KEY_AUTO_RECEIPT";
  static const String KEY_AUTO_LAUNCH = "KEY_AUTO_LAUNCH";
  static const String KEY_VOLUME = "KEY_VOLUME";
  static const String KEY_ORDER_ON = "KEY_ORDER_ON";
  static const String KEY_VERSION_FIRST = "KEY_VERSION_FIRST";
  static const String KEY_SOUND = "KEY_SOUND";
  static const String KEY_SOUND_NUM = "KEY_SOUND_NUM";
  static const String KEY_IS_SAVE_ID = "IS_SAVE_ID";
  static const String KEY_IS_AUTO_LOGIN = "IS_AUTO_LOGIN";
  static const String KEY_IS_NEW_ORDER = "IS_NEW_ORDER";
  static const String KEY_SHOW_KIOSK_ORDER = "IS_SHOW_KIOSK_ORDER";
  static const String KEY_KIOSK_PRINT_AND_SOUND = "IS_KIOSK_PRINT_AND_SOUND";
  static const String KEY_KIOSK_ALWAYS_AUTO_ACCEPT =
      "KEY_KIOSK_ALWAYS_AUTO_ACCEPT"; // bool (기본 true): 키오스크 주문은 픽업 자동접수 설정과 무관하게 항상 즉시 접수
  static const String KEY_USE_PRINT = "KEY_USE_PRINT";
  static const String KEY_PRINTED_ORDERS = "KEY_PRINTED_ORDERS";
  static const String KEY_SOUNDGRAPH_ON = "KEY_SOUNDGRAPH_ON";
  static const String KEY_SOUNDGRAPH_MARKETID = "KEY_SOUNDGRAPH_MARKETID";
  static const String KEY_IS_DEV = "IS_DEV";
  static const String KEY_ENVIRONMENT = 'appfit_environment';

  // 관재(원격관리) 기기 식별 키
  static const String KEY_INSTALL_ID = "KOKONUT_INSTALL_ID";
  static const String KEY_DEVICE_SERIAL = "KOKONUT_DEVICE_SERIAL";

  // New Printer Setting Keys
  static const String KEY_USE_BUILTIN_PRINTER = "KOKONUT_USE_BUILTIN_PRINTER";
  static const String KEY_USE_EXTERNAL_PRINTER = "KOKONUT_USE_EXTERNAL_PRINTER";
  // SharedPreferences 키 문자열은 기존 설치 데이터 호환을 위해 "KEY_IS_SUB_DISPLAY" 유지.
  // 의미상 이 플래그는 KDS 모드(주방 디스플레이)를 지칭한다.
  static const String KEY_IS_KDS_MODE = "KEY_IS_SUB_DISPLAY";
  static const String KEY_ORDER_HISTORY_SCROLL = "KEY_ORDER_HISTORY_SCROLL";
  static const String KEY_PRINT_COUNT = "KEY_PRINT_COUNT";
  static const String KEY_LOCAL_SERVER_ENABLED = "KEY_LOCAL_SERVER_ENABLED";
  static const String KEY_USE_LABEL_PRINTER = "KOKONUT_USE_LABEL_PRINTER";

  // 프린터 × 출력물 매트릭스 키 (내장/외부 × 주문서/영수증)
  static const String KEY_BUILTIN_PRINT_ORDER =
      "KOKONUT_BUILTIN_PRINT_ORDER"; // 내장 × 주문서 (기본 true)
  static const String KEY_BUILTIN_PRINT_RECEIPT =
      "KOKONUT_BUILTIN_PRINT_RECEIPT"; // 내장 × 영수증 (기본 true)
  static const String KEY_EXTERNAL_PRINT_ORDER =
      "KOKONUT_EXTERNAL_PRINT_ORDER"; // 외부 × 주문서 (기본 true)
  static const String KEY_EXTERNAL_PRINT_RECEIPT =
      "KOKONUT_EXTERNAL_PRINT_RECEIPT"; // 외부 × 영수증 (기본 true)
  static const String KEY_BUILTIN_PRINT_CALL =
      "KOKONUT_BUILTIN_PRINT_CALL"; // 내장 × 기기 호출 알림 (기본 true)
  static const String KEY_EXTERNAL_PRINT_CALL =
      "KOKONUT_EXTERNAL_PRINT_CALL"; // 외부 × 기기 호출 알림 (기본 true)

  static const String KEY_SHOW_ORDER_TYPE_BADGE =
      "KEY_SHOW_ORDER_TYPE_BADGE"; // 주문 상세 헤더의 매장/포장 pill 노출 여부
  static const String KEY_ORDER_SOURCE_COLOR =
      "KEY_ORDER_SOURCE_COLOR"; // 앱/키오스크 주문 카드 배경색 구분 (default off)

  // 라벨프린터 테스트 모드 설정 키
  static const String KEY_LABEL_AUTO_REPLY_MODE =
      "KOKONUT_LABEL_AUTO_REPLY_MODE"; // int: 0 or 1
  static const String KEY_LABEL_USE_FEED_TO_TEAR =
      "KOKONUT_LABEL_USE_FEED_TO_TEAR"; // bool (기본 true)
  static const String KEY_LABEL_USE_BACK_TO_PRINT =
      "KOKONUT_LABEL_USE_BACK_TO_PRINT"; // bool (기본 true)
  static const String KEY_LABEL_USE_CALIBRATE =
      "KOKONUT_LABEL_USE_CALIBRATE"; // bool (기본 false)
  static const String KEY_LABEL_FILTER_MODE =
      "KOKONUT_LABEL_FILTER_MODE"; // int (0: 전체, 1: 와플만, 2: 와플제외)
  static const String KEY_LABEL_USE_QR_PRINT =
      "KOKONUT_LABEL_USE_QR_PRINT"; // bool (기본 false)
  static const String KEY_LABEL_QR_PAYLOAD_FORMAT =
      "KOKONUT_LABEL_QR_PAYLOAD_FORMAT"; // int (0: 기존 {orderNo}-{shopItemId}-{cupIdx}, 1: 신규 {displayNum}-{cupIdx}, 기본값 1)

  static const String KEY_IS_SOCKET_ENABLED =
      "KEY_IS_SOCKET_ENABLED"; // 소켓 사용 여부
  static const String KEY_FORCE_SOCKET_RECONNECT =
      "KEY_FORCE_SOCKET_RECONNECT"; // 소켓 강제 재접속 (1분마다)
  static const String KEY_IGNORE_OTHER_DEVICE_TASKS_KDS =
      "KEY_IGNORE_OTHER_DEVICE_TASKS_KDS"; // KDS 타 기기 이벤트 무시 설정
  static const String KEY_KDS_ACCEPT_ORDERS =
      "KEY_KDS_ACCEPT_ORDERS"; // KDS 모드에서 NEW 주문 직접 자동접수
  static const String KEY_LOCALE = "KEY_LOCALE"; // 언어 설정
  static const String KEY_CURRENCY = "KEY_CURRENCY"; // 화폐단위 설정
  static const String KEY_IS_ROTATED_180 = "KEY_IS_ROTATED_180"; // 화면 상하 반전
  static const String KEY_PRINTER_DEFAULT_SET =
      "KEY_PRINTER_DEFAULT_SET"; // 기본 프린터 설정 완료 여부
  static const String KEY_ENVIRONMENT_MANUAL_OVERRIDE =
      "appfit_environment_manual_override"; // 개발자 수동 서버 환경 오버라이드 플래그

  // 업데이트 설정 키
  static const String KEY_AUTO_CHECK_UPDATE = "KEY_AUTO_CHECK_UPDATE";
  static const String KEY_UPDATE_DEFAULT_SET = "KEY_UPDATE_DEFAULT_SET";
  // 업데이트 채널 정책 재조정 마커. 정책이 바뀌면 이 문자열을 새 값으로 올려
  // 기존 설치 기기를 다음 로그인 때 한 번 재조정한다. (구 마커: KEY_UPDATE_TPCP_OVERRIDE_DONE)
  static const String KEY_UPDATE_POLICY_RECONCILED =
      "KEY_UPDATE_POLICY_MHST_SUNMI_V1";

  // 브랜드 테마 키 (BrandTheme.id 를 문자열로 저장)
  static const String KEY_BRAND_THEME = "KEY_BRAND_THEME";

  // 듀얼모니터(D3 MINI 전면 디스플레이) 키 — 네이티브 MainActivity 상수와 동일해야 함.
  // 브랜드 slug 는 네이티브가 res/raw·res/drawable 콘텐츠를 getIdentifier 로 찾는 데 사용.
  static const String KEY_BRAND_SLUG = "KEY_BRAND_SLUG";
  // 콘텐츠 표시 모드: "video" / "image" / "none" / 미설정(null).
  // null=미설정 → 네이티브가 이미지 우선 자동 표시(effectiveMode 규칙). "none"=운영자 명시적 끔.
  static const String KEY_DUAL_MONITOR_MODE = "KEY_DUAL_MONITOR_MODE";

  // New Printer Setting Keys

  static final PreferenceService _instance = PreferenceService._internal();
  late SharedPreferences _prefs;
  final _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  );
  bool _isInitializing = false;
  bool _isInitialized = false;

  factory PreferenceService() {
    return _instance;
  }

  PreferenceService._internal();

  Future<bool> init() async {
    if (_isInitializing) {
      // 이미 초기화 중이면 완료될 때까지 대기
      while (_isInitializing && !_isInitialized) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      return _isInitialized;
    }

    _isInitializing = true;
    try {
      _prefs = await SharedPreferences.getInstance();

      // V2 → AppFit 마이그레이션 실행 (최초 1회)
      final migrationService = V2MigrationService();
      if (!migrationService.isCompleted(_prefs)) {
        await migrationService.runSettingsMigration(_prefs);
      }
      // 볼륨 스케일 0-15 → 0-10 재변환 (전용 플래그로 최초 1회)
      await migrationService.runVolumeRescaleMigration(_prefs);
      await _prefs.setBool('migration_completed', true);

      // 프린터 기본 설정 및 기기 제조사 확인
      await _initializePrinterDefaults();
      // 업데이트 설정 기본값 초기화
      await _initializeUpdateDefaults();
      // 서버 환경이 저장되지 않은 경우 매장 ID 기반으로 복원
      await _ensureEnvironmentIsSet();

      // ACCEPTED 주문 초기화 로직은 OrderProvider로 이동

      _isInitialized = true;
      return true;
    } catch (e, s) {
      logger.e('Error initializing preference service',
          error: e, stackTrace: s);
      _isInitialized = false;
      return false;
    } finally {
      _isInitializing = false;
    }
  }

  /// 프린터 설정 기본값 초기화 (최초 1회 실행)
  Future<void> _initializePrinterDefaults() async {
    final isAlreadySet = _prefs.getBool(KEY_PRINTER_DEFAULT_SET) ?? false;
    if (isAlreadySet) return; // 이미 설정되었으면 패스

    try {
      if (Platform.isAndroid) {
        final deviceInfoList = await DeviceInfoPlugin().androidInfo;
        final manufacturer = (deviceInfoList.manufacturer).toLowerCase();

        // KDS 모드 여부를 확인할 수 없으므로 우선 메인 모드 기준으로 기본값 세팅.
        // (요구사항: 메인 모드 -> 주문서 출력 ON, sunmi면 내장 ON 외부 OFF, 아니면 내장 OFF 외부 OFF, 라벨 OFF.
        // KDS 모드 -> 주문서 출력 OFF, 내장 OFF, 라벨 OFF) -> KDS 모드일 때의 처리는 보통 KDS 진입 시 설정되거나 사용자가 수동 설정
        // 공통 기본값 적용: 라벨 프린터 OFF
        await setUseLabelPrinter(false);

        if (manufacturer == 'sunmi') {
          // 선미 기기 기본값
          await setUsePrint(true);
          await setUseBuiltinPrinter(true);
          await setUseExternalPrinter(false);
          logger.i('[PreferenceService] Sunmi 디바이스 감지: 내장 프린터 ON 설정');
        } else {
          // 기타 기기 기본값
          await setUsePrint(true);
          await setUseBuiltinPrinter(false);
          await setUseExternalPrinter(false);
          logger.i(
              '[PreferenceService] 일반 디바이스 감지($manufacturer): 모든 프린터 OFF 설정');
        }
      } else {
        // iOS 디스크탑 등 기타 플랫폼
        await setUsePrint(true);
        await setUseBuiltinPrinter(false);
        await setUseExternalPrinter(false);
        await setUseLabelPrinter(false);
      }

      await _prefs.setBool(KEY_PRINTER_DEFAULT_SET, true); // 설정 완료 마커 저장
    } catch (e, s) {
      logger.e('[PreferenceService] 기본 프린터 설정 중 오류 발생',
          error: e, stackTrace: s);
    }
  }

  /// 업데이트 설정 기본값 초기화 (최초 1회 실행)
  Future<void> _initializeUpdateDefaults() async {
    final isAlreadySet = _prefs.getBool(KEY_UPDATE_DEFAULT_SET) ?? false;
    if (isAlreadySet) return;

    try {
      if (Platform.isAndroid) {
        final deviceInfo = await DeviceInfoPlugin().androidInfo;
        final manufacturer = deviceInfo.manufacturer.toLowerCase();
        if (manufacturer == 'sunmi') {
          await setAutoCheckUpdate(false);
          logger.i('[PreferenceService] Sunmi 디바이스 감지: 자동 업데이트 체크 OFF 설정');
        } else {
          await setAutoCheckUpdate(true);
          logger.i(
              '[PreferenceService] 일반 디바이스 감지($manufacturer): 자동 업데이트 체크 ON 설정');
        }
      } else {
        await setAutoCheckUpdate(true);
      }
      await _prefs.setBool(KEY_UPDATE_DEFAULT_SET, true);
    } catch (e, s) {
      logger.e('[PreferenceService] 업데이트 기본 설정 중 오류 발생',
          error: e, stackTrace: s);
    }
  }

  /// 서버 환경이 저장되지 않은 경우 매장 ID 기반으로 자동 설정
  ///
  /// 마이그레이션이 스킵된 구버전 AppFit 사용자 또는 환경값이 유실된 경우를
  /// 대응하기 위해 매번 init() 시 확인. KEY_ENVIRONMENT가 이미 있으면 즉시 리턴.
  Future<void> _ensureEnvironmentIsSet() async {
    if (_prefs.containsKey(KEY_ENVIRONMENT)) return;
    final savedId = getId();
    if (savedId == null || savedId.isEmpty) return;
    final env =
        BrandRegistry.resolveOrNull(savedId)?.serverEnvironment ?? 'live';
    await _prefs.setString(KEY_ENVIRONMENT, env);
    logger.i('[PreferenceService] 서버 환경 자동 복원: $env (ID: $savedId)');
  }

  /// 레거시 데이터 접근 권한 확인
  Future<bool> checkLegacyDataAccess() async {
    if (!Platform.isAndroid) return false;

    try {
      final bool canAccess =
          await methodChannel.invokeMethod<bool>('checkLegacyDataAccess') ??
              false;
      logger.i('Legacy data access check result: $canAccess');
      return canAccess;
    } catch (e, s) {
      logger.e('Error checking legacy data access', error: e, stackTrace: s);
      return false;
    }
  }

  /// 레거시 데이터 접근 권한 요청
  Future<void> requestLegacyDataAccess() async {
    if (!Platform.isAndroid) return;

    try {
      await methodChannel.invokeMethod('requestLegacyDataAccess');
      logger.i('Requested legacy data access');
    } catch (e, s) {
      logger.e('Error requesting legacy data access', error: e, stackTrace: s);
    }
  }

  // ID 저장
  //
  // 매장 ID는 항상 대문자로 정규화한다. AppFit 토큰/소켓 채널/인터셉터에서
  // currentStoreId(=getId())를 그대로 사용하므로, 대소문자가 섞이면 토큰 캐시
  // shopCode mismatch가 발생해 매 요청마다 토큰이 재발급된다. 로그인 화면이
  // 대문자로 토큰을 발급한 뒤 _saveLoginInfo()가 소문자로 저장하면서 다음 API
  // 호출에서 캐시가 깨지는 사고를 방지한다.
  Future<void> saveId(String id) async {
    final normalized = id.trim().toUpperCase();
    await _prefs.setString(KEY_MID, normalized);
  }

  // ID 조회
  //
  // 본 변경 이전에 소문자로 저장된 레거시 값이 남아있을 수 있어
  // 읽는 시점에서도 대문자로 정규화한다. (saveId()와 동일한 규칙)
  String? getId() {
    final raw = _prefs.getString(KEY_MID);
    if (raw == null) return null;
    return raw.trim().toUpperCase();
  }

  // 비밀번호 저장 (FlutterSecureStorage 사용)
  Future<void> savePassword(String id, String password) async {
    final trimmedId = id.trim();
    if (trimmedId.isEmpty) {
      logger.e('savePassword called with empty ID');
      return;
    }

    try {
      logger.i('[$trimmedId] Saving password to secure storage...');
      // 보안 저장소에 비밀번호 저장
      await _secureStorage.write(
        key: '${trimmedId}_password',
        value: password,
      );

      // 하위 호환성을 위해 SharedPreferences에는 마커만 저장 (또는 비움)
      await _prefs.setString(KEY_PWD, 'SECURE_STORAGE_V2');
      logger.i('[$trimmedId] Successfully saved password to secure storage');
    } catch (e, s) {
      logger.e('[$trimmedId] Error saving password to secure storage',
          error: e, stackTrace: s);
      // 보안 저장소 실패 시 SharedPreferences에 예외로 저장
      await _prefs.setString(KEY_PWD, password);
    }
  }

  // 비밀번호 조회 (FlutterSecureStorage 사용)
  Future<String?> getPassword(String savedId) async {
    final trimmedId = savedId.trim();
    if (trimmedId.isEmpty) {
      logger.w('getPassword called with empty ID');
      return null;
    }

    try {
      logger.i('[$trimmedId] Attempting to read password from secure storage');
      // 1. 보안 저장소 확인
      String? password =
          await _secureStorage.read(key: '${trimmedId}_password');

      if (password != null && password.isNotEmpty) {
        logger.i('[$trimmedId] Password found in secure storage');
        return password;
      }

      logger.w(
          '[$trimmedId] Password NOT found in secure storage, checking SharedPreferences...');

      // 2. 레거시 데이터 확인 (마이그레이션용)
      final encryptedPwd = _prefs.getString(KEY_PWD);
      if (encryptedPwd == null || encryptedPwd.isEmpty) {
        logger.w('[$trimmedId] No legacy password in SharedPreferences');
        return null;
      }

      if (encryptedPwd == 'SECURE_STORAGE_V2') {
        // 이미 마이그레이션 되었으나 read에 실패한 경우
        logger.e(
            '[$trimmedId] Marker SECURE_STORAGE_V2 exists but secure storage read returned null. Data might be lost or inaccessible.');
        return null;
      }

      // 레거시 암호문인 경우 네이티브 복호화 시도 (MissingPluginException 발생 가능성 있음)
      try {
        logger.i(
            '[$trimmedId] Attempting legacy decryption via native MethodChannel');
        final decryptedPwd = await platform
            .invokeMethod('getDecPwd', {'id': trimmedId, 'pw': encryptedPwd});

        if (decryptedPwd != null) {
          logger.i(
              '[$trimmedId] Legacy decryption success, migrating to secure storage');
          // 성공 시 새로운 저장소로 마이그레이션
          await savePassword(trimmedId, decryptedPwd);
          return decryptedPwd;
        }
      } catch (e, s) {
        logger.w('[$trimmedId] Legacy decryption failed: $e');

        // 암호문일 가능성이 높은 경우 (보통 20자 이상의 Base64 패턴)
        if (encryptedPwd.length > 20) {
          logger.e(
              '[$trimmedId] Detected un-decryptable legacy cipher. Forcing re-login.');
          return null;
        }
      }

      // 평문인 경우 대응
      logger.i('[$trimmedId] Treating SharedPreferences value as plain text');
      return encryptedPwd;
    } catch (e, s) {
      logger.e('[$trimmedId] Error during getPassword',
          error: e, stackTrace: s);
      final fallback = _prefs.getString(KEY_PWD);
      return (fallback == 'SECURE_STORAGE_V2') ? null : fallback;
    }
  }

  // ID 저장 여부 설정
  Future<void> setSaveId(bool value) async {
    await _prefs.setString(KEY_IS_SAVE_ID, value == true ? 'T' : 'F');
  }

  // ID 저장 여부 조회
  String getIsSaveId() {
    return _prefs.getString(KEY_IS_SAVE_ID) ?? 'F';
  }

  // 자동 로그인 설정
  Future<void> setAutoLogin(bool value) async {
    await _prefs.setString(KEY_IS_AUTO_LOGIN, value == true ? 'T' : 'F');
  }

  // 자동 로그인 여부 조회
  String getIsAutoLogin() {
    return _prefs.getString(KEY_IS_AUTO_LOGIN) ?? 'F';
  }

  // 개발 서버 설정
  Future<void> setIsDev(bool value) async {
    await _prefs.setString(KEY_IS_DEV, value == true ? 'T' : 'F');
  }

  // 개발 서버 여부 조회
  String getIsDev() {
    return _prefs.getString(KEY_IS_DEV) ?? 'F';
  }

  // 서버 환경 조회 (dev / staging / live / japanLive)
  String getEnvironment() => _prefs.getString(KEY_ENVIRONMENT) ?? 'live';

  // 서버 환경 저장
  Future<void> setEnvironment(String env) =>
      _prefs.setString(KEY_ENVIRONMENT, env);

  // 개발자 수동 서버 환경 오버라이드 플래그 조회
  bool getEnvironmentManualOverride() =>
      _prefs.getBool(KEY_ENVIRONMENT_MANUAL_OVERRIDE) ?? false;

  // 개발자 수동 서버 환경 오버라이드 플래그 저장
  Future<void> setEnvironmentManualOverride(bool value) =>
      _prefs.setBool(KEY_ENVIRONMENT_MANUAL_OVERRIDE, value);

  // 브랜드 테마 id 조회 (저장되지 않았으면 null → 기본 테마)
  String? getBrandThemeId() => _prefs.getString(KEY_BRAND_THEME);

  // 브랜드 테마 id 저장
  Future<void> setBrandThemeId(String id) =>
      _prefs.setString(KEY_BRAND_THEME, id);

  // 듀얼모니터 콘텐츠 표시 모드 조회.
  // null=미설정 → effectiveMode 규칙이 이미지 우선으로 자동 해석(콘텐츠 있으면 자동 표시).
  // "none" 은 운영자가 명시적으로 끈 상태. 기본값으로 "none" 을 반환하지 말 것.
  String? getDualMonitorMode() => _prefs.getString(KEY_DUAL_MONITOR_MODE);

  // 듀얼모니터 콘텐츠 표시 모드 저장 ("video" / "image" / "none").
  Future<void> setDualMonitorMode(String mode) =>
      _prefs.setString(KEY_DUAL_MONITOR_MODE, mode);

  // 모든 로그인 정보 삭제
  Future<void> clearLoginInfo() async {
    final savedId = getId();

    await _prefs.setString(KEY_PWD, '');
    await _prefs.setString(KEY_IS_AUTO_LOGIN, 'F');

    // 보안 저장소의 비밀번호 삭제
    if (savedId != null && savedId.isNotEmpty) {
      await _secureStorage.delete(key: '${savedId}_password');
    }

    if (getIsSaveId() == 'F') {
      await _prefs.setString(KEY_MID, '');
    }
  }

  String? getStoreId() => _prefs.getString(KEY_STORE_ID);
  String? getStoreName() => _prefs.getString(KEY_STORE_NAME);

  /// 프로젝트명(=브랜드명) 조회. /v0/project/info 의 projectName, 로그인 시 저장.
  String? getProjectName() => _prefs.getString(KEY_PROJECT_NAME);

  /// 프로젝트명(=브랜드명) 저장.
  Future<void> setProjectName(String name) =>
      _prefs.setString(KEY_PROJECT_NAME, name);
  String? getRewardType() => _prefs.getString(KEY_REWARD_TYPE);

  /// 설치 단위 고유 ID. 없으면 생성·영속 후 반환(이후 항상 동일 값).
  /// Sunmi 시리얼/Windows deviceId 를 얻지 못하는 단말의 fallback 식별자.
  Future<String> getOrCreateInstallId() async {
    final existing = _prefs.getString(KEY_INSTALL_ID);
    if (existing != null && existing.isNotEmpty) return existing;
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    final id = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    await _prefs.setString(KEY_INSTALL_ID, id);
    return id;
  }

  /// 캐시된 기기 시리얼(네이티브 조회 1회 후 보관). 없으면 null.
  String? getCachedDeviceSerial() => _prefs.getString(KEY_DEVICE_SERIAL);

  Future<void> setCachedDeviceSerial(String serial) async =>
      _prefs.setString(KEY_DEVICE_SERIAL, serial);

  /// AppFit Project ID 조회 (보안 저장소)
  Future<String?> getProjectId() async {
    return await _secureStorage.read(key: 'appfit_project_id');
  }

  int getWaitMin() => _prefs.getInt(KEY_WAIT_MIN) ?? 0;
  bool getSoundGraphOn() => _prefs.getBool(KEY_SOUNDGRAPH_ON) ?? false;
  Future<void> setSoundGraphOn(bool value) async =>
      _prefs.setBool(KEY_SOUNDGRAPH_ON, value);

  String getSoundGraphMarketId() =>
      _prefs.getString(KEY_SOUNDGRAPH_MARKETID) ?? '';
  Future<void> setSoundGraphMarketId(String value) async =>
      _prefs.setString(KEY_SOUNDGRAPH_MARKETID, value);

  bool getAutoReceipt() {
    final value = _prefs.getBool(KEY_AUTO_RECEIPT) ?? true;
    logger.i('[PreferenceService] 자동접수 설정 조회: $value');
    return value;
  } //주문자동접수

  bool getAutoLaunch() =>
      _prefs.getBool(KEY_AUTO_LAUNCH) ?? false; //부팅시 자동실행 여부
  int getVolume() => _prefs.getInt(KEY_VOLUME) ?? 5; //알림음 볼륨 (0-10)
  bool getOrderOn() => _prefs.getBool(KEY_ORDER_ON) ?? false; //오더 영업중 여부
  bool getVersionFirst() => _prefs.getBool(KEY_VERSION_FIRST) ?? false;
  String getSound() => _prefs.getString(KEY_SOUND) ?? 'alert10.mp3'; //알림음 파일명
  int getSoundNum() => _prefs.getInt(KEY_SOUND_NUM) ?? 5; //알림음 재생 횟수
  bool getIsNewOrder() => _prefs.getBool(KEY_IS_NEW_ORDER) ?? false; //
  bool getShowKioskOrder() =>
      _prefs.getBool(KEY_SHOW_KIOSK_ORDER) ?? true; //키오스크주문 노출여부

  /// 키오스크 주문 항상 자동접수 (기본 ON): 픽업 오더 자동 접수(getAutoReceipt) 와
  /// 무관하게 키오스크 주문은 항상 NEW→PREPARING 즉시 전이시킨다.
  bool getKioskAlwaysAutoAccept() =>
      _prefs.getBool(KEY_KIOSK_ALWAYS_AUTO_ACCEPT) ?? true;
  bool getKioskPrintAndSound() =>
      _prefs.getBool(KEY_KIOSK_PRINT_AND_SOUND) ??
      true; //키오스크주문 출력 및 알람소리 재생 여부
  bool getUsePrint() => _prefs.getBool(KEY_USE_PRINT) ?? true; //주문서 출력 여부

  // New printer settings getters
  bool getUseBuiltinPrinter() =>
      _prefs.getBool(KEY_USE_BUILTIN_PRINTER) ?? true; // Default true
  bool getUseExternalPrinter() =>
      _prefs.getBool(KEY_USE_EXTERNAL_PRINTER) ?? false; // Default false
  bool getUseLabelPrinter() =>
      _prefs.getBool(KEY_USE_LABEL_PRINTER) ?? false; // Default false

  // 프린터 × 출력물 매트릭스 getters
  bool getBuiltinPrintOrder() =>
      _prefs.getBool(KEY_BUILTIN_PRINT_ORDER) ?? true;
  bool getBuiltinPrintReceipt() =>
      _prefs.getBool(KEY_BUILTIN_PRINT_RECEIPT) ?? true;
  bool getExternalPrintOrder() =>
      _prefs.getBool(KEY_EXTERNAL_PRINT_ORDER) ?? true;
  bool getExternalPrintReceipt() =>
      _prefs.getBool(KEY_EXTERNAL_PRINT_RECEIPT) ?? true;
  bool getBuiltinPrintCall() => _prefs.getBool(KEY_BUILTIN_PRINT_CALL) ?? true;
  bool getExternalPrintCall() =>
      _prefs.getBool(KEY_EXTERNAL_PRINT_CALL) ?? true;

  bool getShowOrderTypeBadge() =>
      _prefs.getBool(KEY_SHOW_ORDER_TYPE_BADGE) ??
      false; // 주문 상세 헤더 매장/포장 pill 노출 (default off)

  bool getOrderSourceColor() =>
      _prefs.getBool(KEY_ORDER_SOURCE_COLOR) ??
      false; // 앱/키오스크 주문 카드 배경색 구분 (default off)

  // 라벨프린터 테스트 모드 getters
  // autoReplyMode=1: SDK 양방향 통신 활성. PrintedEvent ACK 콜백을 받기 위한 전제.
  int getLabelAutoReplyMode() => _prefs.getInt(KEY_LABEL_AUTO_REPLY_MODE) ?? 1;
  bool getLabelUseFeedToTear() =>
      _prefs.getBool(KEY_LABEL_USE_FEED_TO_TEAR) ?? true;
  bool getLabelUseBackToPrint() =>
      _prefs.getBool(KEY_LABEL_USE_BACK_TO_PRINT) ?? true;
  bool getLabelUseCalibrate() =>
      _prefs.getBool(KEY_LABEL_USE_CALIBRATE) ?? false;
  bool getLabelUseQrPrint() => _prefs.getBool(KEY_LABEL_USE_QR_PRINT) ?? false;

  /// 라벨 필터 모드 (0: 전체, 1: 와플만, 2: 와플제외)
  int getLabelFilterMode() => _prefs.getInt(KEY_LABEL_FILTER_MODE) ?? 0;

  /// 라벨 QR 페이로드 포맷 (0: 기존, 1: 신규 displayNum-cupIdx 테스트 포맷)
  int getLabelQrPayloadFormat() =>
      _prefs.getInt(KEY_LABEL_QR_PAYLOAD_FORMAT) ?? 1;

  // 영업 상태 저장
  Future<void> setOrderOn(bool value) async {
    await _prefs.setBool(KEY_ORDER_ON, value);
  }

  // 볼륨 설정
  Future<void> setVolume(int value) async {
    await _prefs.setInt(KEY_VOLUME, value);
  }

  // 알림음 파일 설정
  Future<void> setSound(String value) async {
    await _prefs.setString(KEY_SOUND, value);
  }

  // 알림음 재생 횟수 설정
  Future<void> setSoundNum(int value) async {
    await _prefs.setInt(KEY_SOUND_NUM, value);
  }

  // 자동 실행 설정
  //
  // 설정 저장(_saveSettings)은 모든 항목을 매번 재저장하므로, 가드가 없으면
  // 무관한 설정 변경마다 네이티브 부팅 자동실행(setAutoStartup)이 재적용되어
  // '[SYSTEM] 부팅 시 자동 실행 ... 요청 결과' 로그가 매번 찍히고 불필요한
  // 레지스트리/MethodChannel 부수효과가 발생한다. 값이 실제로 바뀐 경우에만 재적용.
  Future<void> setAutoLaunch(bool value) async {
    final previous = _prefs.getBool(KEY_AUTO_LAUNCH);
    await _prefs.setBool(KEY_AUTO_LAUNCH, value);
    if (previous == value) return; // 변경 없음 — 네이티브 재적용 스킵
    await PlatformService.setAutoStartup(value);
  }

  // 픽업 오더 자동 접수 설정 (키오스크 항상 자동접수와 별개 축)
  //
  // 설정 저장(_saveSettings)은 모든 항목을 매번 재저장하므로, 값이 실제로 바뀐
  // 경우에만 로그를 남긴다. (가드 없으면 키오스크 등 무관한 설정을 바꿔도
  // '픽업 오더 자동접수 저장' 로그가 찍혀 오해를 부름)
  Future<void> setAutoReceipt(bool value) async {
    final previous = _prefs.getBool(KEY_AUTO_RECEIPT);
    await _prefs.setBool(KEY_AUTO_RECEIPT, value);
    if (previous != value) {
      logger.i('[PreferenceService] 픽업 오더 자동접수 설정 저장: $value');
    }
  }

  // 인쇄 사용 설정
  Future<void> setUsePrint(bool value) async {
    await _prefs.setBool(KEY_USE_PRINT, value);
    if (!value) {
      await setUseBuiltinPrinter(false);
      await setUseExternalPrinter(false);
    } else {
      // If turning on, and neither is active, default to built-in.
      if (!getUseBuiltinPrinter() && !getUseExternalPrinter()) {
        await setUseBuiltinPrinter(true);
        // setUseBuiltinPrinter(true) should handle setting external to false.
      }
    }
  }

  // New printer settings setters
  Future<void> setUseBuiltinPrinter(bool value) async {
    await _prefs.setBool(KEY_USE_BUILTIN_PRINTER, value);
  }

  Future<void> setUseExternalPrinter(bool value) async {
    await _prefs.setBool(KEY_USE_EXTERNAL_PRINTER, value);
  }

  Future<void> setUseLabelPrinter(bool value) async {
    await _prefs.setBool(KEY_USE_LABEL_PRINTER, value);
  }

  // 프린터 × 출력물 매트릭스 setters
  Future<void> setBuiltinPrintOrder(bool value) async =>
      _prefs.setBool(KEY_BUILTIN_PRINT_ORDER, value);
  Future<void> setBuiltinPrintReceipt(bool value) async =>
      _prefs.setBool(KEY_BUILTIN_PRINT_RECEIPT, value);
  Future<void> setExternalPrintOrder(bool value) async =>
      _prefs.setBool(KEY_EXTERNAL_PRINT_ORDER, value);
  Future<void> setExternalPrintReceipt(bool value) async =>
      _prefs.setBool(KEY_EXTERNAL_PRINT_RECEIPT, value);
  Future<void> setBuiltinPrintCall(bool value) async =>
      _prefs.setBool(KEY_BUILTIN_PRINT_CALL, value);
  Future<void> setExternalPrintCall(bool value) async =>
      _prefs.setBool(KEY_EXTERNAL_PRINT_CALL, value);

  Future<void> setShowOrderTypeBadge(bool value) async {
    await _prefs.setBool(KEY_SHOW_ORDER_TYPE_BADGE, value);
  }

  Future<void> setOrderSourceColor(bool value) async {
    await _prefs.setBool(KEY_ORDER_SOURCE_COLOR, value);
  }

  // 라벨프린터 테스트 모드 setters
  Future<void> setLabelAutoReplyMode(int value) async {
    await _prefs.setInt(KEY_LABEL_AUTO_REPLY_MODE, value);
  }

  Future<void> setLabelUseFeedToTear(bool value) async {
    await _prefs.setBool(KEY_LABEL_USE_FEED_TO_TEAR, value);
  }

  Future<void> setLabelUseBackToPrint(bool value) async {
    await _prefs.setBool(KEY_LABEL_USE_BACK_TO_PRINT, value);
  }

  Future<void> setLabelUseCalibrate(bool value) async {
    await _prefs.setBool(KEY_LABEL_USE_CALIBRATE, value);
  }

  Future<void> setLabelUseQrPrint(bool value) async {
    await _prefs.setBool(KEY_LABEL_USE_QR_PRINT, value);
  }

  Future<void> setLabelFilterMode(int value) async {
    await _prefs.setInt(KEY_LABEL_FILTER_MODE, value);
  }

  Future<void> setLabelQrPayloadFormat(int value) async {
    await _prefs.setInt(KEY_LABEL_QR_PAYLOAD_FORMAT, value);
  }

  // 키오스크 주문 노출 설정
  Future<void> setShowKioskOrder(bool value) async {
    await _prefs.setBool(KEY_SHOW_KIOSK_ORDER, value);
  }

  // 키오스크 주문 출력 및 소리 설정
  Future<void> setKioskPrintAndSound(bool value) async {
    await _prefs.setBool(KEY_KIOSK_PRINT_AND_SOUND, value);
  }

  // 키오스크 주문 항상 자동접수 설정 (픽업 오더 자동접수와 별개 축)
  // 값이 실제로 바뀐 경우에만 로그(위 setAutoReceipt 와 동일 이유).
  Future<void> setKioskAlwaysAutoAccept(bool value) async {
    final previous = _prefs.getBool(KEY_KIOSK_ALWAYS_AUTO_ACCEPT);
    await _prefs.setBool(KEY_KIOSK_ALWAYS_AUTO_ACCEPT, value);
    if (previous != value) {
      logger.i('[PreferenceService] 키오스크 항상 자동접수 설정 저장: $value');
    }
  }

  // KDS 모드 설정 저장 (기존 sub-display 플래그와 동일 키 사용)
  Future<void> setKdsMode(bool value) async {
    await _prefs.setBool(KEY_IS_KDS_MODE, value);
  }

  // KDS 모드 설정 조회
  bool getKdsMode() {
    return _prefs.getBool(KEY_IS_KDS_MODE) ?? false;
  }

  // 프린터 선택 설정
  Future<void> setSelectedPrinter(String value) async {
    await _prefs.setString('selectedPrinter', value);
  }

  // 서버 URL 설정
  Future<void> setServerUrl(String value) async {
    await _prefs.setString('serverUrl', value);
  }

  // 출력된 주문 목록 저장
  Future<void> setPrintedOrders(Map<String, String> printedOrders) async {
    final jsonString = jsonEncode(printedOrders);
    await _prefs.setString(KEY_PRINTED_ORDERS, jsonString);
  }

  // 출력된 주문 목록 조회
  Map<String, dynamic> getPrintedOrders() {
    final String? jsonStr = _prefs.getString(KEY_PRINTED_ORDERS);
    if (jsonStr == null || jsonStr.isEmpty) {
      return {};
    }

    try {
      final Map<String, dynamic> result = jsonDecode(jsonStr);
      return result;
    } catch (e, s) {
      logger.e('Error parsing printed orders JSON', error: e, stackTrace: s);
      return {};
    }
  }

  // 마지막 주문 시간 조회
  DateTime? getLastOrderTime() {
    final String? lastOrderTimeStr = _prefs.getString('last_order_time');
    if (lastOrderTimeStr == null || lastOrderTimeStr.isEmpty) {
      return null;
    }
    try {
      return DateTime.parse(lastOrderTimeStr);
    } catch (e, s) {
      logger.e('Error parsing last order time', error: e, stackTrace: s);
      return null;
    }
  }

  // 마지막 주문 시간 저장
  Future<void> setLastOrderTime(DateTime time) async {
    await _prefs.setString('last_order_time', time.toIso8601String());
  }

  // 설치 시간 조회
  DateTime? getInstallTime() {
    final String? installTimeStr = _prefs.getString('install_time');
    if (installTimeStr == null || installTimeStr.isEmpty) {
      return null;
    }
    try {
      return DateTime.parse(installTimeStr);
    } catch (e, s) {
      logger.e('Error parsing install time', error: e, stackTrace: s);
      return null;
    }
  }

  // 설치 시간 저장
  Future<void> setInstallTime(DateTime time) async {
    await _prefs.setString('install_time', time.toIso8601String());
  }

  // 주문내역 보기설정 저장 (true: 스크롤 O, false: 스크롤 X)
  Future<void> setOrderHistoryScroll(bool value) async {
    await _prefs.setBool(KEY_ORDER_HISTORY_SCROLL, value);
  }

  // 주문내역 보기설정 조회 (true: 스크롤 O, false: 스크롤 X)
  bool getOrderHistoryScroll() {
    return _prefs.getBool(KEY_ORDER_HISTORY_SCROLL) ?? true; // 기본값: 스크롤 O
  }

  // 주문서 출력 개수 저장
  Future<void> setPrintCount(int value) async {
    await _prefs.setInt(KEY_PRINT_COUNT, value);
  }

  // 주문서 출력 개수 조회
  int getPrintCount() {
    return _prefs.getInt(KEY_PRINT_COUNT) ?? 1; // 기본값: 1개
  }

  // 로컬 서버 활성화 설정 저장
  Future<void> setLocalServerEnabled(bool value) async {
    await _prefs.setBool(KEY_LOCAL_SERVER_ENABLED, value);
  }

  // 로컬 서버 활성화 설정 조회
  bool getLocalServerEnabled() {
    return _prefs.getBool(KEY_LOCAL_SERVER_ENABLED) ?? false; // 기본값: 비활성화
  }

  // 소켓 활성화 설정 저장
  Future<void> setIsSocketEnabled(bool value) async {
    await _prefs.setBool(KEY_IS_SOCKET_ENABLED, value);
  }

  // 소켓 활성화 설정 조회
  bool getIsSocketEnabled() {
    return _prefs.getBool(KEY_IS_SOCKET_ENABLED) ?? true; // 기본값: 활성화
  }

  // 소켓 강제 재접속 설정 저장 (1분마다 재연결)
  Future<void> setForceSocketReconnect(bool value) async {
    await _prefs.setBool(KEY_FORCE_SOCKET_RECONNECT, value);
  }

  // 소켓 강제 재접속 설정 조회
  bool getForceSocketReconnect() {
    return _prefs.getBool(KEY_FORCE_SOCKET_RECONNECT) ?? false; // 기본값: 비활성화
  }

  // KDS 타 기기 이벤트 무시 설정 저장
  Future<void> setIgnoreOtherDeviceTasksKds(bool value) async {
    await _prefs.setBool(KEY_IGNORE_OTHER_DEVICE_TASKS_KDS, value);
  }

  // KDS 타 기기 이벤트 무시 설정 조회
  bool getIgnoreOtherDeviceTasksKds() {
    return _prefs.getBool(KEY_IGNORE_OTHER_DEVICE_TASKS_KDS) ??
        false; // 기본값: 비활성화 (기존 동작)
  }

  // KDS 모드에서 NEW 주문 자동접수 활성화 여부 저장
  Future<void> setKdsAcceptOrders(bool value) async {
    await _prefs.setBool(KEY_KDS_ACCEPT_ORDERS, value);
  }

  // KDS 모드에서 NEW 주문 자동접수 활성화 여부 조회
  bool getKdsAcceptOrders() {
    return _prefs.getBool(KEY_KDS_ACCEPT_ORDERS) ?? false;
  }

  // 언어 설정 저장
  Future<void> setLocale(String languageCode) async {
    await _prefs.setString(KEY_LOCALE, languageCode);
  }

  // 언어 설정 조회
  String? getLocale() {
    return _prefs.getString(KEY_LOCALE);
  }

  // 화폐단위 설정 저장
  Future<void> setCurrency(CurrencyUnit value) async {
    await _prefs.setString(KEY_CURRENCY, value.name);
  }

  // 화폐단위 설정 조회 (기본값: 브랜드 레지스트리의 currency, 미지의 매장은 krw)
  CurrencyUnit getCurrency() {
    final saved = _prefs.getString(KEY_CURRENCY);
    if (saved == 'krw') return CurrencyUnit.krw;
    if (saved == 'jpy') return CurrencyUnit.jpy;
    return BrandRegistry.resolveOrNull(getId())?.currency ?? CurrencyUnit.krw;
  }

  // 화면 상하 반전 저장
  Future<void> setIsRotated180(bool value) async {
    await _prefs.setBool(KEY_IS_ROTATED_180, value);
  }

  // 화면 상하 반전 조회 (저장값 없으면 빌드 플래그 기본값)
  bool getIsRotated180() {
    return _prefs.getBool(KEY_IS_ROTATED_180) ?? AppEnv.isRotated180;
  }

  // 자동 업데이트 체크 설정 조회 (기본값: true)
  bool getAutoCheckUpdate() => _prefs.getBool(KEY_AUTO_CHECK_UPDATE) ?? true;

  // 자동 업데이트 체크 설정 저장
  Future<void> setAutoCheckUpdate(bool value) async =>
      await _prefs.setBool(KEY_AUTO_CHECK_UPDATE, value);

  // 업데이트 채널 정책 재조정 완료 여부 조회 (정책당 1회 실행 게이트)
  bool getUpdatePolicyReconciled() =>
      _prefs.getBool(KEY_UPDATE_POLICY_RECONCILED) ?? false;

  // 업데이트 채널 정책 재조정 완료 여부 저장
  Future<void> setUpdatePolicyReconciled(bool value) async =>
      await _prefs.setBool(KEY_UPDATE_POLICY_RECONCILED, value);

  // ── 브랜드 판별 레거시 헬퍼 ──────────────────────────────────────────────
  // prefix 매칭 로직의 단일 출처는 [BrandRegistry]. 아래 헬퍼들은 그 위의 얇은
  // 어댑터이며, 신규 코드는 BrandRegistry.resolveOrNull / currentBrandProvider 사용.

  /// TPCP 매장 여부를 ID 문자열로 판별. (마이그레이션/로그인처럼 ID 저장 전 사용)
  static bool isTPCPStoreId(String? storeId) =>
      BrandRegistry.resolveOrNull(storeId)?.key == BrandKey.tpcp;

  /// 현재 저장된 매장 ID가 TPCP(일본 특화) 매장인지 반환.
  bool isTpcpStore() => isTPCPStoreId(getId());

  /// MHST(매머드) 매장 여부를 ID 문자열로 판별.
  static bool isMHSTStoreId(String? storeId) =>
      BrandRegistry.resolveOrNull(storeId)?.key == BrandKey.mhst;

  /// 현재 저장된 매장 ID가 MHST(매머드) 매장인지 반환.
  bool isMammothStore() => isMHSTStoreId(getId());

  /// 마하테이스트(mahataste) 매장 여부를 ID 문자열로 판별.
  static bool isMATAStoreId(String? storeId) =>
      BrandRegistry.resolveOrNull(storeId)?.key == BrandKey.mata;

  /// 현재 저장된 매장 ID가 마하테이스트(mahataste) 매장인지 반환.
  bool isMataStore() => isMATAStoreId(getId());

  // ── Windows 전용 프린터 설정 ────────────────────────────────────────────────

  static const String _keyComPortName = 'APPFIT_COM_PORT_NAME';
  static const String _keyComPortBaudRate = 'APPFIT_COM_PORT_BAUD_RATE';

  String? getComPortName() => _prefs.getString(_keyComPortName);
  Future<void> setComPortName(String name) async =>
      _prefs.setString(_keyComPortName, name);

  // 기본 115200: PR800 시리얼 포트 고정값이며 USB-CDC 는 baud 무시.
  // ComPortPrintService.defaultBaudRate 와 함께 유지.
  int getComPortBaudRate() => _prefs.getInt(_keyComPortBaudRate) ?? 115200;
  Future<void> setComPortBaudRate(int baudRate) async =>
      _prefs.setInt(_keyComPortBaudRate, baudRate);
}
