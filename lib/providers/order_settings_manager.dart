import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audioplayers/audioplayers.dart';
import '../services/preference_service.dart';
import '../utils/logger.dart';

/// 주문 관련 설정 관리 클래스
/// 알람소리, 볼륨, 자동접수 등의 설정을 관리합니다.
class OrderSettingsManager {
  final Ref ref;
  final PreferenceService _preferenceService;

  // 알람소리 관련 설정
  String _soundFileName = '';
  int _playCount = 0;
  double _volume = 1.0;


  // AudioPlayer 상태
  bool _isAudioPlayerDisposed = false;

  OrderSettingsManager(this.ref, this._preferenceService);

  // Getters
  String get soundFileName => _soundFileName;
  int get playCount => _playCount;
  double get volume => _volume;
  bool get isAudioPlayerDisposed => _isAudioPlayerDisposed;

  /// 알람소리 설정 로드
  void loadSoundSettings() {
    _soundFileName = _preferenceService.getSound();
    _playCount = _preferenceService.getSoundNum();
    final volumeValue = _preferenceService.getVolume();
    _volume = volumeValue / 15.0;

    logger.d(
        '알람소리 설정 로드 - 파일: $_soundFileName, 횟수: $_playCount, 볼륨: $_volume (원본값: $volumeValue)');

    logger.d(
        'Sound settings loaded: file=$_soundFileName, count=$_playCount, volume=$_volume');
  }

  /// AudioPlayer 설정 적용
  void applyAudioPlayerSettings(AudioPlayer audioPlayer) {
    if (_isAudioPlayerDisposed) {
      logger.w('AudioPlayer가 dispose된 상태라서 설정을 건너뜀');
      return;
    }

    try {
      audioPlayer.setVolume(_volume);

      var audioContext = AudioContext(
        android: const AudioContextAndroid(
          audioFocus: AndroidAudioFocus.none,
        ),
      );
      audioPlayer.setAudioContext(audioContext);
      logger.d('AudioPlayer 설정 완료 - 볼륨: $_volume, AudioContext 설정됨');
    } catch (e, s) {
      logger.w('Error setting audio player settings: $e');
    }
  }



  /// 자동접수 설정 업데이트
  Future<void> updateAutoReceipt(bool value) async {
    logger.d('updateAutoReceipt 호출 - 새로운 값: $value');
    await _preferenceService.setAutoReceipt(value);
    logger.d('updateAutoReceipt 완료 - PreferenceService 업데이트됨: $value');
  }

  /// 설정 업데이트 (외부에서 호출)
  void updateSoundSettings() {
    loadSoundSettings();
    logger.d('Sound settings reloaded for OrderSettingsManager.');
  }


  /// AudioPlayer dispose 상태 설정
  void setAudioPlayerDisposed(bool disposed) {
    _isAudioPlayerDisposed = disposed;
  }

  /// 로그아웃 시 설정 초기화
  void clearOnLogout() {
    _soundFileName = '';
    _playCount = 0;
    _volume = 1.0;
    _isAudioPlayerDisposed = false;
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
