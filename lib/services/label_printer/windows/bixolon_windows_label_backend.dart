// BIXOLON XD5-40d 라벨 프린터 Windows 백엔드 (BXLLAPI_x64.dll FFI).
//
// Android BixolonLabelDriver.java 의 의미론을 1:1 로 따르고, 구조는 Caysn
// WindowsLabelPrinterBackend 를 미러한다:
// - 동시 호출 직렬화는 _inflight Future 체이닝.
// - 용지없음/커버열림 → 운영자 개입 신뢰, 무한 복구대기 (false 반환 안 함).
//   ※ 커버열림 복구는 프린터 본체 재개(resume) 버튼까지 눌러야 재개된다
//   (하드웨어 동작 — project_bixolon_xd5_40d 메모리).
// - 기타 프린터 에러 → 0.5초 짧은 게이트 후 false (Dart 1.5초 재시도 위임).
// - ★ submit-wins: Prints() 제출 후에는 상태조회 실패/연결 끊김으로 false 를
//   반환하지 않는다 (false → Dart 재시도 → 같은 라벨 중복 인쇄 사고).
//
// BXLLAPI 특성 (헤더 V3.10 전문 판독 + 샘플):
// - 완전 동기 API, 콜백 없음 — 상태는 CheckStatus() 폴링.
// - 연결 상태는 DLL 프로세스 전역 (핸들 객체 없음).
// - 이미지 인쇄는 파일 경로 전용 → 임시 BMP 파일 경유.
// - 블로킹 가능 호출은 전부 Isolate.run 으로 박싱, int/String 만 경계 통과
//   (FFI isolate boxing 규칙).

import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';

import 'package:appfit_order_agent/services/label_printer/windows/bxllapi_bindings.dart';
import 'package:appfit_order_agent/services/label_printer/windows/bxllapi_constants.dart';
import 'package:appfit_order_agent/services/label_printer/windows/label_bmp_converter.dart';
import 'package:appfit_order_agent/utils/logger.dart';

// ---------------------------------------------------------------------------
// Isolate.run 워커용 top-level 함수 — int/String 만 주고받는다.
// 워커 isolate 의 BxlLapiBindings.tryGet() 은 isolate 별 인스턴스를 만들지만
// DLL 모듈/연결 상태는 프로세스 전역이라 안전하다.
// ---------------------------------------------------------------------------

/// DLL 로드 실패 sentinel (SLCS 코드 공간과 겹치지 않게 음수).
const int _kRcDllLoadFailed = -100;

/// 연결/설정 중 예외 sentinel.
const int _kRcException = -101;

/// PrintImageLibW 실패 = 아무것도 커밋 안 됨 (재시도 안전).
const int _kRcImageFailed = -2;

/// Prints 실패/예외 = 제출 모호 (상태조회 2차 판별 대상).
const int _kRcPrintsAmbiguous = -3;

/// 연결 + 1회 미디어 설정. 반환: [connectRc, dpi, cfgFailBits].
List<int> _isolateConnectAndConfigure() {
  final b = BxlLapiBindings.tryGet();
  if (b == null) return const [_kRcDllLoadFailed, 0, 0];
  try {
    // DLL 이 에러 시 블로킹 MessageBox 를 띄우지 않도록 최우선 호출 —
    // 워커 스레드에서 다이얼로그가 뜨면 파이프라인이 보이지 않게 wedge 된다.
    b.setShowMsgBox(0);
    final empty = ''.toNativeUtf8();
    int rc;
    try {
      rc = b.connectPrinterEx(BxlInterface.usb, empty, 115200, 8, 0, 1);
    } finally {
      calloc.free(empty);
    }
    if (rc != BxlStatus.ok) return [rc, 0, 0];

    final dpi = b.getPrinterDpi();
    // 미디어 설정 (연결당 1회). 실패는 비치명 — 프린터 보존값 사용.
    int cfgFailBits = 0;
    if (b.clearBuffer() == 0) cfgFailBits |= 1;
    if (b.setCharacterset(BxlCharset.icsUsa, BxlCharset.cp1252) == 0) {
      cfgFailBits |= 2;
    }
    if (b.setConfigOfPrinter(BxlSpeed.keepPrinterSetting, kBxlDensity,
            BxlOrientation.top2bottom, 0, 1, 1) ==
        0) {
      cfgFailBits |= 4;
    }
    if (b.setPaper(0, 0, kBxlLabelWidthDots, kBxlLabelLengthDots,
            BxlMediaType.gap, 0, kBxlLabelGapDots) ==
        0) {
      cfgFailBits |= 8;
    }
    // XD5-40d 는 감열(direct thermal).
    final std = 'STd'.toNativeUtf8();
    try {
      if (b.printDirect(std, 1) == 0) cfgFailBits |= 16;
    } finally {
      calloc.free(std);
    }
    return [BxlStatus.ok, dpi, cfgFailBits];
  } catch (_) {
    return const [_kRcException, 0, 0];
  }
}

