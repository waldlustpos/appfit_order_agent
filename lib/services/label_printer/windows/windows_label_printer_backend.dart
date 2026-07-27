// 라벨 프린터 고수준 API.
//
// appfit 의 Android Java LabelPrinter.java 를 1:1 로 Dart FFI 로 포팅한 것.
// Java 의 synchronized 는 Future 체이닝(_inflight) 으로 대체했고, volatile
// 필드는 단일 isolate 라 일반 필드로 충분하다. 상태 콜백은
// NativeCallable.listener 로 받아 Java 와 동일한 8개 비콘 캐시 필드를 갱신한다.

import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:appfit_order_agent/utils/logger.dart';

import 'package:appfit_order_agent/services/label_printer/label_printer_options.dart';
import 'package:appfit_order_agent/services/label_printer/windows/autoreplyprint_bindings.dart';
import 'package:appfit_order_agent/services/label_printer/windows/autoreplyprint_constants.dart';

class WindowsLabelPrinterBackend {
  WindowsLabelPrinterBackend._();

  static final WindowsLabelPrinterBackend instance =
      WindowsLabelPrinterBackend._();

  // ---------------------------------------------------------------------------
  // SDK 호출 시 사용하는 상수
  // ---------------------------------------------------------------------------

  // QueryPrintResult timeout. autoReplyMode=1 + PrintedEvent 콜백 등록 상태에서는
  // SDK 가 ACK 를 콜백으로만 보내고 QueryPrintResult 내부 상태는 갱신 안 하는
  // race 가 관찰됨 (5장 부하 테스트, ackArrived=true 인데 rc=0 timeout).
  // 정상 ACK 는 1초 내 도착하므로 1초면 충분. timeout 도달해도 ackArrived 가
  // true 면 인쇄 완료로 간주하므로 회귀 위험 없음.
  // (이전: 3000ms -> 50장 부하에서 timeout 누적이 주된 텀 원인)
  static const int _kQueryPrintResultTimeoutMs = 1000;
  // PagePrint 후 추가 sleep 은 두지 않는다. appfit Java 패턴과 동일.
  // QueryPrintResult 의 동기 블로킹 + 다음 호출의 idle gate (_waitIdleGate) 가
  // 자연스러운 직렬화 역할을 하므로 100% 추가 텀이 되는 sleep 은 불필요.
  // (이전: 100ms sleep -> 50장 인쇄 시 누적 5초 텀 발생)
  static const int _kErrorQuickGateMs = 500;
  static const int _kIdleGateMaxMs = 5000;
  // idle gate polling 간격. 비콘 도착 후 빠르게 감지.
  static const int _kIdleStepMs = 30;
  // PAPERNOFETCH wait / ERROR 게이트 polling 간격. Android 의
  // Thread.sleep(100) 와 동등. 200ms 였을 때 떼기 감지가 0~100ms 정도 늦어
  // 라벨당 미세 텀 누적 (5장 부하에서 사용자 체감 차이 관찰).
  static const int _kPaperWaitStepMs = 100;
  static const int _kPaperWaitProgressLogMs = 60000;

  // ---------------------------------------------------------------------------
  // 포트 / 콜백 핸들
  // ---------------------------------------------------------------------------

  ffi.Pointer<ffi.Void> _hPrinter = ffi.nullptr;
  int _currentAutoReplyMode = -1;
  bool _statusCallbackRegistered = false;
  bool _printedCallbackRegistered = false;
  ffi.NativeCallable<CpOnPrinterStatusEventNative>? _callable;
  ffi.NativeCallable<CpOnPrinterPrintedEventNative>? _printedCallable;
  int _printedAckCount = 0;

  /// CP_Label_EnableLabelMode 가 현재 핸들에 대해 적용됐는지. 라벨 모드는
  /// 한 번 진입하면 포트가 닫히기 전까지 유지되므로 매 라벨마다 재진입할
  /// 필요가 없다. 매번 호출하면 펌웨어로 모드 전환 명령 바이트가 송출되어
  /// 라벨 사이 텀이 늘어난다 (50장 부하 테스트에서 누적 텀 관찰됨).
  /// 포트 재오픈 시 _tryOpenUsb 에서 false 로 reset.
  bool _labelModeEnabled = false;

  // ---------------------------------------------------------------------------
  // 비콘 상태 캐시 (Java LabelPrinter 의 volatile 필드와 동일)
  // ---------------------------------------------------------------------------

  int _lastErrorStatusBits = 0;
  bool _lastErrorOccurred = false;
  bool _lastErrorIsNoPaper = false;
  bool _lastErrorIsCoverUp = false;
  bool _lastInfoRecvIdle = false;
  bool _lastInfoPrintIdle = false;
  bool _lastInfoNoPaperCanceled = false;
  bool _lastInfoPaperNoFetch = false;

  /// 마지막으로 ERROR phase 를 로깅한 타임스탬프 (dedup 용).
  int _lastLoggedErrorBits = 0;

  /// 진행 중인 라벨의 식별 태그 (예: "[0795 1/3]").
  /// 비콘 콜백(_onPrinterStatusEvent) 의 ERROR 로그에 prefix 로 붙어 어떤
  /// 라벨에서 비콘이 떴는지 운영 로그로 추적 가능하게 한다 (appfit 의
  /// currentOrderTag 패턴).
  String? _currentTag;

