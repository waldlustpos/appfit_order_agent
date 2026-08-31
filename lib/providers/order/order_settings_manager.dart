import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:appfit_order_agent/services/preference_service.dart';
import 'package:appfit_order_agent/utils/logger.dart';

/// 주문 관련 설정 관리 클래스
/// 알람소리, 볼륨, 자동접수 등의 설정을 관리합니다.
class OrderSettingsManager {
  final Ref ref;
  final PreferenceService _preferenceService;

  // 알람소리 관련 설정
  String _soundFileName = '';
  int _playCount = 0;
  double _volume = 1.0;

  OrderSettingsManager(this.ref, this._preferenceService);

  // Getters
  String get soundFileName => _soundFileName;
  int get playCount => _playCount;
  double get volume => _volume;

  /// 알람소리 설정 로드
  void loadSoundSettings() {
    _soundFileName = _preferenceService.getSound();
    _playCount = _preferenceService.getSoundNum();
    final volumeValue = _preferenceService.getVolume();
    _volume = volumeValue / 10.0;

    logger.d(
        '알람소리 설정 로드 - 파일: $_soundFileName, 횟수: $_playCount, 볼륨: $_volume (원본값: $volumeValue)');

    logger.d(
        'Sound settings loaded: file=$_soundFileName, count=$_playCount, volume=$_volume');
  }

  /// 자동접수 설정 업데이트
  Future<void> updateAutoReceipt(bool value) async {
    logger.d('updateAutoReceipt 호출 - 새로운 값: $value');
    await _preferenceService.setAutoReceipt(value);
    logger.d('updateAutoReceipt 완료 - PreferenceService 업데이트됨: $value');
  }

  /// KDS 모드 NEW 주문 자동접수 토글 업데이트
  Future<void> updateKdsAcceptOrders(bool value) async {
    logger.d('updateKdsAcceptOrders 호출 - 새로운 값: $value');
    await _preferenceService.setKdsAcceptOrders(value);
    logger.d('updateKdsAcceptOrders 완료 - PreferenceService 업데이트됨: $value');
  }

  /// 설정 업데이트 (외부에서 호출)
  void updateSoundSettings() {
    loadSoundSettings();
    logger.d('Sound settings reloaded for OrderSettingsManager.');
  }

  /// 로그아웃 시 설정 초기화
  void clearOnLogout() {
    _soundFileName = '';
    _playCount = 0;
    _volume = 1.0;
    logger.d('[OrderSettingsManager] 로그아웃 시 설정 초기화 완료');
  }

  /// 로그인 후 설정 재로드
  void reloadAfterLogin() {
    logger.d('[OrderSettingsManager] 설정 재로드 시작');
    loadSoundSettings();
    logger.d('[OrderSettingsManager] 설정 재로드 완료');
    logger.d(
        '[OrderSettingsManager] 알람소리 설정 상태 - 파일: $_soundFileName, 횟수: $_playCount, 볼륨: $_volume');
  }
}