/// CheckStatus 1회. 실패/예외는 UNKNOWN(99).
int _isolateCheckStatus() {
  final b = BxlLapiBindings.tryGet();
  if (b == null) return BxlStatus.unknown;
  try {
    return b.checkStatus();
  } catch (_) {
    return BxlStatus.unknown;
  }
}

/// 라벨 1장 제출: ClearBuffer → PrintImageLibW → Prints.
int _isolateSubmit(String bmpPath) {
  final b = BxlLapiBindings.tryGet();
  if (b == null) return _kRcDllLoadFailed;
  try {
    b.clearBuffer();
  } catch (_) {
    return _kRcImageFailed; // 아직 아무것도 커밋 안 됨
  }
  int okImg;
  final p = bmpPath.toNativeUtf16();
  try {
    okImg = b.printImageLibW(0, 0, p, BxlDither.none, 0);
  } catch (_) {
    return _kRcImageFailed;
  } finally {
    calloc.free(p);
  }
  if (okImg == 0) return _kRcImageFailed;
  try {
    final okPrints = b.prints(1, 1);
    return okPrints != 0 ? BxlStatus.ok : _kRcPrintsAmbiguous;
  } catch (_) {
    return _kRcPrintsAmbiguous;
  }
}

void _isolateDisconnect() {
  final b = BxlLapiBindings.tryGet();
  if (b == null) return;
  try {
    b.disconnectPrinter();
  } catch (_) {
    // best-effort
  }
}

/// BIXOLON XD5-40d Windows 백엔드. Caysn 백엔드와 동일한 공개 시그니처.
class BixolonWindowsLabelBackend {
  BixolonWindowsLabelBackend._();

  static final BixolonWindowsLabelBackend instance =
      BixolonWindowsLabelBackend._();

  // ---------------------------------------------------------------------------
  // 상수 — Android BixolonLabelDriver 미러
  // ---------------------------------------------------------------------------

  static const int _kStatusPollIntervalMs = 200;
  static const int _kErrorQuickGateMs = 500;
  static const int _kPrintResultTimeoutMs = 30000;
  static const int _kRecoveryHeartbeatMs = 60000;

  /// 복구대기 중 연속 상태조회 실패(장치 소멸) 한도 — 200ms × 15 = 3초.
  static const int _kRecoveryDeadLimit = 15;

  /// 완료폴링 중 연속 연결사망 한도 — 200ms × 5 = 1초 후 submit-wins.
  static const int _kCompletionDeadLimit = 5;

  // ---------------------------------------------------------------------------
  // 상태 (main isolate 전용)
  // ---------------------------------------------------------------------------

  bool _connected = false;
  String? _currentTag;
  int _printSeq = 0;
  Future<bool>? _inflight;

  bool get isAvailable => Platform.isWindows;

  /// 연결 플래그. FFI 호출 없는 순수 bool — stale 일 수 있으며, stale 은
  /// 다음 인쇄의 연결사망 감지 → 재연결/false 로 해소된다.
  bool get isOpen => _connected;

  String? get currentTag => _currentTag;

