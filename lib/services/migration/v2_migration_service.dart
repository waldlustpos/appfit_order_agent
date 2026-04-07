import 'package:shared_preferences/shared_preferences.dart';
import 'package:appfit_order_agent/services/preference_service.dart';
import 'v2_migration_logger.dart';

/// 구앱(kokonut_order_agent_v2) → 신규앱(appfit_order_agent) 마이그레이션 서비스
///
/// 동일한 Android 패키지명과 SharedPreferences 네임스페이스를 공유하므로,
/// 앱 업데이트 시 기존 설정 데이터가 자동으로 유지됩니다.
/// 이 서비스는 볼륨 범위 변환, 로그인 초기화, 서버 환경 설정 등을 수행합니다.
class V2MigrationService {
  static const String KEY_MIGRATION_V2_COMPLETED =
      'migration_v2_to_appfit_completed';
  static const String KEY_MIGRATED_OLD_ID = 'migration_v2_old_id';

  /// 테스트용 목 매핑 테이블 (대소문자 무시, 키는 대문자로 저장)
  /// 실제 매핑 API 완성 후 제거 또는 kDebugMode 조건 하에서만 동작하도록 전환 예정
  static const Map<String, String> _mockMappingTable = {
    'K0130101': 'TPCP00002',
  };

  // 싱글톤
  static final V2MigrationService _instance = V2MigrationService._internal();
  factory V2MigrationService() => _instance;
  V2MigrationService._internal();

  /// 마이그레이션이 이미 완료되었는지 확인
  bool isCompleted(SharedPreferences prefs) {
    return prefs.getBool(KEY_MIGRATION_V2_COMPLETED) ?? false;
  }

  /// Phase 1: 설정 마이그레이션 (앱 시작 시, PreferenceService.init()에서 호출)
  ///
  /// SharedPreferences의 구앱 데이터를 감지하고:
  /// - 볼륨 범위 변환 (0-10 → 0-15)
  /// - 프린터 설정 보존 플래그 설정
  /// - 로그인 정보 초기화 (비밀번호 삭제, 자동로그인 OFF)
  /// - 서버 환경 설정 (ID 접두사 기반)
  Future<bool> runSettingsMigration(SharedPreferences prefs) async {
    try {
      // 이미 완료된 경우 스킵
      if (isCompleted(prefs)) {
        return true;
      }

      // 구앱 데이터 존재 여부 확인
      if (!_isOldAppData(prefs)) {
        // 신규 설치 — 마이그레이션 불필요, 플래그만 설정
        V2MigrationLogger.log('신규 설치 감지. 마이그레이션 스킵.');
        await prefs.setBool(KEY_MIGRATION_V2_COMPLETED, true);
        await V2MigrationLogger.flush();
        return true;
      }

      final oldId = prefs.getString(PreferenceService.KEY_MID) ?? '';
      V2MigrationLogger.log('V2 마이그레이션 시작. 구앱 ID: $oldId');

      // --- 설정 마이그레이션 ---
      await _migrateVolume(prefs);
      await _migratePrinterFlags(prefs);
      _logAutoCarrySettings(prefs);

      // --- 로그인 정보 초기화 ---
      await _resetLoginInfo(prefs, oldId);

      // --- 서버 환경 설정 ---
      await _setEnvironment(prefs, oldId);

      // --- 마이그레이션 완료 ---
      await prefs.setBool(KEY_MIGRATION_V2_COMPLETED, true);
      V2MigrationLogger.log('V2 마이그레이션 Phase 1 완료');
      await V2MigrationLogger.flush();

      return true;
    } catch (e) {
      V2MigrationLogger.error('마이그레이션 중 오류 발생. 스킵 처리.', e);
      // 오류 시에도 completed 플래그를 설정하여 무한 재시도 방지
      await prefs.setBool(KEY_MIGRATION_V2_COMPLETED, true);
      await V2MigrationLogger.flush();
      return false;
    }
  }

  /// Phase 2: ID 매핑 (로그인 화면 진입 시 호출)
  ///
  /// 먼저 목 매핑 테이블에서 확인하고, 없으면 실제 API를 호출합니다.
  /// API가 아직 준비되지 않았으므로 현재는 목 테이블 + 미구현 API 구조입니다.
  Future<String?> fetchMappedId(String oldId) async {
    final normalizedId = oldId.trim().toUpperCase();

    // 1. 목 매핑 테이블 확인
    if (_mockMappingTable.containsKey(normalizedId)) {
      final mappedId = _mockMappingTable[normalizedId]!;
      V2MigrationLogger.log('ID 매핑 성공 (mock): $oldId → $mappedId');
      return mappedId;
    }

    // 2. 실제 매핑 API 호출 (TODO: 백엔드 API 완성 후 구현)
    try {
      final mappedId = await _callMappingApi(normalizedId);
      if (mappedId != null) {
        V2MigrationLogger.log('ID 매핑 성공 (API): $oldId → $mappedId');
        return mappedId;
      }
    } catch (e) {
      V2MigrationLogger.warn('ID 매핑 API 실패: $e. 수동 입력 필요.');
    }

    return null;
  }

  // --- Private 메서드 ---

