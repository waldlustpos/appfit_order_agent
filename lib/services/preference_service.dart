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
  // 현재 로그인 세션의 매장 ID. KEY_MID 와 달리 "아이디 저장" 체크박스와 무관하게
  // 로그인 성공 시 항상 기록된다. (신규 키 — 구앱 KOKONUT_* 잔존값 오염 방지)
  static const String KEY_SESSION_STORE_ID = "APPFIT_SESSION_STORE_ID";
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
  // 키오스크 설정 재조정 마커. 기본값을 바꿔도 이미 값이 저장된 기존 설치는
  // 그대로이므로, 업데이트 후 첫 실행 때 한 번만 강제로 덮어쓴다.
  //   노출 / 주문서·알림소리 → false, 항상 자동접수 → true.
  // 정책이 또 바뀌면 이 문자열을 새 버전으로 올려 기존 기기를 다시 한 번
  // 재조정한다. (구 마커: KEY_KIOSK_DEFAULT_OFF_V1 — 노출·알림만 다뤘음)
  static const String KEY_KIOSK_SETTINGS_RECONCILED = "KEY_KIOSK_SETTINGS_V2";
  static const String KEY_KIOSK_ALWAYS_AUTO_ACCEPT =
      "KEY_KIOSK_ALWAYS_AUTO_ACCEPT"; // bool (기본 true): 키오스크 주문은 픽업 자동접수 설정과 무관하게 항상 즉시 접수
  static const String KEY_SHOW_POS_ORDER =
      "KEY_SHOW_POS_ORDER"; // bool (기본 false): POS 주문 노출 여부
  static const String KEY_POS_PRINT_AND_SOUND =
      "KEY_POS_PRINT_AND_SOUND"; // bool (기본 false): POS 주문 출력 및 알람소리 재생 여부
  static const String KEY_USE_PRINT = "KEY_USE_PRINT";
  static const String KEY_PRINTED_ORDERS = "KEY_PRINTED_ORDERS";
  static const String KEY_SOUNDGRAPH_ON = "KEY_SOUNDGRAPH_ON";
  static const String KEY_SOUNDGRAPH_MARKETID = "KEY_SOUNDGRAPH_MARKETID";
  static const String KEY_IS_DEV = "IS_DEV";
  static const String KEY_ENVIRONMENT = 'appfit_environment';

  // 관재(원격관리) 기기 식별 키
  static const String KEY_INSTALL_ID = "KOKONUT_INSTALL_ID";
  // ⚠️ 키 문자열에 _V2 가 붙은 이유 — 구 키에는 **틀린 값이 캐시돼 있다.**
  // 예전 네이티브는 Sunmi 프린터 서비스의 `getPrinterSerialNo()` 를 먼저 봤는데,
  // 그건 프린터 보드 SN 이라 T2mini_s 에서 단말 SN(TN11211U40325)이 아닌 칩 UID
  // (4308425239384D5305D5FF30)를 돌려줬다(D3 MINI 는 둘이 같아 안 드러났다).
  // 키를 갈아 기존 설치가 다음 실행에 한 번 다시 읽게 한다. 구 키는 건드리지
  // 않는다(읽는 코드가 없어 그대로 사장된다).
  static const String KEY_DEVICE_SERIAL = "KOKONUT_DEVICE_SERIAL_V2";

  // Sentry 기기 대장(매장-시리얼-앱버전) 전송 디듀프 키. **기기 전역**이다 —
  // 매장 전환 자체가 재전송 사유라 매장 범위로 두면 감지하지 못한다.
  static const String KEY_SENTRY_INVENTORY_SIG = "KEY_SENTRY_INVENTORY_SIG";
  static const String KEY_SENTRY_INVENTORY_AT = "KEY_SENTRY_INVENTORY_AT";

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
  static const String KEY_PRINT_SHOW_ORDER_TYPE =
      "KEY_PRINT_SHOW_ORDER_TYPE"; // 영수증/주문서 출력물에 매장/포장 표기 (기본 true)

  // 라벨프린터 테스트 모드 설정 키
  static const String KEY_LABEL_AUTO_REPLY_MODE =
      "KOKONUT_LABEL_AUTO_REPLY_MODE"; // int: 0 or 1
  static const String KEY_LABEL_USE_FEED_TO_TEAR =
      "KOKONUT_LABEL_USE_FEED_TO_TEAR"; // bool (기본 true)
  static const String KEY_LABEL_USE_BACK_TO_PRINT =
      "KOKONUT_LABEL_USE_BACK_TO_PRINT"; // bool (기본 true)
  static const String KEY_LABEL_USE_CALIBRATE =
      "KOKONUT_LABEL_USE_CALIBRATE"; // bool (기본 false)
  static const String KEY_LABEL_USE_QR_PRINT =
      "KOKONUT_LABEL_USE_QR_PRINT"; // bool (기본 false)

  // ── 라벨 출력 카테고리 지정 (매장 범위 키) ────────────────────────────────
  //
  // 값이 카테고리 POS 코드·옵션그룹 POS 코드라 **매장마다 의미가 다르다**. 기기
  // 전역 키로 두면 다른 매장으로 로그인했을 때 이전 매장의 코드가 그대로 적용돼
  // 엉뚱한 상품이 걸러진다. 실제 키는 `<접두사><매장ID>` 형태이고 매장 ID 는
  // [getActiveStoreId] 가 정본이다.
  static const String KEY_LABEL_CATEGORY_FILTER_ON_PREFIX =
      "APPFIT_LABEL_CAT_FILTER_ON_"; // bool (기본 false)
  static const String KEY_LABEL_CATEGORY_KEYS_PREFIX =
      "APPFIT_LABEL_CAT_KEYS_"; // JSON array (정렬 저장)

  /// 장착한 라벨 용지 폭(mm). **레거시** — 40mm 가 서비스 대상에서 빠지면서
  /// (2026-09-03) 설정 화면의 선택 UI 와 출력 경로의 40/58 분기를 모두 제거했다.
  /// G30 은 58mm 연속용지 하나로 고정이라 이 값을 읽는 코드는 남아 있지 않다.
  /// 키 자체는 기존 단말에 저장된 값을 설명하기 위해 남긴다.
  static const String KEY_LABEL_PAPER_SIZE =
      "KOKONUT_LABEL_PAPER_SIZE"; // int mm (레거시, 기본 58)

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

  // 기기 관제(Fleet) 대상 매장 목록 캐시. 매장 코드를 콤마로 이어 저장한다.
  // 키가 없음(null) = "아직 한 번도 못 받아봄"(→ 관제 OFF), 빈 문자열 = 서버가
  // 내려준 "대상 없음". 둘의 판정 결과는 같지만 조회 실패 시 캐시를 덮어쓸지를
  // 가르므로 구분해서 저장한다.
  static const String KEY_FLEET_STORE_ALLOWLIST = "KEY_FLEET_STORE_ALLOWLIST";
  static const String KEY_FLEET_ALLOWLIST_FETCHED_AT =
      "KEY_FLEET_ALLOWLIST_FETCHED_AT";

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
      // 키오스크 설정(노출·출력·항상 자동접수) 강제 재조정 (정책당 1회)
      await _reconcileKioskSettings();
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

  /// 키오스크 설정 3종을 정책값으로 강제 전환 (정책당 1회)
  ///
  /// 노출 / 주문서·알림소리는 기본값이 ON → OFF 로 바뀌었지만, 기본값 변경만으로는
  /// 이미 true 가 저장된 기존 설치가 그대로 ON 으로 남는다. 반대로 '항상 자동접수'는
  /// 기본값이 ON 인데 과거에 꺼둔 기기는 false 가 저장돼 있다 — 노출까지 꺼진 상태에서
  /// 자동접수마저 꺼져 있으면 키오스크 주문이 화면에도 안 보이고 접수도 되지 않는다.
  /// 업데이트 후 첫 실행 때 한 번만 세 값을 정책값으로 덮어써 출발점을 맞춘다.
  /// 마커를 세워 이후 점주가 바꾼 값은 덮어쓰지 않는다.
  ///
  /// Windows 는 '주문서·알림소리' 정책이 반대(ON)라 이 강제 OFF 에서 제외한다 —
  /// 이 함수가 값을 쓰면 getKioskPrintAndSound() 의 Windows 기본값(ON)이
  /// 신규 설치에서도 무력화되기 때문. 대신 키를 건드리지 않아, 신규 설치는
  /// 기본값 ON, 이미 값이 저장된 기기는 그 값을 그대로 유지한다.
  Future<void> _reconcileKioskSettings() async {
    final isAlreadyDone =
        _prefs.getBool(KEY_KIOSK_SETTINGS_RECONCILED) ?? false;
    if (isAlreadyDone) return;

    try {
      final previousShow = _prefs.getBool(KEY_SHOW_KIOSK_ORDER);
      final previousPrintAndSound = _prefs.getBool(KEY_KIOSK_PRINT_AND_SOUND);
      final previousAutoAccept = _prefs.getBool(KEY_KIOSK_ALWAYS_AUTO_ACCEPT);

      await _prefs.setBool(KEY_SHOW_KIOSK_ORDER, false);
      if (!Platform.isWindows) {
        await _prefs.setBool(KEY_KIOSK_PRINT_AND_SOUND, false);
      }
      await _prefs.setBool(KEY_KIOSK_ALWAYS_AUTO_ACCEPT, true);
      await _prefs.setBool(KEY_KIOSK_SETTINGS_RECONCILED, true);

      final printAndSoundResult = Platform.isWindows
          ? '유지(Windows 정책 ON: ${getKioskPrintAndSound()})'
          : 'false';
      logger.i('[PreferenceService] 키오스크 설정 강제 재조정: '
          '노출 ${previousShow ?? '미설정'} → false, '
          '주문서·알림소리 ${previousPrintAndSound ?? '미설정'} → $printAndSoundResult, '
          '항상 자동접수 ${previousAutoAccept ?? '미설정'} → true');
    } catch (e, s) {
      logger.e('[PreferenceService] 키오스크 설정 재조정 중 오류 발생',
          error: e, stackTrace: s);
    }
  }

  /// 서버 환경이 저장되지 않은 경우 매장 ID 기반으로 자동 설정
  ///
  /// 마이그레이션이 스킵된 구버전 AppFit 사용자 또는 환경값이 유실된 경우를
  /// 대응하기 위해 매번 init() 시 확인. KEY_ENVIRONMENT가 이미 있으면 즉시 리턴.
  ///
  /// 매장 ID조차 없는 완전 신규 설치는 기기 타임존으로 국가를 추정해 로그인
  /// 화면 초기 선택값을 유도한다(정확도 100% 목적 아님 — 실패 시 기존과
  /// 동일하게 KEY_ENVIRONMENT 를 비워 'live' 폴백 유지, 사용자가 언제든
  /// 로그인 화면에서 재선택 가능).
  Future<void> _ensureEnvironmentIsSet() async {
    if (_prefs.containsKey(KEY_ENVIRONMENT)) return;
    final savedId = getId();
    if (savedId != null && savedId.isNotEmpty) {
      final env = BrandRegistry.environmentForStoreId(savedId) ?? 'live';
      await _prefs.setString(KEY_ENVIRONMENT, env);
      logger.i('[PreferenceService] 서버 환경 자동 복원: $env (ID: $savedId)');
      return;
    }
    final tzId = await PlatformService.getDeviceTimezoneId();
    final guessedEnv = _environmentFromTimezoneId(tzId);
    if (guessedEnv != null) {
      await _prefs.setString(KEY_ENVIRONMENT, guessedEnv);
      logger.i('[PreferenceService] 서버 환경 타임존 추정: $guessedEnv (tz: $tzId)');
    }
  }

  /// 타임존 ID/키 이름에서 국가를 추정. Android(IANA) 는 "Seoul"/"Tokyo",
  /// Windows(레지스트리 키 이름) 는 "Korea"/"Japan" 문자열을 포함하므로 양쪽
  /// 형식을 모두 검사. 판정 불가 시 null(호출 측이 기존 폴백 유지).
  static String? _environmentFromTimezoneId(String? tzId) {
    if (tzId == null) return null;
    if (tzId.contains('Seoul') || tzId.contains('Korea')) return 'live';
    if (tzId.contains('Tokyo') || tzId.contains('Japan')) return 'japanLive';
    return null;
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

  // 세션 매장 ID 저장 — 로그인 성공 시 항상 호출한다.
  //
  // KEY_MID(saveId)는 "아이디 저장" 체크박스에 종속돼 clearLoginInfo()에서
  // 지워진다. 반면 Dio 인터셉터(currentStoreId)·소켓 매장 검증·브랜드 해석·
  // Fleet 보고는 체크박스와 무관하게 "지금 로그인된 매장"을 알아야 하므로
  // 별도 키로 분리한다. 두 체크박스가 모두 꺼진 신규 매장 최초 로그인에서
  // KEY_MID 가 비어 인증 헤더가 누락되던 사고가 이 분리의 이유다.
  Future<void> setSessionStoreId(String id) async {
    await _prefs.setString(KEY_SESSION_STORE_ID, id.trim().toUpperCase());
  }

  // 세션 매장 ID 삭제 — 로그아웃/자격증명 정리 시에만 호출한다.
  // (clearLoginInfo() 에 넣으면 로그인 직전 경로에서 다시 지워져 버그가 재발한다)
  Future<void> clearSessionStoreId() async {
    await _prefs.remove(KEY_SESSION_STORE_ID);
  }

  /// 현재 로그인된 매장 ID (런타임 정본).
  ///
  /// 세션 값이 우선이고, 없으면 저장된 로그인 ID(KEY_MID)로 폴백한다.
  /// 폴백은 이 키가 없던 버전에서 업데이트돼 이미 로그인 상태인 기기를 위한 것.
  String? getActiveStoreId() {
    final session = _prefs.getString(KEY_SESSION_STORE_ID);
    if (session != null && session.trim().isNotEmpty) {
      return session.trim().toUpperCase();
    }
    return getId();
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
  ///
  /// Sunmi 시리얼을 얻지 못하는 단말의 fallback 이자, **Windows 기기의 관제
  /// 식별자 정본**이다(`DeviceIdentityService`). 관제 서버 D1 의 기기 테이블
  /// PK 가 `(app_type, device_id)` 라, 이 값이 바뀌면 그 기기는 새 행으로
  /// 등록되고 기존 행은 영구 유령으로 남는다.
  ///
  /// ⚠️ 그러므로 [KEY_INSTALL_ID] 를 지우는 코드를 추가하지 말 것. 로그아웃·
  /// 매장 전환·설정 초기화 어디에도 넣으면 안 되고, `_prefs.clear()` 도 마찬가지다.
  Future<String> getOrCreateInstallId() async {
    final existing = _prefs.getString(KEY_INSTALL_ID);
    if (existing != null && existing.isNotEmpty) return existing;
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    final id = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    await _prefs.setString(KEY_INSTALL_ID, id);
    return id;
  }

  /// 이미 만들어진 설치 UUID 만 읽는다. 없으면 null — **만들지 않는다.**
  ///
  /// 시리얼이 멀쩡한 기기에까지 UUID 를 새로 찍지 않으려는 것이다. 식별자로
  /// 쓸 값이 필요하면 [getOrCreateInstallId] 를 쓰고, 이 게터는 "있으면 같이
  /// 보고" 하는 보조 정보용이다.
  String? getInstallIdOrNull() => _prefs.getString(KEY_INSTALL_ID);

  /// 캐시된 기기 시리얼(네이티브 조회 1회 후 보관). 없으면 null.
  String? getCachedDeviceSerial() => _prefs.getString(KEY_DEVICE_SERIAL);

  Future<void> setCachedDeviceSerial(String serial) async =>
      _prefs.setString(KEY_DEVICE_SERIAL, serial);

  /// 마지막으로 Sentry 에 보낸 기기 대장 서명(`매장ID|시리얼|앱버전`). 없으면 null.
  String? getSentryInventorySignature() =>
      _prefs.getString(KEY_SENTRY_INVENTORY_SIG);

  /// 마지막 기기 대장 전송 시각(epoch ms). 없으면 null.
  int? getSentryInventorySentAt() => _prefs.getInt(KEY_SENTRY_INVENTORY_AT);

  /// 기기 대장 전송 기록. 서명과 시각은 **함께** 갱신해야 디듀프가 어긋나지 않는다.
  Future<void> setSentryInventorySent(String signature, DateTime at) async {
    await _prefs.setString(KEY_SENTRY_INVENTORY_SIG, signature);
    await _prefs.setInt(KEY_SENTRY_INVENTORY_AT, at.millisecondsSinceEpoch);
  }

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
  String getSound() {
    final raw = _prefs.getString(KEY_SOUND) ?? 'alert10.mp3'; //알림음 파일명
    // alert_speech.mp3 -> .m4a 교체. 레거시 파일명이 저장된 기기가 존재하지 않는
    // 에셋을 참조해 무음이 되는 것을 방지.
    return raw == 'alert_speech.mp3' ? 'alert_speech.m4a' : raw;
  }

  int getSoundNum() => _prefs.getInt(KEY_SOUND_NUM) ?? 5; //알림음 재생 횟수
  bool getIsNewOrder() => _prefs.getBool(KEY_IS_NEW_ORDER) ?? false; //
  bool getShowKioskOrder() =>
      _prefs.getBool(KEY_SHOW_KIOSK_ORDER) ?? false; //키오스크주문 노출여부 (기본 OFF)
  bool getShowPosOrder() =>
      _prefs.getBool(KEY_SHOW_POS_ORDER) ?? false; //POS주문 노출여부 (기본 OFF)

  /// 키오스크 주문 항상 자동접수 (기본 ON): 픽업 오더 자동 접수(getAutoReceipt) 와
  /// 무관하게 키오스크 주문은 항상 NEW→PREPARING 즉시 전이시킨다.
  bool getKioskAlwaysAutoAccept() =>
      _prefs.getBool(KEY_KIOSK_ALWAYS_AUTO_ACCEPT) ?? true;

  /// 키오스크주문 출력 및 알람소리 재생 여부
  ///
  /// 기본값이 플랫폼마다 다르다 — Android(Sunmi 등 주문접수 단말)는 키오스크가
  /// 자체 출력을 담당하므로 OFF, Windows POS 는 키오스크 주문의 주문서·알림음을
  /// POS 가 받아야 하므로 ON. 노출(getShowKioskOrder)은 양쪽 모두 OFF 유지.
  bool getKioskPrintAndSound() =>
      _prefs.getBool(KEY_KIOSK_PRINT_AND_SOUND) ?? Platform.isWindows;
  bool getPosPrintAndSound() =>
      _prefs.getBool(KEY_POS_PRINT_AND_SOUND) ??
      false; //POS주문 출력 및 알람소리 재생 여부 (기본 OFF)
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

  bool getPrintShowOrderType() =>
      _prefs.getBool(KEY_PRINT_SHOW_ORDER_TYPE) ??
      true; // 영수증/주문서 출력물에 매장/포장 표기 (default on)

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

  /// 장착한 라벨 용지 폭(mm). 레거시 — 읽는 코드 없음([KEY_LABEL_PAPER_SIZE] 참조).
  int getLabelPaperSizeMm() => _prefs.getInt(KEY_LABEL_PAPER_SIZE) ?? 58;

  // ── 라벨 출력 카테고리 지정 ───────────────────────────────────────────────
  //
  // 두 값 모두 매장 범위다. 매장이 확정되지 않았으면(로그인 전/세션 소실) 저장은
  // **false 를 반환**하고 조회는 기본값으로 수렴한다 — 조용히 성공한 척하면
  // 설정이 사라진 이유를 점주가 알 수 없다.
  //
  // SharedPreferences 는 변경 알림이 없다. 저장한 화면이
  // `ref.invalidate(labelOutputPolicyProvider)` 를 호출하는 것이 계약이다.

  String? _storeScopedKey(String prefix) {
    final storeId = getActiveStoreId();
    if (storeId == null || storeId.isEmpty) return null;
    return '$prefix$storeId';
  }

  /// JSON 배열 문자열 → `List<String>`. 손상된 값은 빈 목록으로 흡수한다
  /// (라벨 설정에서 빈 목록 = 전체 출력 = 라벨 소실 0).
  List<String> _readJsonStringList(String? key) {
    if (key == null) return const [];
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .map((e) => e?.toString() ?? '')
          .where((e) => e.isNotEmpty)
          .toList();
    } catch (e) {
      logger.w('[라벨설정] JSON 파싱 실패 — 빈 목록으로 처리 ($key)', error: e);
      return const [];
    }
  }

  Future<bool> _writeJsonStringList(String? key, List<String> values) async {
    if (key == null) return false;
    final cleaned = values.where((v) => v.trim().isNotEmpty).toList();
    await _prefs.setString(key, jsonEncode(cleaned));
    return true;
  }

  /// 라벨 출력 카테고리 지정 ON/OFF. OFF 면 모든 카테고리가 출력 대상.
  bool getLabelCategoryFilterOn() {
    final key = _storeScopedKey(KEY_LABEL_CATEGORY_FILTER_ON_PREFIX);
    if (key == null) return false;
    return _prefs.getBool(key) ?? false;
  }

  Future<bool> setLabelCategoryFilterOn(bool value) async {
    final key = _storeScopedKey(KEY_LABEL_CATEGORY_FILTER_ON_PREFIX);
    if (key == null) return false;
    await _prefs.setBool(key, value);
    return true;
  }

  /// 출력 대상 카테고리 키 집합. 순서에 의미가 없어 정렬 저장한다
  /// (같은 선택이 항상 같은 문자열 → 로그/diff 안정).
  Set<String> getLabelCategoryKeys() =>
      _readJsonStringList(_storeScopedKey(KEY_LABEL_CATEGORY_KEYS_PREFIX))
          .toSet();

  Future<bool> setLabelCategoryKeys(Set<String> keys) => _writeJsonStringList(
        _storeScopedKey(KEY_LABEL_CATEGORY_KEYS_PREFIX),
        keys.toList()..sort(),
      );

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

  Future<void> setPrintShowOrderType(bool value) async {
    await _prefs.setBool(KEY_PRINT_SHOW_ORDER_TYPE, value);
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

  Future<void> setLabelPaperSizeMm(int value) async {
    await _prefs.setInt(KEY_LABEL_PAPER_SIZE, value);
  }

  // 키오스크 주문 노출 설정
  Future<void> setShowKioskOrder(bool value) async {
    await _prefs.setBool(KEY_SHOW_KIOSK_ORDER, value);
  }

  // POS 주문 노출 설정
  Future<void> setShowPosOrder(bool value) async {
    await _prefs.setBool(KEY_SHOW_POS_ORDER, value);
  }

  // 키오스크 주문 출력 및 소리 설정
  Future<void> setKioskPrintAndSound(bool value) async {
    await _prefs.setBool(KEY_KIOSK_PRINT_AND_SOUND, value);
  }

  // POS 주문 출력 및 소리 설정
  Future<void> setPosPrintAndSound(bool value) async {
    await _prefs.setBool(KEY_POS_PRINT_AND_SOUND, value);
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

  // 관제 대상 매장 목록 캐시 조회. null = 아직 한 번도 못 받아봄(관제 OFF).
  String? getFleetStoreAllowlist() =>
      _prefs.getString(KEY_FLEET_STORE_ALLOWLIST);

  // 관제 대상 매장 목록 캐시 저장 (조회 성공 시에만 호출)
  Future<void> setFleetStoreAllowlist(String value) async {
    await _prefs.setString(KEY_FLEET_STORE_ALLOWLIST, value);
    await _prefs.setString(
      KEY_FLEET_ALLOWLIST_FETCHED_AT,
      DateTime.now().toIso8601String(),
    );
  }

  // 관제 대상 매장 목록을 마지막으로 받아온 시각 (진단용)
  String? getFleetAllowlistFetchedAt() =>
      _prefs.getString(KEY_FLEET_ALLOWLIST_FETCHED_AT);

  // ── 브랜드 판별 레거시 헬퍼 ──────────────────────────────────────────────
  // prefix 매칭 로직의 단일 출처는 [BrandRegistry]. 아래 헬퍼들은 그 위의 얇은
  // 어댑터이며, 신규 코드는 BrandRegistry.resolveOrNull / currentBrandProvider 사용.

  /// TPCP 매장 여부를 ID 문자열로 판별. (마이그레이션/로그인처럼 ID 저장 전 사용)
  static bool isTPCPStoreId(String? storeId) =>
      BrandRegistry.resolveOrNull(storeId)?.key == BrandKey.tpcp;

  /// 현재 저장된 매장 ID가 TPCP(일본 특화) 매장인지 반환.
  bool isTpcpStore() => isTPCPStoreId(getId());

  /// 매머드 매장 여부를 ID 문자열로 판별. MMTH(운영)·MHST(스테이징) 둘 다.
  static bool isMammothStoreId(String? storeId) =>
      BrandRegistry.resolveOrNull(storeId)?.key == BrandKey.mammoth;

  /// 현재 저장된 매장 ID가 매머드 매장인지 반환.
  bool isMammothStore() => isMammothStoreId(getId());

  /// 마하테이스트(mahataste) 매장 여부를 ID 문자열로 판별.
  static bool isMATAStoreId(String? storeId) =>
      BrandRegistry.resolveOrNull(storeId)?.key == BrandKey.mata;

  /// 현재 저장된 매장 ID가 마하테이스트(mahataste) 매장인지 반환.
  bool isMataStore() => isMATAStoreId(getId());

  // ── Windows 전용 설치 환경 점검 ─────────────────────────────────────────────

  /// Defender 예외 상태를 마지막으로 점검한 날짜(`yyyy-MM-dd`).
  ///
  /// 점검은 powershell 프로세스를 띄우므로 하루 1회로 제한한다 —
  /// `windows_startup_maintenance.dart` 참조.
  static const String _keyDefenderCheckDate = 'APPFIT_DEFENDER_CHECK_DATE';

  String? getDefenderCheckDate() => _prefs.getString(_keyDefenderCheckDate);
  Future<void> setDefenderCheckDate(String date) async =>
      _prefs.setString(_keyDefenderCheckDate, date);

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

  /// Windows 외부 영수증 프린터가 **현재 붙어 있는 경로의 종류**.
  ///
  /// 사용자가 고르는 설정이 아니라 **재연결 스캔이 채택한 결과**다 — 케이블이
  /// 시리얼이든 USB든 앱이 알아서 잡는 것이 목표라, 사용자에게 종류를 묻지 않는다.
  /// (수동 교정은 설정 화면의 통합 드롭다운에서 하고, 그때도 이 값이 함께 갱신된다.)
  ///
  /// 같은 USB 영수증 프린터라도 Windows 바인딩이 두 갈래로 갈리며 **서로소**다:
  /// - [extPrinterConnCom] : 프린터가 CDC-ACM 을 노출해 가상 COM 포트가 생기거나
  ///   물리 RS-232 로 붙은 경우 (PR800 = `USB\VID_0D28&PID_4C59` → COM3).
  ///   `ComPortPrintService` 가 처리하며 식별자는 [getComPortName].
  /// - [extPrinterConnUsbPrint] : USB Printer class 만 노출해 usbprint.sys 가 붙고
  ///   COM 포트가 없는 경우 (POSBANK A8 = `USB\VID_0483&PID_A319`).
  ///   `UsbPrintService` 가 처리하며 식별자는 [getUsbPrintDevicePath].
  ///
  /// **기본값은 COM** 이라 기존 현장 단말(저장된 COM 포트 보유)의 동작은 그대로다.
  static const String _keyExtPrinterConn = 'APPFIT_EXT_PRINTER_CONN';
  static const String extPrinterConnCom = 'com';
  static const String extPrinterConnUsbPrint = 'usbprint';

  String getExternalPrinterConnection() {
    final v = _prefs.getString(_keyExtPrinterConn);
    return v == extPrinterConnUsbPrint
        ? extPrinterConnUsbPrint
        : extPrinterConnCom;
  }

  Future<void> setExternalPrinterConnection(String mode) async =>
      _prefs.setString(
        _keyExtPrinterConn,
        mode == extPrinterConnUsbPrint
            ? extPrinterConnUsbPrint
            : extPrinterConnCom,
      );

  /// usbprint 경로의 장치 인터페이스 경로. 재연결 스캔이 채택했거나 사용자가
  /// 드롭다운에서 고른 값.
  ///
  /// null 이면 전송 경로는 `PrinterNoDevice` 다 — COM 경로의 `comPort == null` 과
  /// 같은 규율. 채택은 **ESC/POS 응답을 확인한 장치**에 대해서만 일어나고 라벨
  /// 프린터 VID 는 열거 단계에서 이미 빠져 있다. "목록에 하나뿐이니 probe 없이
  /// 그냥 쓰기" 같은 완화는 넣지 말 것 — 그게 Winspool 금지의 실질이다.
  ///
  /// 주의: 이 경로는 USB 허브의 물리 포트를 포함하므로 **다른 포트로 옮겨 꽂으면
  /// 값이 바뀐다**. 그래서 재연결 스캔이 저장값 실패 시 다른 후보까지 훑는다.
  static const String _keyUsbPrintDevicePath = 'APPFIT_USB_PRINT_DEVICE_PATH';

  String? getUsbPrintDevicePath() => _prefs.getString(_keyUsbPrintDevicePath);
  Future<void> setUsbPrintDevicePath(String path) async =>
      _prefs.setString(_keyUsbPrintDevicePath, path);

  /// 외부 영수증 프린터의 1행 컬럼 수. **Windows/Android 공통** — 같은 A8 이
  /// Sunmi 단말에 물려도 42 컬럼이다.
  ///
  /// null = 미설정이며 호출부가 `ReceiptEscPosBuilder.defaultColumns`(48)로
  /// 폴백한다. ESC/POS 에 컬럼 수 질의가 없어 자동 판별이 불가능하므로
  /// (`GS W` 는 쓰기 전용) 값은 ① 알려진 USB 기종 프리시드 ② 눈금자 출력을 보고
  /// 사용자가 고른 값 두 경로로만 채워진다.
  ///
  /// 프리시드는 **이 값이 null 일 때만** 개입한다 — 사용자가 한 번이라도 고른
  /// 뒤에는 재연결로 대상이 바뀌어도 그 선택을 덮지 않는다.
  static const String _keyExtPrinterColumns = 'APPFIT_EXT_PRINTER_COLUMNS';

  int? getExternalPrinterColumns() => _prefs.getInt(_keyExtPrinterColumns);
  Future<void> setExternalPrinterColumns(int columns) async =>
      _prefs.setInt(_keyExtPrinterColumns, columns);
}