  // ---------------------------------------------------------------------------
  // 동시 호출 직렬화 (Java synchronized 대체)
  // ---------------------------------------------------------------------------

  Future<bool>? _inflight;

  bool get isAvailable => Platform.isWindows;

  bool get isOpen =>
      _hPrinter != ffi.nullptr &&
      AutoReplyPrintBindings.instance.portIsOpened(_hPrinter) != 0;

  // ---------------------------------------------------------------------------
  // 디버그 빌드 부하 테스트 다이얼로그용 read-only getter.
  // production UI 에서는 노출하지 않고, kDebugMode 가드된 부하 테스트 패널에서
  // 메트릭 polling 용으로만 사용한다.
  // ---------------------------------------------------------------------------

  int get printedAckCount => _printedAckCount;
  bool get hasInflight => _inflight != null;
  String? get currentTag => _currentTag;

  /// 마지막으로 오픈에 성공한 USB 포트 이름 — 설정 UI 의 기종 표시용
  /// (WindowsLabelRouter.connectedModelName). isOpen 일 때만 의미 있음.
  String? get openedPortName => _openedPortName;
  String? _openedPortName;

  /// 라이브러리 버전 문자열 (디버깅용). DLL 로드가 실패하면 null.
  String? get libraryVersion {
    final bindings = AutoReplyPrintBindings.tryGet();
    if (bindings == null) return null;
    try {
      final ptr = bindings.libraryVersion();
      if (ptr.address == 0) return null;
      return ptr.toDartString();
    } catch (_) {
      return null;
    }
  }