  /// DLL 버전 (디버깅용). 로드 실패 시 null.
  String? get libraryVersion {
    final b = BxlLapiBindings.tryGet();
    if (b == null) return null;
    final buf = calloc<ffi.Uint8>(256).cast<Utf8>();
    try {
      final ok = b.getDllVersion(buf);
      if (ok == 0) return null;
      return buf.toDartString();
    } catch (_) {
      return null;
    } finally {
      calloc.free(buf);
    }
  }

  // ---------------------------------------------------------------------------
  // 공개 API
  // ---------------------------------------------------------------------------

  /// 라벨 1장 인쇄. 성공 여부 반환, 절대 throw 하지 않는다.
  Future<bool> printPng({
    required Uint8List pngBytes,
    required int width,
    required int height,
    required String orderNo,
    required int labelIndex,
    required int totalLabels,
  }) async {
    if (!isAvailable) return false;
    if (pngBytes.isEmpty) {
      logger.e('[Label][BXL] empty PNG buffer');
      return false;
    }

    final prev = _inflight;
    final completer = Completer<bool>();
    _inflight = completer.future;
    try {
      if (prev != null) {
        await prev.catchError((_) => false);
      }
      _currentTag = '[$orderNo $labelIndex/$totalLabels]';
      final result = await _doPrintPng(
        pngBytes: pngBytes,
        orderNo: orderNo,
        labelIndex: labelIndex,
        totalLabels: totalLabels,
      );
      completer.complete(result);
      return result;
    } catch (e, s) {
      logger.e('[Label][BXL] printPng exception', error: e, stackTrace: s);
      completer.complete(false);
      return false;
    } finally {
      _currentTag = null;
      if (identical(_inflight, completer.future)) {
        _inflight = null;
      }
    }
  }

  /// 시작 시 미리 연결 (첫 인쇄 지연 제거 + 설정 UI 연결 표시).
  Future<bool> warmupOpen() async {
    if (!isAvailable) return false;
    final prev = _inflight;
    final completer = Completer<bool>();
    _inflight = completer.future;
    try {
      if (prev != null) {
        await prev.catchError((_) => false);
      }
      final result = await _ensureConnected('[Label][BXL][warmup]');
      completer.complete(result);
      return result;
    } catch (e, s) {
      logger.w('[Label][BXL] warmupOpen exception', error: e, stackTrace: s);
      completer.complete(false);
      return false;
    } finally {
      if (identical(_inflight, completer.future)) {
        _inflight = null;
      }
    }
  }

  /// 앱 종료(detached) 시 연결 해제. best-effort.
  void dispose() {
    if (!_connected) return;
    _connected = false;
    unawaited(Isolate.run(_isolateDisconnect).catchError((_) {}));
    logger.i('[Label][BXL] dispose — disconnect 요청');
  }

  // ---------------------------------------------------------------------------
  // 인쇄 본체
  // ---------------------------------------------------------------------------

