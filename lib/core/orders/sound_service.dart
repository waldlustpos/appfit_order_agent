import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:appfit_order_agent/services/preference_service.dart';
import 'package:appfit_order_agent/utils/logger.dart';
import 'package:appfit_order_agent/providers/preference_provider.dart';

class SoundService {
  final Ref ref;
  SoundService(this.ref);

  late final PreferenceService _preferenceService =
      ref.read(preferenceServiceProvider);

  // Player & settings
  AudioPlayer _player = AudioPlayer();
  bool _isDisposed = false;
  String _soundFileName = '';
  int _playCount = 0;
  double _volume = 0.5;
  // 현재 _player 인스턴스에 마지막으로 적용된 볼륨. null 이면 미적용(새 플레이어).
  // 재생마다 불필요한 setVolume MethodChannel 호출(알림 순간 마이크로 잭)을 막는다.
  double? _appliedVolume;
  AssetSource? _soundSource;

  // 앱 시작 시 알람소리 재생 제한
  Timer? _startupTimer;

  // 예약된 알람 횟수 목록을 관리하는 큐
  final List<int> _alarmQueue = [];

  // Playback control
  bool _isPlaying = false;
  int _remainingPlays = 0;
  int _sessionId = 0;
  Duration? _cachedDuration;
  static const Duration _defaultDelay = Duration(milliseconds: 2000);
  static const Duration _playbackBuffer = Duration(milliseconds: 200);

  /// dispose 된 AudioPlayer 를 재초기화한다.
  /// Sentry APPFIT-ORDER-AGENT-N: `Player has not yet been created or has
  /// already been disposed.` 발생 시 복구용.
  void _ensurePlayer() {
    if (_isDisposed) {
      logger.w('[SoundService] 플레이어 dispose 상태 감지, 재초기화');
      _player = AudioPlayer();
      _isDisposed = false;
      _appliedVolume = null; // 새 인스턴스는 볼륨 재적용 필요
    }
  }

  /// 볼륨이 마지막 적용값과 다를 때만 실제 setVolume 호출.
  /// 성공 시 true, PlatformException(disposed) 시 false 반환.
  bool _applyVolumeIfChanged() {
    if (_appliedVolume == _volume) return true;
    try {
      _player.setVolume(_volume);
      _appliedVolume = _volume;
      return true;
    } on PlatformException catch (e) {
      logger.w('[SoundService] setVolume 실패 (disposed 가능성): $e');
      _isDisposed = true;
      _appliedVolume = null;
      return false;
    }
  }

  void reloadSettings() {
    try {
      final String newSoundFileName = _preferenceService.getSound();
      final bool soundChanged = newSoundFileName != _soundFileName;
      _soundFileName = newSoundFileName;
      _playCount = _preferenceService.getSoundNum();
      _volume = _preferenceService.getVolume() / 10.0;

      // 재생 중 재호출 시 캐시된 duration이 날아가 다음 단위 재생 간격이
      // _defaultDelay(2s)로 급증하는 문제를 막기 위해, 파일이 바뀐 경우에만
      // 소스/캐시를 재생성한다.
      if (soundChanged || _soundSource == null) {
        _soundSource = AssetSource('sounds/' + _soundFileName);
        _cachedDuration = null;
      }

      if (!_isDisposed) {
        _applyVolumeIfChanged();
        logger.i(
            '[SoundService] 설정 로드: file=$_soundFileName, count=$_playCount, vol=$_volume');
      }
    } catch (e, s) {
      logger.w('[SoundService] 설정 로드 실패', error: e, stackTrace: s);
    }
  }

  Future<void> playNotificationSound({int? customPlayCount}) async {
    try {
      // 항상 최신 설정 로드 (설정 변경 시 반영)
      reloadSettings();

      _ensurePlayer();

      if (_soundFileName.isEmpty || _playCount == 0) {
        logger.w('[SoundService] 사운드 설정 없음, 재생 건너뜀');
        return;
      }

      _soundSource ??= AssetSource('sounds/' + _soundFileName);
      if (_soundSource == null) {
        logger.w('[SoundService] 사운드 소스 없음');
        return;
      }

      final int playCountToUse = customPlayCount ?? _playCount;

      // 큐에 추가
      _alarmQueue.add(playCountToUse);
      logger.i(
          '[SoundService] 큐에 알람 작업 추가: $playCountToUse회 재생 예정 (대기열 수: ${_alarmQueue.length})');

      // 현재 재생 중이 아니면 바로 플래그를 잡고 큐 처리를 시작해 Race Condition 방지
      if (!_isPlaying) {
        _isPlaying = true;

        // 캐시 기간이 없다면 비동기로 채운 후 알람 처리
        if (_cachedDuration == null) {
          try {
            await _player.setSource(_soundSource!);
            _cachedDuration = await _player.getDuration();
          } on PlatformException catch (e) {
            logger.w('[SoundService] setSource 실패 (disposed 가능): $e');
            _isDisposed = true;
            _isPlaying = false;
            return;
          } catch (e, s) {
            logger.w('[SoundService] 길이 조회 실패, 기본 지연 사용: $e');
          }
        }

        if (!_applyVolumeIfChanged()) {
          _isPlaying = false;
          return;
        }
        _processNextAlarm();
      }
    } catch (e, s) {
      logger.e('[SoundService] 재생 준비 중 오류', error: e, stackTrace: s);
      _isPlaying = false;
    }
  }