  /// 라벨 1장을 인쇄. 성공 여부를 반환.
  ///
  /// - [pngBytes] 는 PNG 인코딩된 byte array. SDK 가 디코드/이진화 처리.
  /// - [width]/[height] 는 라벨 페이지 사이즈 (= 이미지를 그릴 영역).
  /// - 호출 간 직렬화는 내부에서 처리하므로 호출자는 await 만 하면 된다.
  Future<bool> printPng({
    required Uint8List pngBytes,
    required int width,
    required int height,
    required LabelPrinterOptions options,
    required String orderNo,
    required int labelIndex,
    required int totalLabels,
  }) async {
    if (!isAvailable) return false;
    if (pngBytes.isEmpty) {
      logger.e('[LabelPrinter] empty PNG buffer');
      return false;
    }

    // 동시 호출 직렬화 — 직전 작업이 끝난 뒤 진입.
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
        width: width,
        height: height,
        options: options,
        orderNo: orderNo,
        labelIndex: labelIndex,
        totalLabels: totalLabels,
      );
      completer.complete(result);
      return result;
    } catch (e, s) {
      logger.e('[LabelPrinter] printPng exception', error: e, stackTrace: s);
      completer.complete(false);
      return false;
    } finally {
      _currentTag = null;
      if (identical(_inflight, completer.future)) {
        _inflight = null;
      }
    }
  }

  Future<bool> _doPrintPng({
    required Uint8List pngBytes,
    required int width,
    required int height,
    required LabelPrinterOptions options,
    required String orderNo,
    required int labelIndex,
    required int totalLabels,
  }) async {
    final tag = '[Label][$orderNo $labelIndex/$totalLabels]';
    final tStart = DateTime.now();
    final bindings = AutoReplyPrintBindings.tryGet();
    if (bindings == null) {
      logger.w(
          '$tag autoreplyprint.dll 로드 실패 — DLL 누락 또는 호환성 문제. err=${AutoReplyPrintBindings.lastInitError}');
      return false;
    }

    if (!await _ensurePortOpen(options.autoReplyMode)) {
      logger.w('$tag 포트 오픈 실패');
      return false;
    }

    // 2) ACK 콜백 등록 — autoReplyMode=1 invariant.
    //    PrintedEvent 콜백이 등록되지 않으면 SDK 가 PagePrint ACK 처리를 안 해서
    //    QueryPrintResult 가 timeout → 호출자가 retry → 동일 라벨 N장 인쇄 사고.
    //    (appfit Java 의 핵심 invariant — label-printer-inspector.md 참고)
    if (!_printedCallbackRegistered) _registerPrintedCallback();
    if (!_statusCallbackRegistered) _registerStatusCallback();

    // 2-A) ERROR 게이트 (Java LabelPrinter.java:145-203 패턴):
    //   - paper-out / cover-up / NoPaperCanceled → 무한 대기 (운영자 개입 신뢰)
    //   - 그 외 ERROR (engine/voltage/cutter 등) → 0.5초 짧은 게이트 후 false 반환
    if (!await _waitErrorGate(tag)) {
      return false;
    }

    // 2-B) idle 게이트 (RECVIDLE && PRINTIDLE && !NoPaperCanceled, 최대 5초).
    //    피크타임 race 완화. 비콘 미수신 환경에서는 fallback 으로 즉시 통과.
    await _waitIdleGate();

    // 3) 라벨 캘리브레이션은 매 라벨마다 호출하지 않는다.
    //    autoreplyprint SDK 헤더 원문: "calibrate label paper (change to
    //    different label paper, need calibration)" — 즉 종이 교체 시 1회만
    //    호출이 SDK 의도. 매 라벨마다 호출하면 펌웨어가 매번 갭 센서 정렬
    //    동작을 수행해 라벨 사이 텀이 크게 늘어남 (50장 부하 테스트 검증).
    //    LabelPrinterOptions.useCalibrate 필드는 호환성 위해 남기되 본 함수
    //    에서는 사용하지 않는다. 종이 교체 후 캘리브가 필요하면 외부에서
    //    WindowsLabelPrinterBackend.calibrateLabel() 을 명시 호출.

    // 4) 라벨 모드는 한 번 진입하면 포트 close 전까지 유지된다. 매번 호출하면
    //    펌웨어 모드 전환 명령이 매번 송출되어 텀 발생. 첫 진입 시 1회만 호출.
    if (!_labelModeEnabled) {
      bindings.labelEnableLabelMode(_hPrinter);
      _labelModeEnabled = true;
    }
    bindings.posResetPrinter(_hPrinter);

    // 5) PageBegin → DrawImageFromData → PagePrint.
    final beginRc = bindings.labelPageBegin(
      _hPrinter,
      0,
      0,
      width,
      height,
      CpLabelRotation.rot0,
    );
    if (beginRc == 0) {
      logger.w('$tag CP_Label_PageBegin 실패');
      return false;
    }

    // PagePrint 직전의 ACK 카운트 snapshot. 이 호출에 대한 PrintedEvent 가
    // 도착했는지 race-free 로 판정하기 위함.
    final ackBefore = _printedAckCount;

    final pngPtr = malloc.allocate<ffi.Uint8>(pngBytes.length);
    try {
      pngPtr.asTypedList(pngBytes.length).setAll(0, pngBytes);
      final drawRc = bindings.labelDrawImageFromData(
        _hPrinter,
        0,
        0,
        width,
        height,
        pngPtr,
        pngBytes.length,
        CpImageBinarization.thresholding,
        CpImageCompression.none,
      );
      if (drawRc == 0) {
        logger.w('$tag CP_Label_DrawImageFromData 실패');
        return false;
      }

      final printRc = bindings.labelPagePrint(_hPrinter, 1);
      if (printRc == 0) {
        logger.w('$tag CP_Label_PagePrint 실패');
        return false;
      }
    } finally {
      malloc.free(pngPtr);
    }

    // 6) 인쇄 완료 신호 폴링.
    //
    // autoReplyMode=1 + PrintedEvent 콜백 등록 상태에서 SDK 가 QueryPrintResult
    // 의 내부 신호를 race 로 갱신하지 않는 케이스가 5장 부하 테스트로 검증됨.
    // (ackArrived=true 인데 QueryPrintResult 가 풀 timeout 까지 대기)
    //
    // ACK 콜백 또는 비콘 (PAPERNOFETCH/NoPaperCanceled) 이 인쇄 완료/실패의
    // 충분 신호이므로, main isolate 에서 가벼운 폴링으로 즉시 응답을 잡는다.
    // 폴링 timeout 까지 신호가 하나도 안 오면 fallback 으로 SDK
    // QueryPrintResult 를 1회 호출 (메모리 invariant: "두 번째 QueryPrintResult
    // 호출 금지" — fallback 은 1차 폴링과 1회만이므로 invariant 보존).
    // 폴링 timeout: 5장 부하 테스트에서 ACK 도착이 PagePrint 후 최대 1.7초까지
    // 지연되는 케이스 관찰됨 (SEQ 1, ACK pageId=0). paperFetch 비콘이 잡히는
    // 정상 케이스는 0~700ms 에 즉시 break 하므로 timeout 을 길게 잡아도 영향
    // 없음. 1700ms 면 ACK 늦은 케이스도 폴링 안에서 잡고 fallback 회피.
    const fastPollTimeoutMs = 1700;
    const fastPollIntervalMs = 30;
    final tPoll = DateTime.now();
    while (true) {
      if (_printedAckCount > ackBefore) break;
      if (_lastInfoPaperNoFetch) break;
      if (_lastInfoNoPaperCanceled) break;
      if (DateTime.now().difference(tPoll).inMilliseconds >=
          fastPollTimeoutMs) {
        break;
      }
      await Future.delayed(const Duration(milliseconds: fastPollIntervalMs));
    }
    bool ackArrived = _printedAckCount > ackBefore;

    // 용지없음 race - 즉시 실패 (Dart 재시도 위임).
    if (_lastInfoNoPaperCanceled) {
      logger.w('$tag 용지없음 race (NoPaperCanceled) — Dart 재시도 위임');
      return false;
    }

    // 폴링 timeout 인데 신호가 하나도 없으면 fallback QueryPrintResult.
    // SDK 가 콜백/비콘 모두 발화하지 않은 케이스 - 보수적으로 SDK 에 직접 질의.
    if (!ackArrived && !_lastInfoPaperNoFetch) {
      final handleAddr = _hPrinter.address;
      final queryRc = await Isolate.run<int>(() {
        final innerBindings = AutoReplyPrintBindings.instance;
        final innerHandle = ffi.Pointer<ffi.Void>.fromAddress(handleAddr);
        return innerBindings.posQueryPrintResult(
            innerHandle, _kQueryPrintResultTimeoutMs);
      });
      ackArrived = _printedAckCount > ackBefore;
      if (queryRc == 0 && !ackArrived && !_lastInfoPaperNoFetch) {
        logger.w('$tag step9 fallback timeout — 인쇄 신호 없음');
        return false;
      }
    }

    // PAPERNOFETCH 비트가 떠있으면 사용자가 라벨을 떼기까지 무한 대기.
    if (_lastInfoPaperNoFetch) {
      await _waitPaperFetched(tag);
    }

    if (options.useFeedToTear) {
      bindings.labelFeedLabel(_hPrinter);
    }

    // PagePrint 후 추가 sleep 없음. 다음 호출의 _waitIdleGate 가 비콘 idle
    // 복귀를 기다리므로 자연 직렬화. (appfit Java 패턴과 동일)

    final stillOpen = bindings.portIsOpened(_hPrinter) != 0;
    final totalElapsed = DateTime.now().difference(tStart).inMilliseconds;
    logger.i(
        '$tag 완료: stillOpen=$stillOpen ackCount=$_printedAckCount total=${totalElapsed}ms');
    return stillOpen;
  }

  // ---------------------------------------------------------------------------
  // 시작 시점 warm-up.
  //
  // 첫 인쇄 호출에서 USB enum + OpenUsb 를 수행하던 lazy 흐름을 startup 시점
  // 으로 앞당긴다. 첫 라벨 인쇄 지연 제거 + 설정 화면이 실행 직후부터 정확한
  // "연결됨/미연결" 상태를 표시하도록 함. 콜백도 함께 등록해 startup 부터
  // 비콘을 캡처한다 (USB 분리/커버 열림 등).
  //
  // _inflight 큐에 참여해 자동 접수 첫 인쇄와 race 가 나지 않도록 한다.
  // 실패해도 호출자에게 false 를 반환할 뿐 throw 하지 않는다 (앱 시작을
  // 차단하지 않기 위함).
  // ---------------------------------------------------------------------------
  Future<bool> warmupOpen({required int autoReplyMode}) async {
    if (!isAvailable) return false;
    final prev = _inflight;
    final completer = Completer<bool>();
    _inflight = completer.future;
    try {
      if (prev != null) {
        await prev.catchError((_) => false);
      }
      final ok = await _ensurePortOpen(autoReplyMode);
      if (ok) {
        if (!_printedCallbackRegistered) _registerPrintedCallback();
        if (!_statusCallbackRegistered) _registerStatusCallback();
      }
      completer.complete(ok);
      return ok;
    } catch (e, s) {
      logger.e('[LabelPrinter] warmupOpen 예외', error: e, stackTrace: s);
      completer.complete(false);
      return false;
    } finally {
      if (identical(_inflight, completer.future)) {
        _inflight = null;
      }
    }
  }

  // ---------------------------------------------------------------------------
  // 라벨 캘리브레이션 (설정 화면 버튼).
  // ---------------------------------------------------------------------------
  Future<bool> calibrateLabel(int autoReplyMode) async {
    final bindings = AutoReplyPrintBindings.tryGet();
    if (bindings == null) {
      logger.w(
          '[LabelPrinter] calibrate 실패 — DLL 미로드. err=${AutoReplyPrintBindings.lastInitError}');
      return false;
    }
    try {
      if (!await _ensurePortOpen(autoReplyMode)) return false;
      final rc = bindings.labelCalibrateLabel(_hPrinter);
      return rc != 0;
    } catch (e, s) {
      logger.e('[LabelPrinter] calibrate 예외', error: e, stackTrace: s);
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // 포트 / 상태 콜백 관리
  // ---------------------------------------------------------------------------

  /// 라벨 프린터 전용 VID:PID 화이트리스트.
  /// SDK 의 `CP_Port_OpenUsb(name, ...)` 가 NULL name 을 안전하게 처리하지 않을
  /// 가능성이 있어 명시적으로 후보를 순회 시도한다.
  ///
  /// 주의: 범용 USB-Serial 브리지 칩(예: Prolific PL2303 = VID:0x067B,PID:0x2303)
  /// 은 절대 추가하지 말 것. 외부 ESC/POS 영수증 프린터가 그런 칩으로 연결되면
  /// 라벨 백엔드가 그 포트를 라벨로 오인 점유 → 라벨 연결 오탐 + 라벨 테스트가
  /// 외부 프린터로 송출되는 사고가 발생한다. 라벨 프린터는 고정 모델만 등재한다.
  static const List<String> _kUsbPortCandidates = [
    'VID:0x4B43,PID:0x3538', // Caysn D2 (검증 디바이스)
    'VID:0x4B43,PID:0x3830', // Caysn D3 (검증 디바이스)
    'VID:0x0FE6,PID:0x811E', // REXOD RXLA-561 (운영 모델)
  ];

  Future<bool> _ensurePortOpen(int autoReplyMode) async {
    final bindings = AutoReplyPrintBindings.tryGet();
    if (bindings == null) return false;
    final modeChanged = autoReplyMode != _currentAutoReplyMode;
    // USB 케이블 분리/재삽입 후 핸들이 stale 상태일 때 portIsOpened 가 여전히
    // 1 을 반환할 수 있으므로 portIsConnectionValid 도 함께 체크해서 자동
    // reconnect 를 트리거한다 (appfit Java needReconnect 패턴).
    final portInvalid = _hPrinter == ffi.nullptr ||
        bindings.portIsOpened(_hPrinter) == 0 ||
        bindings.portIsConnectionValid(_hPrinter) == 0;

    if (!modeChanged && !portInvalid) {
      return true;
    }

    if (_hPrinter != ffi.nullptr) {
      bindings.portClose(_hPrinter);
      _hPrinter = ffi.nullptr;
    }

    // 1) CP_Port_EnumUsb 로 실제 연결된 USB 디바이스 이름을 받는다.
    //    SDK 가 첫 호출 시 lazy enumerate 라 결과가 비어 나오는 경우가 있어
    //    한 번에 한해 200ms 대기 후 재시도.
    //
    //    USB 미연결 환경에서 SDK 의 동기 FFI 호출이 main thread 를 수백ms~수초
    //    block 해 "앱 응답없음" 사고가 보고됨. enumerate + portOpenUsb 모두
    //    Isolate.run 으로 boxing 해서 main thread 가 안 막히도록 한다. handle
    //    의 raw address 는 cross-isolate 로 안전하게 전달 가능 (이미 본 파일의
    //    posQueryPrintResult 호출에서 검증된 패턴).
    var enumeratedNames = await _enumerateUsbPortsAsync();
    if (enumeratedNames.isEmpty) {
      await Future.delayed(const Duration(milliseconds: 200));
      enumeratedNames = await _enumerateUsbPortsAsync();
    }

    // 진단: SDK 가 surface 하는 디바이스 목록을 로그에 남긴다. 외부 ESC/POS
    // 직렬장비가 라벨 enumerate 결과에 섞여 나오는지(= 라벨 오인 점유 위험) 를
    // 현장 로그로 검증하기 위함.
    logger.i(
        '[LabelPrinter] CP_Port_EnumUsb 결과(${enumeratedNames.length}): $enumeratedNames');

    // OS 디바이스 인스턴스 경로(`\\?\usb#...`)가 SDK 의 OpenUsb 가 실제로 받아
    // 들이는 형식이다. 짧은 `VID:0xXXXX,PID:0xYYYY` 형식은 enumerate 결과로
    // 노출되지만 OpenUsb 에서는 거부되는 환경이 있어 OS 경로를 먼저 시도한다.
    final ordered = [...enumeratedNames]..sort((a, b) {
        final aOs = a.startsWith(r'\\?\');
        final bOs = b.startsWith(r'\\?\');
        if (aOs == bOs) return 0;
        return aOs ? -1 : 1;
      });

    for (final name in ordered) {
      if (await _tryOpenUsbAsync(name, autoReplyMode)) return true;
    }

    // 2) Fallback: appfit Android 와 동일한 VID:PID 4종 화이트리스트.
    for (final port in _kUsbPortCandidates) {
      if (ordered.contains(port)) continue; // 이미 시도함
      if (await _tryOpenUsbAsync(port, autoReplyMode)) return true;
    }

    logger.w('[LabelPrinter] USB 라벨 프린터 오픈 실패 — '
        'enum=${ordered.length}, fallback=${_kUsbPortCandidates.length}');
    return false;
  }

  /// CP_Port_EnumUsb 로 USB 디바이스 이름 목록을 받는다.
  /// 결과는 buffer 안에 null-terminated 문자열들이 연속으로 채워지고
  /// 마지막은 빈 문자열로 끝난다 (double-null terminated list).
  ///
  /// SDK FFI 호출이 USB 미연결 환경에서 main thread 를 block 하므로 Isolate.run
  /// 으로 boxing. 결과(String 리스트) 만 cross-isolate 로 반환.
  Future<List<String>> _enumerateUsbPortsAsync() async {
    return Isolate.run<List<String>>(() {
      final bindings = AutoReplyPrintBindings.tryGet();
      if (bindings == null) return const [];
      const int bufSize = 0x1000;
      final buffer = malloc.allocate<ffi.Uint8>(bufSize);
      try {
        final rc = bindings.portEnumUsb(buffer, bufSize, ffi.nullptr);
        if (rc == 0) return const [];
        final bytes = buffer.asTypedList(bufSize);
        final names = <String>[];
        int offset = 0;
        while (offset < bufSize) {
          int end = offset;
          while (end < bufSize && bytes[end] != 0) {
            end++;
          }
          if (end == offset) break; // 빈 문자열 = 종료 마커
          if (end >= bufSize) break;
          final name = String.fromCharCodes(bytes.sublist(offset, end));
          if (name.isNotEmpty) names.add(name);
          offset = end + 1;
        }
        return names;
      } catch (_) {
        // isolate 안에서 throw 시 main 으로 전파되면 안 됨. 빈 결과로 fallback.
        return const [];
      } finally {
        malloc.free(buffer);
      }
    });
  }

  /// CP_Port_OpenUsb 호출. SDK FFI 의 동기 block 을 피하기 위해 Isolate.run 으로
  /// boxing 하고 handle 의 raw address 만 cross-isolate 로 반환받는다. 성공 시
  /// main isolate 의 backend instance state(`_hPrinter` / 콜백 플래그 / status
  /// beacon)를 그대로 갱신 — instance state 는 main 에 유지되므로 출력 시점의
  /// printPng 가 동일 인스턴스를 그대로 사용할 수 있다.
  Future<bool> _tryOpenUsbAsync(String name, int autoReplyMode) async {
    final addr = await Isolate.run<int>(() {
      final innerBindings = AutoReplyPrintBindings.tryGet();
      if (innerBindings == null) return 0;
      final namePtr = name.toNativeUtf8();
      try {
        final handle = innerBindings.portOpenUsb(namePtr, autoReplyMode);
        if (handle.address != 0 && innerBindings.portIsOpened(handle) != 0) {
          return handle.address;
        }
        if (handle.address != 0) {
          innerBindings.portClose(handle);
        }
        return 0;
      } catch (_) {
        // isolate 안 예외는 0 으로 fallback. 실패 사유 진단 로그는 호출자가 담당.
        return 0;
      } finally {
        malloc.free(namePtr);
      }
    });

    if (addr == 0) return false;

    _hPrinter = ffi.Pointer<ffi.Void>.fromAddress(addr);
    _currentAutoReplyMode = autoReplyMode;
    _openedPortName = name;
    // 콜백은 SDK 글로벌이라 포트 오픈/재오픈과 무관하게 한 번만 등록되면
    // 충분하지만, 안전하게 재등록하도록 플래그를 리셋한다.
    _statusCallbackRegistered = false;
    _printedCallbackRegistered = false;
    // 라벨 모드는 핸들과 결합되므로 핸들이 새로 열리면 다시 진입해야 한다.
    _labelModeEnabled = false;
    _resetStatusBeacon();
    logger.i('[LabelPrinter] 포트 오픈 성공: $name');
    return true;
  }

  void _registerStatusCallback() {
    final bindings = AutoReplyPrintBindings.tryGet();
    if (bindings == null) return;
    try {
      _callable ??= ffi.NativeCallable<CpOnPrinterStatusEventNative>.listener(
        _onPrinterStatusEvent,
      );
      final rc = bindings.printerAddOnStatus(
        _callable!.nativeFunction,
        ffi.nullptr,
      );
      _statusCallbackRegistered = rc != 0;
    } catch (e, s) {
      logger.e('[LabelPrinter] status callback 등록 실패', error: e, stackTrace: s);
      _statusCallbackRegistered = false;
    }
  }

  void _registerPrintedCallback() {
    final bindings = AutoReplyPrintBindings.tryGet();
    if (bindings == null) return;
    try {
      _printedCallable ??=
          ffi.NativeCallable<CpOnPrinterPrintedEventNative>.listener(
        _onPrinterPrintedEvent,
      );
      final rc = bindings.printerAddOnPrinted(
        _printedCallable!.nativeFunction,
        ffi.nullptr,
      );
      _printedCallbackRegistered = rc != 0;
    } catch (e, s) {
      logger.e('[LabelPrinter] printed callback 등록 실패',
          error: e, stackTrace: s);
      _printedCallbackRegistered = false;
    }
  }

  void _onPrinterPrintedEvent(
    ffi.Pointer<ffi.Void> handle,
    int printedPageId,
    ffi.Pointer<ffi.Void> ctx,
  ) {
    _printedAckCount++;
  }

  void _resetStatusBeacon() {
    _lastErrorStatusBits = 0;
    _lastErrorOccurred = false;
    _lastErrorIsNoPaper = false;
    _lastErrorIsCoverUp = false;
    _lastInfoRecvIdle = false;
    _lastInfoPrintIdle = false;
    _lastInfoNoPaperCanceled = false;
    _lastInfoPaperNoFetch = false;
    _lastLoggedErrorBits = 0;
  }

  void _onPrinterStatusEvent(
    ffi.Pointer<ffi.Void> handle,
    int errorStatus,
    int infoStatus,
    ffi.Pointer<ffi.Void> ctx,
  ) {
    _lastErrorStatusBits = errorStatus;
    _lastErrorOccurred = errorStatus != 0;
    _lastErrorIsNoPaper = (errorStatus & CpPrinterErrorBits.noPaper) != 0;
    _lastErrorIsCoverUp = (errorStatus & CpPrinterErrorBits.coverUp) != 0;
    _lastInfoRecvIdle = (infoStatus & CpPrinterInfoBits.recvIdle) != 0;
    _lastInfoPrintIdle = (infoStatus & CpPrinterInfoBits.printIdle) != 0;
    _lastInfoNoPaperCanceled =
        (infoStatus & CpPrinterInfoBits.noPaperCanceled) != 0;
    _lastInfoPaperNoFetch = (infoStatus & CpPrinterInfoBits.paperNoFetch) != 0;

    // ERROR phase 변경 시 1회만 로깅 (Java _loggedErrorPhase 패턴).
    // _currentTag 가 set 되어 있으면 어느 라벨에서 비콘이 떴는지 추적 가능.
    final loggedBits = errorStatus & 0xFFFF;
    if (loggedBits != _lastLoggedErrorBits) {
      _lastLoggedErrorBits = loggedBits;
      final prefix = _currentTag ?? '[idle]';
      if (loggedBits != 0) {
        logger.w(
            '[LabelPrinter]$prefix error beacon=0x${loggedBits.toRadixString(16)} info=0x${infoStatus.toRadixString(16)}');
      }
    }
  }

  Future<bool> _waitErrorGate(String tag) async {
    // Java 패턴:
    //   - NoPaper / CoverUp / NoPaperCanceled → 무한 대기
    //   - 그 외 ERROR → 짧은 게이트 후 false 반환 (orchestrator 재시도)
    if (!_lastErrorOccurred) return true;

    if (_lastErrorIsNoPaper ||
        _lastErrorIsCoverUp ||
        _lastInfoNoPaperCanceled) {
      logger.w('$tag 종이없음/커버열림 — 무한 대기 진입 '
          '(cover=$_lastErrorIsCoverUp noPaper=$_lastErrorIsNoPaper '
          'noPaperCanceled=$_lastInfoNoPaperCanceled)');
      int elapsed = 0;
      // entry phase snapshot — 사용자 동작 (cover 열고 닫음 등) 감지용
      final entryCover = _lastErrorIsCoverUp;
      final entryNoPaper = _lastErrorIsNoPaper;
      bool sawUserAction = false;
      bool clearTried = false;
      int clearTime = -1;
      while (_lastErrorIsNoPaper ||
          _lastErrorIsCoverUp ||
          _lastInfoNoPaperCanceled) {
        // 사용자 동작 감지: cover/noPaper 비트가 진입 시점과 달라지면 set.
        // (사용자가 cover 열거나 닫음 / 용지 교체 등)
        if (_lastErrorIsCoverUp != entryCover ||
            _lastErrorIsNoPaper != entryNoPaper) {
          sawUserAction = true;
        }
        // 사용자 동작 후 cover/noPaper 모두 해제됐는데 noPaperCanceled 만
        // stuck 인 케이스: Windows Caysn 펌웨어가 자동 해제 안 함 (SDK sample
        // 의 ERROR Status 0xCE stuck 동작과 동일). ClearError + ClearBuffer
        // + ResetPrinter 3종으로 active clear.
        if (!clearTried &&
            sawUserAction &&
            !_lastErrorIsCoverUp &&
            !_lastErrorIsNoPaper &&
            elapsed >= 200) {
          final bindings = AutoReplyPrintBindings.tryGet();
          if (bindings != null && _hPrinter != ffi.nullptr) {
            logger.w('$tag stuck 감지 (cover/noPaper 해제됨, '
                'noPaperCanceled=$_lastInfoNoPaperCanceled) '
                '-> ClearError + ClearBuffer + ResetPrinter active clear');
            try {
              bindings.printerClearError(_hPrinter);
            } catch (e, s) {
              logger.w('$tag printerClearError 예외', error: e, stackTrace: s);
            }
            try {
              bindings.printerClearBuffer(_hPrinter);
            } catch (e, s) {
              logger.w('$tag printerClearBuffer 예외', error: e, stackTrace: s);
            }
            try {
              bindings.posResetPrinter(_hPrinter);
            } catch (e, s) {
              logger.w('$tag posResetPrinter 예외', error: e, stackTrace: s);
            }
            clearTried = true;
            clearTime = elapsed;
          }
        }
        // active clear 후 1500ms 안에 펌웨어 비트 자연 갱신 안 되면 강제 break.
        // 펌웨어가 비트를 host 측 호출로도 안 풀어주는 limitation 안전망.
        // 사용자가 실제로 cover 닫고 시각적으로 정상 상태이므로 다음 PagePrint
        // 시도가 합리적.
        if (clearTried && elapsed - clearTime >= 1500) {
          logger.w('$tag active clear 후에도 비트 stuck '
              '(cover=$_lastErrorIsCoverUp noPaper=$_lastErrorIsNoPaper '
              'noPaperCanceled=$_lastInfoNoPaperCanceled) -> 강제 break, '
              '다음 PagePrint 시도');
          break;
        }
        await Future.delayed(const Duration(milliseconds: _kPaperWaitStepMs));
        elapsed += _kPaperWaitStepMs;
        if (elapsed % _kPaperWaitProgressLogMs == 0) {
          logger.w('$tag 종이없음/커버열림 대기 ${elapsed ~/ 1000}s 경과 '
              '(cover=$_lastErrorIsCoverUp noPaper=$_lastErrorIsNoPaper '
              'noPaperCanceled=$_lastInfoNoPaperCanceled '
              'sawAction=$sawUserAction)');
        }
      }
      logger.i('$tag 종이/커버 복구 — 진행 (cover=$_lastErrorIsCoverUp '
          'noPaper=$_lastErrorIsNoPaper '
          'noPaperCanceled=$_lastInfoNoPaperCanceled)');
      return true;
    }

    // 기타 ERROR — 짧은 게이트 후 false (재시도 루프에서 다시 진입).
    logger.w(
        '$tag 일반 ERROR (bits=0x${_lastErrorStatusBits.toRadixString(16)}) — short gate $_kErrorQuickGateMs ms');
    await Future.delayed(const Duration(milliseconds: _kErrorQuickGateMs));
    return false;
  }

  Future<void> _waitIdleGate() async {
    int elapsed = 0;
    while (elapsed < _kIdleGateMaxMs) {
      if (_lastInfoRecvIdle &&
          _lastInfoPrintIdle &&
          !_lastInfoNoPaperCanceled) {
        return;
      }
      await Future.delayed(const Duration(milliseconds: _kIdleStepMs));
      elapsed += _kIdleStepMs;
    }
  }

  Future<void> _waitPaperFetched(String tag) async {
    final bindings = AutoReplyPrintBindings.tryGet();
    logger.w('$tag PAPERNOFETCH wait 진입: paper=$_lastInfoPaperNoFetch '
        'cover=$_lastErrorIsCoverUp noPaper=$_lastErrorIsNoPaper '
        'noPaperCanceled=$_lastInfoNoPaperCanceled '
        'errorBits=0x${_lastErrorStatusBits.toRadixString(16)}');
    int elapsed = 0;
    bool prevError = _lastErrorOccurred;
    bool prevCover = _lastErrorIsCoverUp;
    bool prevNoPaper = _lastErrorIsNoPaper;
    while (_lastInfoPaperNoFetch) {
      // USB 핸들 stale 검사. 커버 열고 닫는 사이 또는 USB 일시 disconnect 시
      // status 비콘 stream 이 끊겨 PAPERNOFETCH 갱신 안 받는 케이스 안전망.
      // invalid 면 wait 종료 -> 다음 호출의 _ensurePortOpen 이 reconnect 처리.
      // (Android 는 같은 케이스에서 펌웨어가 PAPERNOFETCH 자동 해제. Windows
      // 도 정상 시에는 동등 동작하지만 stream 끊긴 케이스 방어.)
      if (bindings != null &&
          _hPrinter != ffi.nullptr &&
          bindings.portIsConnectionValid(_hPrinter) == 0) {
        logger.w(
            '$tag PAPERNOFETCH wait 중 USB 포트 stale 감지 (elapsed=${elapsed}ms) '
            '-> wait 종료, 다음 호출에서 reconnect');
        return;
      }

      // ERROR 비트 변화 진단 로그 (커버 열림/닫힘 등 사용자 동작 추적).
      if (_lastErrorOccurred != prevError ||
          _lastErrorIsCoverUp != prevCover ||
          _lastErrorIsNoPaper != prevNoPaper) {
        logger.i('$tag PAPERNOFETCH wait 중 ERROR 비트 변화: '
            'cover=$_lastErrorIsCoverUp noPaper=$_lastErrorIsNoPaper '
            'errorBits=0x${_lastErrorStatusBits.toRadixString(16)} '
            '(elapsed=${elapsed}ms)');
        prevError = _lastErrorOccurred;
        prevCover = _lastErrorIsCoverUp;
        prevNoPaper = _lastErrorIsNoPaper;
      }

      await Future.delayed(const Duration(milliseconds: _kPaperWaitStepMs));
      elapsed += _kPaperWaitStepMs;
      if (elapsed % 1000 == 0 && elapsed > 0) {
        logger.i('$tag PAPERNOFETCH 대기 ${elapsed ~/ 1000}s '
            '(paper=$_lastInfoPaperNoFetch cover=$_lastErrorIsCoverUp '
            'noPaper=$_lastErrorIsNoPaper '
            'noPaperCanceled=$_lastInfoNoPaperCanceled)');
      }
    }
    logger.i('$tag 라벨 fetch 완료 wait=${elapsed}ms');
  }

  /// 앱 종료 시 호출. 콜백/포트를 모두 정리한다.
  void dispose() {
    final bindings = AutoReplyPrintBindings.tryGet();
    if (bindings == null) {
      _callable?.close();
      _callable = null;
      _printedCallable?.close();
      _printedCallable = null;
      _statusCallbackRegistered = false;
      _printedCallbackRegistered = false;
      return;
    }
    try {
      if (_callable != null) {
        bindings.printerRemoveOnStatus(_callable!.nativeFunction);
        _callable!.close();
        _callable = null;
      }
      if (_printedCallable != null) {
        bindings.printerRemoveOnPrinted(_printedCallable!.nativeFunction);
        _printedCallable!.close();
        _printedCallable = null;
      }
      if (_hPrinter != ffi.nullptr) {
        bindings.labelDisableLabelMode(_hPrinter);
        bindings.portClose(_hPrinter);
        _hPrinter = ffi.nullptr;
      }
    } catch (e, s) {
      logger.e('[LabelPrinter] dispose 예외', error: e, stackTrace: s);
    }
    _statusCallbackRegistered = false;
    _printedCallbackRegistered = false;
    _currentAutoReplyMode = -1;
    _labelModeEnabled = false;
    _resetStatusBeacon();
  }
}