  Future<bool> _doPrintPng({
    required Uint8List pngBytes,
    required String orderNo,
    required int labelIndex,
    required int totalLabels,
  }) async {
    final seq = ++_printSeq;
    final tag = '[Label][BXL][$orderNo'
        '${totalLabels > 1 ? ' $labelIndex/$totalLabels' : ''}]';
    final tStart = DateTime.now();
    logger.i('$tag #$seq 출력시작');

    if (BxlLapiBindings.tryGet() == null) {
      logger.w('$tag BXLLAPI_x64.dll 로드 실패 — DLL 누락 또는 호환성 문제. '
          'err=${BxlLapiBindings.lastInitError}');
      return false;
    }

    // 1) 연결 보장 (+ 연결당 1회 미디어 설정 — isolate 내에서 함께 수행)
    if (!await _ensureConnected(tag)) {
      _logElapsed(tag, seq, '실패 [연결오류]', tStart);
      return false;
    }

    // 2) 진입 상태 게이트
    if (!await _waitEntryGate(tag, seq)) {
      _logElapsed(tag, seq, '실패 [진입게이트]', tStart);
      return false;
    }

    // 3) PNG → 이진화 BMP 임시 파일
    String bmpPath;
    try {
      bmpPath = await _writeBmpTempFile(pngBytes, seq);
    } catch (e, s) {
      logger.e('$tag BMP 변환/기록 실패', error: e, stackTrace: s);
      _logElapsed(tag, seq, '실패 [BMP 변환]', tStart);
      return false;
    }

    try {
      // 4) 제출: ClearBuffer → PrintImageLibW → Prints
      final rc = await Isolate.run(() => _isolateSubmit(bmpPath));
      if (rc == _kRcImageFailed || rc == _kRcDllLoadFailed) {
        // 커밋 전 실패 — 재시도 안전.
        _logElapsed(tag, seq, '실패 [이미지 전송오류 rc=$rc — 재시도 위임]', tStart);
        return false;
      }
      if (rc == _kRcPrintsAmbiguous) {
        // Prints 실패/예외 — write 실패와 "제출 후 응답 없음" 을 구분 못 한다.
        // 상태조회 2차 판별 (Android endTransactionPrint==-1 처리 이식):
        // 프린터가 응답하면 인쇄 스트림도 도달했다고 보고 submit-wins 진행.
        final probe = await Isolate.run(_isolateCheckStatus);
        if (BxlStatus.connDead.contains(probe) || probe == BxlStatus.unknown) {
          await _disconnect();
          _logElapsed(tag, seq, '실패 [전송오류 — 연결사망, 재시도 위임]', tStart);
          return false;
        }
        logger.w('$tag #$seq Prints 응답모호 st=$probe — submit-wins 진행');
      }

      // 5) 완료 폴링 (여기서부터 submit-wins 구간)
      final printed = await _waitPrintComplete(tag, seq);
      _logElapsed(tag, seq, printed ? '출력끝' : '실패 [완료폴링 timeout]', tStart);
      return printed;
    } finally {
      // 임시 파일 정리 (best-effort)
      try {
        await File(bmpPath).delete();
      } catch (_) {
        // 삭제 실패는 무시 — 유니크 파일명이라 다음 인쇄와 충돌 없음.
      }
    }
  }

  void _logElapsed(String tag, int seq, String outcome, DateTime tStart) {
    final ms = DateTime.now().difference(tStart).inMilliseconds;
    logger.i('$tag #$seq $outcome (${ms}ms)');
  }

  // ---------------------------------------------------------------------------
  // 연결
  // ---------------------------------------------------------------------------

  Future<bool> _ensureConnected(String tag) async {
    if (_connected) return true;
    final r = await Isolate.run(_isolateConnectAndConfigure);
    final rc = r[0];
    if (rc != BxlStatus.ok) {
      logger.w('$tag 연결 실패 rc=$rc'
          '${rc == _kRcDllLoadFailed ? ' (DLL 로드 실패)' : ''}');
      return false;
    }
    _connected = true;
    final dpi = r[1];
    final cfgFailBits = r[2];
    logger.i('$tag 연결됨 dpi=$dpi'
        '${cfgFailBits != 0 ? ' 미디어설정 경고 bits=0x${cfgFailBits.toRadixString(16)}' : ''}');
    return true;
  }

  Future<void> _disconnect() async {
    _connected = false;
    try {
      await Isolate.run(_isolateDisconnect);
    } catch (_) {
      // best-effort
    }
  }

  // ---------------------------------------------------------------------------
  // 상태 게이트
  // ---------------------------------------------------------------------------