  /// 구앱(kokonut_order_agent_v2) 데이터 존재 여부 판별
  ///
  /// 구앱 ID 형식: 'K' + 숫자 (예: K0130002, k0130002)
  /// AppFit ID 형식: 알파벳 4자 + 숫자 (예: TPCP00002, MHST00001)
  bool _isOldAppData(SharedPreferences prefs) {
    final savedId = prefs.getString(PreferenceService.KEY_MID);
    if (savedId == null || savedId.isEmpty) return false;
    return RegExp(r'^[kK]\d+$').hasMatch(savedId);
  }

  /// 볼륨 비례 변환 (0-10 → 0-15)
  Future<void> _migrateVolume(SharedPreferences prefs) async {
    final oldVolume = prefs.getInt(PreferenceService.KEY_VOLUME);
    if (oldVolume == null) return;

    // 구앱 범위(0-10)에 해당하는 경우에만 변환
    if (oldVolume <= 10) {
      final newVolume = _mapVolume(oldVolume);
      await prefs.setInt(PreferenceService.KEY_VOLUME, newVolume);
      V2MigrationLogger.log('볼륨 변환: $oldVolume → $newVolume');
    } else {
      V2MigrationLogger.log('볼륨 값이 이미 신규 범위: $oldVolume (변환 스킵)');
    }
  }

  /// 볼륨 값 변환: (old * 15 / 10).round(), 0-15 범위로 clamp
  int _mapVolume(int oldVolume) {
    final clamped = oldVolume.clamp(0, 10);
    return (clamped * 15 / 10).round().clamp(0, 15);
  }

  /// 프린터 설정 보존 플래그 설정
  /// 구앱의 프린터 설정이 존재하면 KEY_PRINTER_DEFAULT_SET=true로 설정하여
  /// _initializePrinterDefaults()가 덮어쓰지 않도록 보호
  Future<void> _migratePrinterFlags(SharedPreferences prefs) async {
    final hasBuiltin = prefs.containsKey(PreferenceService.KEY_USE_BUILTIN_PRINTER);
    final hasExternal = prefs.containsKey(PreferenceService.KEY_USE_EXTERNAL_PRINTER);
    final hasPrint = prefs.containsKey(PreferenceService.KEY_USE_PRINT);

    if (hasBuiltin || hasExternal || hasPrint) {
      await prefs.setBool(PreferenceService.KEY_PRINTER_DEFAULT_SET, true);
      V2MigrationLogger.log(
        '프린터 설정 보존: '
        'usePrint=${prefs.getBool(PreferenceService.KEY_USE_PRINT)}, '
        'builtin=${prefs.getBool(PreferenceService.KEY_USE_BUILTIN_PRINTER)}, '
        'external=${prefs.getBool(PreferenceService.KEY_USE_EXTERNAL_PRINTER)}',
      );
    }
  }

  /// 자동이전 설정 로그 기록 (동일 키이므로 변환 불필요)
  void _logAutoCarrySettings(SharedPreferences prefs) {
    V2MigrationLogger.log(
      '자동이전 설정: '
      'autoLaunch=${prefs.getBool(PreferenceService.KEY_AUTO_LAUNCH)}, '
      'autoReceipt=${prefs.getBool(PreferenceService.KEY_AUTO_RECEIPT)}, '
      'sound=${prefs.getString(PreferenceService.KEY_SOUND)}, '
      'soundNum=${prefs.getInt(PreferenceService.KEY_SOUND_NUM)}, '
      'showKiosk=${prefs.getBool(PreferenceService.KEY_SHOW_KIOSK_ORDER)}, '
      'kioskPrintSound=${prefs.getBool(PreferenceService.KEY_KIOSK_PRINT_AND_SOUND)}',
    );
  }

  /// 로그인 정보 초기화
  Future<void> _resetLoginInfo(SharedPreferences prefs, String oldId) async {
    // 구앱 ID를 백업 키에 저장 (로그인 화면에서 매핑 API 호출 시 사용)
    await prefs.setString(KEY_MIGRATED_OLD_ID, oldId);

    // 비밀번호 삭제
    await prefs.setString(PreferenceService.KEY_PWD, '');

    // 자동로그인 해제
    await prefs.setString(PreferenceService.KEY_IS_AUTO_LOGIN, 'F');

    // ID 저장 활성화 (매핑된 ID가 로그인 화면에 표시되도록)
    await prefs.setString(PreferenceService.KEY_IS_SAVE_ID, 'T');

    V2MigrationLogger.log('로그인 정보 초기화 완료. 자동로그인 해제됨. 구앱 ID 백업: $oldId');
  }

  /// 서버 환경 설정 (ID 접두사 기반)
  Future<void> _setEnvironment(SharedPreferences prefs, String oldId) async {
    final env = oldId.toUpperCase().startsWith('TPCP') ? 'japanLive' : 'live';
    await prefs.setString(PreferenceService.KEY_ENVIRONMENT, env);
    V2MigrationLogger.log('서버 환경 설정: $env (ID: $oldId)');
  }

  /// 실제 매핑 API 호출 (TODO: 백엔드 API 완성 후 구현)
  Future<String?> _callMappingApi(String storeId) async {
    // TODO: 실제 API 엔드포인트가 확정되면 구현
    // 예시:
    // final dio = ... ;
    // final response = await dio.post('/v0/migration/store-mapping', data: {'oldStoreId': storeId});
    // return response.data['newStoreId'] as String?;
    return null;
  }
}
