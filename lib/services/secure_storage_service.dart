import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kokonut_order_agent/utils/logger.dart';

/// 보안 저장소 서비스
///
/// JWT 토큰 등 민감한 정보를 암호화하여 저장합니다.
class SecureStorageService {
  static final SecureStorageService _instance =
      SecureStorageService._internal();

  // Singleton pattern
  factory SecureStorageService() {
    return _instance;
  }

  SecureStorageService._internal();

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );

  /// 데이터 저장
  Future<void> write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
      logger.d('[SecureStorage] Write success: $key');
    } catch (e) {
      logger.e('[SecureStorage] Write error: $key, $e');
      rethrow;
    }
  }

  /// 데이터 읽기
  Future<String?> read(String key) async {
    try {
      final value = await _storage.read(key: key);
      return value;
    } catch (e) {
      logger.e('[SecureStorage] Read error: $key, $e');
      return null;
    }
  }

  /// 데이터 삭제
  Future<void> delete(String key) async {
    try {
      await _storage.delete(key: key);
      logger.d('[SecureStorage] Delete success: $key');
    } catch (e) {
      logger.e('[SecureStorage] Delete error: $key, $e');
    }
  }

  /// 모든 데이터 삭제
  Future<void> deleteAll() async {
    try {
      await _storage.deleteAll();
      logger.i('[SecureStorage] All data deleted');
    } catch (e) {
      logger.e('[SecureStorage] DeleteAll error: $e');
    }
  }

  // Keys
  static const String appFitProjectId = 'appfit_project_id';
  static const String appFitProjectApiKey = 'appfit_project_api_key';
}

final secureStorageServiceProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});