  /// 인쇄 전 진입 게이트. Android 진입 게이트 + Caysn 1-B-① 미러.
  Future<bool> _waitEntryGate(String tag, int seq) async {
    bool reconnectTried = false;
    bool transientGateUsed = false;
    while (true) {
      final st = await Isolate.run(_isolateCheckStatus);
      if (st == BxlStatus.ok) return true;

      if (BxlStatus.recoverable.contains(st)) {
        // 용지없음/커버열림 → 무한 복구대기. 커버열림은 닫은 뒤 본체
        // 재개버튼까지 눌러야 한다 (운영 안내).
        if (!await _waitOperatorRecovery(tag, seq, st)) {
          return false; // 장치 소멸
        }
        continue;
      }

      if (BxlStatus.takenWait.contains(st)) {
        // 직전 라벨 미회수/인쇄 진행 — 실패가 아니라 대기 (Android 떼기대기).
        if (!await _waitTakenClear(tag, seq, st)) {
          return false; // 장치 소멸
        }
        continue;
      }

      if (BxlStatus.connDead.contains(st)) {
        if (reconnectTried) {
          logger.w('$tag #$seq 진입게이트 연결사망 st=$st — 재연결 실패');
          return false;
        }
        reconnectTried = true;
        logger.w('$tag #$seq 진입게이트 연결사망 st=$st — 재연결 시도');
        await _disconnect();
        if (!await _ensureConnected(tag)) return false;
        continue;
      }

      // 커터잼/과열/센싱/리본/UNKNOWN 등 — 0.5초 게이트 후 1회 재확인.
      if (transientGateUsed) {
        logger.w('$tag #$seq 실패 [프린터 에러 st=$st — 재시도 위임]');
        return false;
      }
      transientGateUsed = true;
      await Future<void>.delayed(
          const Duration(milliseconds: _kErrorQuickGateMs));
    }
  }

  /// 용지없음/커버열림 무한 복구대기. 회복 true / 장치 소멸 false.
  Future<bool> _waitOperatorRecovery(String tag, int seq, int entrySt) async {
    final phase = entrySt == BxlStatus.noPaper ? '용지없음' : '커버열림(닫은 후 재개버튼)';
    logger.w('$tag #$seq 복구대기 진입 [$phase] st=$entrySt');
    final waitStart = DateTime.now();
    var lastNotice = waitStart;
    int consecutiveDead = 0;
    while (true) {
      await Future<void>.delayed(
          const Duration(milliseconds: _kStatusPollIntervalMs));
      final st = await Isolate.run(_isolateCheckStatus);
      if (BxlStatus.connDead.contains(st) || st == BxlStatus.unknown) {
        if (++consecutiveDead >= _kRecoveryDeadLimit) {
          logger.w('$tag #$seq 복구대기 중 장치 소멸 st=$st');
          return false;
        }
        continue;
      }
      consecutiveDead = 0;
      if (!BxlStatus.recoverable.contains(st)) {
        final waited = DateTime.now().difference(waitStart).inMilliseconds;
        logger.i('$tag #$seq 복구감지 [$phase → st=$st] wait=${waited}ms — 인쇄재개');
        return true;
      }
      final now = DateTime.now();
      if (now.difference(lastNotice).inMilliseconds >= _kRecoveryHeartbeatMs) {
        logger.i('$tag #$seq 복구대기중 elapsed='
            '${now.difference(waitStart).inSeconds}s');
        lastNotice = now;
      }
    }
  }

  /// 인쇄중/라벨 미회수 대기. 해제 true / 장치 소멸 false.
  Future<bool> _waitTakenClear(String tag, int seq, int entrySt) async {
    logger.i('$tag #$seq 떼기대기 (st=$entrySt)');
    final waitStart = DateTime.now();
    var lastNotice = waitStart;
    int consecutiveDead = 0;
    while (true) {
      await Future<void>.delayed(
          const Duration(milliseconds: _kStatusPollIntervalMs));
      final st = await Isolate.run(_isolateCheckStatus);
      if (BxlStatus.connDead.contains(st) || st == BxlStatus.unknown) {
        if (++consecutiveDead >= _kRecoveryDeadLimit) {
          logger.w('$tag #$seq 떼기대기 중 장치 소멸 st=$st');
          return false;
        }
        continue;
      }
      consecutiveDead = 0;
      if (!BxlStatus.takenWait.contains(st)) return true;
      final now = DateTime.now();
      if (now.difference(lastNotice).inMilliseconds >= _kRecoveryHeartbeatMs) {
        logger.i('$tag #$seq 떼기대기중 elapsed='
            '${now.difference(waitStart).inSeconds}s (st=$st)');
        lastNotice = now;
      }
    }
  }