  void _processNextAlarm() {
    if (_alarmQueue.isEmpty) {
      logger.i('[SoundService] 모든 큐 작업 완료, 대기 중');
      _isPlaying = false;
      return;
    }

    // 다음 작업 꺼내기
    final int nextCount = _alarmQueue.removeAt(0);
    logger.i(
        '[SoundService] 큐 작업 시작: 총 $nextCount회 재생 시작 (남은 대기열: ${_alarmQueue.length})');

    _isPlaying = true;
    _remainingPlays = nextCount;
    _sessionId++; // 새 작업 세션 아이디 갱신

    _loopPlay(_sessionId);
  }

  Future<void> _loopPlay(int session) async {
    if (session != _sessionId) {
      logger.d(
          '[SoundService] 세션 불일치, 종료: session=$session, _sessionId=$_sessionId');
      return;
    }

    if (!_isPlaying || _remainingPlays <= 0) {
      logger.d('[SoundService] 단일 주문 재생 작업 종료: session=$session');
      // 해당 큐의 작업 완료 후, 다음 큐 작업 실행
      _processNextAlarm();
      return;
    }

    if (_isDisposed) {
      logger.w('[SoundService] 재생 중 플레이어 dispose 감지, 세션 종료');
      _isPlaying = false;
      _remainingPlays = 0;
      return;
    }

    try {
      logger.d('[SoundService] 단위 재생 시작: 해당 세션 남은 횟수=$_remainingPlays');
      await _player.stop();
      await _player.play(_soundSource!);

      _remainingPlays--;

      final Duration delay =
          (_cachedDuration ?? _defaultDelay) + _playbackBuffer;

      // 단일 주문의 재생이 남아있는 경우 다음 단위루프 예약 (단일 펌프)
      if (_remainingPlays > 0) {
        logger.d(
            '[SoundService] 단일 단위 재생 다음 프레임 예약: ${delay.inMilliseconds}ms 후 (세션 남은 횟수: $_remainingPlays)');
        Future.delayed(delay, () => _loopPlay(session));
      } else {
        // 단일 주문 재생이 완전히 끝난 후에도 딜레이를 살짝 주어 다음 주문 알람과 간격을 유지 (혹은 즉시 넘김)
        logger.i('[SoundService] 단일 주문 설정횟수 재생 완료');
        Future.delayed(delay, () {
          if (session == _sessionId && _isPlaying) {
            _processNextAlarm();
          }
        });
      }
    } on PlatformException catch (e) {
      // Sentry APPFIT-ORDER-AGENT-N 대응: 재생 중 플레이어가 disposed 된 경우
      logger.w('[SoundService] 재생 중 PlatformException (disposed 가능): $e');
      _isDisposed = true;
      _isPlaying = false;
      _remainingPlays = 0;
    } catch (e, s) {
      logger.e('[SoundService] loop 재생 오류', error: e, stackTrace: s);
      _processNextAlarm(); // 에러 발생 시 현재 것 취소하고 다음 큐 진행
    }
  }

  Future<void> stop() async {
    if (_isDisposed) {
      _isPlaying = false;
      _remainingPlays = 0;
      _alarmQueue.clear();
      return;
    }
    try {
      await _player.stop();
    } on PlatformException catch (e) {
      logger.w('[SoundService] stop 중 PlatformException: $e');
      _isDisposed = true;
    } catch (_) {}
    _isPlaying = false;
    _remainingPlays = 0;
    _sessionId++;
    _alarmQueue.clear();
  }

  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    try {
      await _player.dispose();
    } catch (_) {}
    _startupTimer?.cancel();
    _isPlaying = false;
    _remainingPlays = 0;
    _sessionId = 0;
    _cachedDuration = null;
    _soundSource = null;
    _appliedVolume = null;
  }
}

final soundAppServiceProvider = Provider<SoundService>((ref) {
  final svc = SoundService(ref);
  // 초기 설정 로드
  svc.reloadSettings();
  ref.onDispose(() {
    svc.dispose();
  });
  return svc;
});