  /// 완료 폴링 — Android waitPrintCompleteLocked 미러 (submit-wins 구간).
  Future<bool> _waitPrintComplete(String tag, int seq) async {
    var deadline = DateTime.now()
        .add(const Duration(milliseconds: _kPrintResultTimeoutMs));
    int consecutiveDead = 0;
    bool takenLogged = false;
    var lastTakenNotice = DateTime.now();
    while (DateTime.now().isBefore(deadline)) {
      final st = await Isolate.run(_isolateCheckStatus);

      if (st == BxlStatus.ok) return true;

      if (BxlStatus.recoverable.contains(st)) {
        // 인쇄 도중 용지소진/커버열림 race — 복구까지 대기 후 성공 처리.
        // false 를 주면 Dart 재시도가 중복 인쇄. 복구 후 펌웨어 재인쇄를
        // 전제 (실기기 검증점 — 아니면 이 분기만 false 로 조정).
        logger.w('$tag #$seq 인쇄중 복구대기 진입 st=$st');
        final recovered = await _waitOperatorRecovery(tag, seq, st);
        if (!recovered) {
          logger.w('$tag #$seq 인쇄중 장치 소멸 — submit-wins');
          return true;
        }
        deadline = DateTime.now()
            .add(const Duration(milliseconds: _kPrintResultTimeoutMs));
        continue;
      }

      if (BxlStatus.takenWait.contains(st)) {
        final now = DateTime.now();
        if (!takenLogged) {
          logger.i('$tag #$seq 떼기대기 (st=$st)');
          takenLogged = true;
          lastTakenNotice = now;
        } else if (now.difference(lastTakenNotice).inMilliseconds >=
            _kRecoveryHeartbeatMs) {
          logger.i('$tag #$seq 떼기대기중 (st=$st)');
          lastTakenNotice = now;
        }
        // 회수 대기는 timeout 에 걸리지 않게 타이머 리셋.
        deadline = DateTime.now()
            .add(const Duration(milliseconds: _kPrintResultTimeoutMs));
        await Future<void>.delayed(
            const Duration(milliseconds: _kStatusPollIntervalMs));
        continue;
      }

      if (BxlStatus.connDead.contains(st) || st == BxlStatus.unknown) {
        if (++consecutiveDead >= _kCompletionDeadLimit) {
          // 제출은 끝났다 — 인쇄 직후 USB 이벤트/전원 상태로 실패 처리하지
          // 않는다 (submit-wins). 연결 플래그만 내려 다음 인쇄가 재연결.
          logger.w('$tag #$seq 완료폴링 연결사망 st=$st — submit-wins');
          _connected = false;
          return true;
        }
        await Future<void>.delayed(
            const Duration(milliseconds: _kStatusPollIntervalMs));
        continue;
      }

      // 기타(커터잼/과열 등) — 30초 내 해제 안 되면 wedge 로 false.
      consecutiveDead = 0;
      await Future<void>.delayed(
          const Duration(milliseconds: _kStatusPollIntervalMs));
    }
    logger.w('$tag #$seq 완료폴링 timeout — status 미해제');
    return false;
  }

  // ---------------------------------------------------------------------------
  // PNG → 이진화 BMP 임시 파일
  // ---------------------------------------------------------------------------

  Future<String> _writeBmpTempFile(Uint8List pngBytes, int seq) async {
    final codec = await ui.instantiateImageCodec(pngBytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) {
        throw StateError('rawRgba decode failed');
      }
      final rgba =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      final bin = binarizeRgba(rgba, threshold: kBxlBinarizeThreshold);
      final bmp = encodeBmp24(bin, image.width, image.height);
      final path = '${Directory.systemTemp.path}'
          '${Platform.pathSeparator}appfit_label_${pid}_'
          '${DateTime.now().millisecondsSinceEpoch}_$seq.bmp';
      await File(path).writeAsBytes(bmp, flush: true);
      return path;
    } finally {
      image.dispose();
      codec.dispose();
    }
  }
}
