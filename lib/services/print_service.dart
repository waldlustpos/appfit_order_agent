import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:appfit_order_agent/services/external_receipt_printer.dart';
import 'package:appfit_order_agent/services/label_printer/label_print_outcome.dart';
import 'package:appfit_order_agent/services/label_printer/label_printer_options.dart';
import 'package:appfit_order_agent/services/label_printer/label_warmup_starter.dart';
import 'package:appfit_order_agent/services/label_printer/windows/windows_label_router.dart';
import 'package:appfit_order_agent/services/platform_service.dart';
import 'package:appfit_order_agent/services/printer_job_queue.dart';
import 'package:appfit_order_agent/services/printer_transport.dart';
import 'package:appfit_order_agent/services/startup_probe_scheduler.dart';
import 'package:appfit_order_agent/utils/label_painter.dart';
import 'package:appfit_order_agent/models/order_model.dart';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:appfit_order_agent/providers/providers.dart';
import 'package:appfit_order_agent/providers/locale_provider.dart';
import 'package:appfit_order_agent/services/receipt_labels.dart';
import 'package:appfit_order_agent/utils/logger.dart';
import 'package:appfit_order_agent/services/preference_service.dart';

// Windows transport (WindowsTransport) 는 win32/serial_port_win32 의존성 때문에
// Android 런타임에서 로드되면 안 된다. external_receipt_printer.dart 가 이미
// deferred 로 import 하고 있으나 별도 alias 가 필요하므로 본 파일에서도 deferred 로 받음.
import 'package:appfit_order_agent/services/external_receipt_printer_windows.dart'
    deferred as win_transport;

class PrinterStatus {
  final bool isExternalConnected;
  final bool isLabelConnected;

  /// 연결된 라벨 프린터 기종명 (예: 'BIXOLON G30', 'REXOD RXLA-561').
  /// 미연결/미식별이면 null.
  final String? labelPrinterModel;

  PrinterStatus({
    this.isExternalConnected = false,
    this.isLabelConnected = false,
    this.labelPrinterModel,
  });

  PrinterStatus copyWith({
    bool? isExternalConnected,
    bool? isLabelConnected,
    bool updateLabelModel = false,
    String? labelPrinterModel,
  }) {
    return PrinterStatus(
      isExternalConnected: isExternalConnected ?? this.isExternalConnected,
      isLabelConnected: isLabelConnected ?? this.isLabelConnected,
      // null 로 되돌릴 수 있어야 하므로 `?? this` 패턴 대신 명시 플래그 사용.
      labelPrinterModel:
          updateLabelModel ? labelPrinterModel : this.labelPrinterModel,
    );
  }
}

/// 라벨 프린터 표시명 중 G30 — [OutputService] 가 이 값으로 연속용지 레이아웃
/// ([ContinuousLabelPainter] / [LabelMediaSpec.continuous40]) 분기를 탄다.
/// 문자열을 여기저기 새로 쓰지 말고 항상 이 상수를 참조할 것.
const String kBixolonG30ModelName = 'BIXOLON G30';

/// 라벨 프린터 VID/PID → 사용자 표시용 기종명. 지원 대상이 아니면 null.
/// LabelPrinter.java / BixolonPosDriver.java 화이트리스트와 동기 유지.
///
/// BIXOLON 은 VID 0x1504 만으로는 G30 을 확정하지 못한다 — PID 로 가른다.
/// G30 PID 는 실기기로 확인됨(0x0147) — Android `BixolonPosDriver.KNOWN_PRODUCT_IDS`
/// 와 동기 유지. [productName] "G30" 부분일치는 PID 미매칭 개체(리퍼브/다른 로트)를
/// 위한 보조 판정.
///
/// ★ 둘 다 안 맞는 0x1504 기기는 **의도적으로 null**(미식별)이다. XD5-40d 지원 종료로
/// 폴백 대상이 사라졌다 — 넓혀서 G30 으로 몰면 UPOS 로 구동하다 실패해 원인이 흐려진다.
/// 새 BIXOLON 개체를 지원하려면 그 PID 를 여기와 `KNOWN_PRODUCT_IDS` 양쪽에 추가할 것.
String? labelPrinterModelName({
  required int vendorId,
  required int productId,
  String? productName,
}) {
  if (vendorId == 0x4B43 && productId == 0x3538) return 'Caysn D2';
  if (vendorId == 0x4B43 && productId == 0x3830) return 'Caysn D3';
  if (vendorId == 0x0FE6 && productId == 0x811E) return 'REXOD RXLA-561';
  if (vendorId == 0x1504) {
    if (productId == 0x0147) return kBixolonG30ModelName;
    if (productName != null && productName.toUpperCase().contains('G30')) {
      return kBixolonG30ModelName;
    }
  }
  return null;
}

final printerStatusProvider =
    StateProvider<PrinterStatus>((ref) => PrinterStatus());

/// 내장 프린터 하드웨어 감지 결과. null = 아직 probe 중. Sunmi 단말 + 실제
/// 내장 모듈 있는 모델만 true. [PrintService] 생성자 microtask 에서 갱신.
final builtinPrinterAvailableProvider = StateProvider<bool?>((ref) => null);

class PrintService {
  final Ref ref;
  final PreferenceService _preferenceService;

  // 프린터 설정값 캐시
  bool? _cachedBuiltinPrinter;
  bool? _cachedExternalPrinter;
  bool? _cachedLabelPrinter;

  // 프린터 × 출력물 매트릭스 캐시
  bool? _cachedBuiltinPrintOrder;
  bool? _cachedBuiltinPrintReceipt;
  bool? _cachedExternalPrintOrder;
  bool? _cachedExternalPrintReceipt;
  bool? _cachedBuiltinPrintCall;
  bool? _cachedExternalPrintCall;

  /// 앱 시작 시 외부 COM 프린터 연결 확인이 실패했을 때 재확인하는 간격.
  ///
  /// 매장 PC 는 부팅 직후 다른 POS / 배달 프로그램이 COM 포트를 먼저 배타 점유
  /// (serial_port_win32 open 은 share-mode 0)하거나 USB-Serial 드라이버가 아직
  /// enumerate 되지 않아 첫 확인이 실패하는 경우가 있다. 사용자가 설정 화면에서
  /// 재연결을 누르지 않아도 점유가 풀리면 스스로 "연결됨" 으로 복구되도록 한다.
  ///
  /// 초기 1회 + 이 목록만큼 재시도 = 총 6회 / 누적 약 170초. 출력 잡 자체는
  /// [PrinterJobQueue] 의 backoff(누적 137초)가 따로 흡수하므로 같은 자릿수로 맞췄다.
  /// 주기 폴링으로 승격하지 말 것 — COM probe 는 포트를 실제로 여닫아 출력과
  /// 간섭할 수 있어 **시작 창 한정 · 유한 횟수** 여야 한다.
  static const List<Duration> defaultStartupProbeBackoffs = [
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(seconds: 30),
    Duration(seconds: 60),
    Duration(seconds: 60),
  ];

  /// 시작 재확인 스케줄러. 첫 확인이 실패한 경우에만 생성된다 (성공 시 null 유지).
  StartupProbeScheduler? _startupProbe;

  /// 라벨 warm-up 재확인 스케줄러. 초기 warm-up 이 실패한 경우에만 생성된다.
  StartupProbeScheduler? _labelWarmupProbe;

  /// dispose 됐는지. warm-up 이 백그라운드로 도는 사이 컨테이너가 정리되면
  /// 뒤늦게 도착한 스케줄러가 타이머를 남기지 않도록 즉시 stop 하기 위한 플래그.
  bool _disposed = false;

  var tag = '프린트';

  PrintService(this.ref)
      : _preferenceService = ref.read(preferenceServiceProvider) {
    // 초기 설정값 로드
    _loadPrinterSettings();
    // 외부 프린터 출력 큐의 transport 와 최종 실패 콜백을 등록.
    // 큐는 글로벌 싱글턴이므로 PrintService 가 dispose 돼도 transport 는 유지된다.
    Future.microtask(_initPrinterQueue);
    // USB 디바이스 확인.
    // Riverpod provider build 도중 ref.read(...).state= 가 동기적으로 실행되면
    // assertion 위반 (Providers 가 build 중 다른 provider 수정 금지).
    // Android 흐름은 첫 라인이 await PlatformService.getConnectedUsbDevices()
    // 라 항상 microtask 로 yield 되어 안전했지만, Windows 분기는 _cachedLabelPrinter
    // 가 false 거나 backend.isOpen=true 면 첫 await 없이 state 가 갱신될 수 있다.
    // 다음 microtask 으로 deferred 해서 provider build 종료 후 실행되게 한다.
    Future.microtask(_runStartupConnectionCheck);
    Future.microtask(_probeBuiltinPrinter);
    // keepAlive provider 라 실제로는 세션당 1회 생성되지만, 컨테이너가 정리될 때
    // 예약된 재시도 타이머가 남지 않도록 방어.
    ref.onDispose(() {
      _disposed = true;
      _startupProbe?.stop();
      _labelWarmupProbe?.stop();
    });
  }

  /// 앱 시작 시 연결 확인 1회 + (Windows 외부 프린터 한정) 실패 시 백오프 재시도.
  ///
  /// Android / 라벨 프린터 경로는 기존과 동일하게 [checkConnection] 1회로 끝난다.
  Future<void> _runStartupConnectionCheck() async {
    final comPort = _preferenceService.getComPortName();
    final isWindowsExternal =
        Platform.isWindows && _cachedExternalPrinter == true;

    if (isWindowsExternal) {
      // 이 PC 에서 어떤 COM 이 보이는지는 지금까지 파일 로그 어디에도 없었다.
      // "설정 포트가 아예 존재하지 않는 매장" 을 원격 로그 한 줄로 판정하기 위함.
      String availablePorts = '(조회 실패)';
      try {
        await win_transport.loadLibrary();
        availablePorts = win_transport.getAvailableComPorts().toString();
      } catch (e) {
        logger.w('[PrintService] COM 포트 목록 조회 실패: $e');
      }
      logToFile(
          tag: LogTag.PLATFORM,
          message: '[PrintService] Windows 외부 프린터 초기 연결 확인: '
              'COM=${comPort ?? "(미설정)"} '
              'baud=${_preferenceService.getComPortBaudRate()} '
              '가용포트=$availablePorts');
    }

    // Android 라벨: 시작 시점에 USB 포트를 미리 연다 (Windows 의 main.dart 에서
    // WindowsLabelRouter.warmupOpen 을 부르는 것과 대칭). 이것이 없으면 세션 최초
    // open 을 첫 주문의 라벨이 대신 지불해, 실패 시 `실패 [연결오류]` 후 1.5초 뒤
    // 재시도에서야 인쇄된다.
    //
    // ★ 인쇄 경로에는 아무 재시도도 추가하지 않는다 — 시작 창만 손댄다
    //   (label_print_retry.dart 의 "retryable 일 때 정확히 1회" 불변식 불변).
    //
    // await 하지 않는 이유: BIXOLON 경로의 연결은 USB 권한 승인을 최대 30초 폴링
    // 대기할 수 있고, 그동안 아래 checkConnection 이 막히면 설정 화면의 연결 배지가
    // 그만큼 늦게 뜬다. Android 의 checkConnection 은 USB enumerate 만 읽고 포트를
    // 열지 않으므로 warm-up 과 순서를 다툴 이유도 없다.
    if (Platform.isAndroid) {
      unawaited(startLabelWarmup(
        useLabelPrinter: _cachedLabelPrinter == true,
        autoReplyMode: _preferenceService.getLabelAutoReplyMode,
        warmup: (mode) =>
            PlatformService.warmupLabelPrinter(autoReplyMode: mode),
        shouldContinue: () => _cachedLabelPrinter == true,
        onInfo: (m) =>
            logToFile(tag: LogTag.PLATFORM, message: '[PrintService] $m'),
        onWarning: (m) =>
            logToFile(tag: LogTag.WARNING, message: '[PrintService] $m'),
      ).then((scheduler) {
        // warm-up 이 도는 사이 dispose 됐으면 뒤늦은 스케줄러가 타이머를 남긴다.
        if (_disposed) {
          scheduler?.stop();
          return;
        }
        _labelWarmupProbe = scheduler;
      }));
    }

    await checkConnection();

    if (!isWindowsExternal) return;
    // 첫 시도 성공은 파일에 남기지 않는다 (정상 흐름 flood 방지).
    if (_isExternalConnected) return;
    // 포트 미설정은 시간이 지나도 저절로 풀리지 않는다 (사용자가 설정에서 골라야
    // 하고, 그때 설정 화면이 checkConnection 을 다시 돌린다). 재시도 무의미.
    if (comPort == null || comPort.isEmpty) {
      logToFile(
          tag: LogTag.PLATFORM,
          message: '[PrintService] COM 포트 미설정 — 재시도 생략 '
              '(설정에서 프린터 포트를 선택하세요)');
      return;
    }

    _startupProbe = StartupProbeScheduler(
      backoffs: defaultStartupProbeBackoffs,
      // 재시도는 외부 scope 만 갱신 — 라벨 status 가 같이 토글되는 sync 이슈 회피.
      probe: () async {
        await checkConnection(external: true, label: false);
        return _isExternalConnected;
      },
      // 재시도 대기 중 사용자가 외부 프린터 토글을 껐다면 더 확인할 이유가 없다.
      shouldContinue: () => _cachedExternalPrinter == true,
      onRetryScheduled: (attempt, total, delay) => logToFile(
          tag: LogTag.PLATFORM,
          message: '[PrintService] 외부 프린터 미연결 — 재시도 예약 '
              '($attempt/$total, ${delay.inSeconds}초 후)'),
      onRecovered: (attempt, total) => logToFile(
          tag: LogTag.PLATFORM,
          message: '[PrintService] 외부 프린터 연결 확인 (재시도 $attempt/$total 에서 복구)'),
      onExhausted: (total) => logToFile(
          tag: LogTag.ERROR,
          message: '[PrintService] 외부 프린터 초기 연결 최종 실패 ($total회) — '
              '출력은 잡별 큐 재시도로 계속 시도됨'),
    )..startAfterInitialFailure();
  }

  bool get _isExternalConnected =>
      ref.read(printerStatusProvider).isExternalConnected;

  Future<void> _initPrinterQueue() async {
    final queue = PrinterJobQueue.instance;
    if (Platform.isAndroid) {
      queue.setTransport(const AndroidUsbTransport());
    } else if (Platform.isWindows) {
      try {
        await win_transport.loadLibrary();
        queue.setTransport(win_transport.WindowsTransport());
      } catch (e, s) {
        logger.e('[PrintService] WindowsTransport 로드 실패',
            error: e, stackTrace: s);
      }
    }
    queue.onFinalFailure = (job, result) {
      // 3회 backoff 재시도 후에도 success 못 받은 잡. logToFile 로 매장 진단용
      // 영구 기록 + logger.e 로 Sentry 자동 캡처.
      logToFile(
        tag: LogTag.ERROR,
        message:
            '[PrinterQueue] FINAL FAILURE id=${job.id} job=${job.jobName} kind=${job.kind} attempts=${job.attempt} result=$result',
      );
      logger.e('[PrinterQueue] 출력 최종 실패 job=${job.jobName} result=$result');
    };
  }

  /// 내장 프린터 하드웨어 감지 (앱 시작 1회).
  /// Sunmi 단말 + InnerPrinterManager.hasPrinter() true 인 경우에만 true.
  /// 감지 못하면 self-heal: 설정상 ON 으로 저장돼 있어도 OFF 로 보정해 사용자가
  /// 출력 안 되는 프린터를 ON 처럼 인식하지 않도록 한다.
  Future<void> _probeBuiltinPrinter() async {
    bool result = false;
    if (Platform.isAndroid) {
      try {
        result =
            await platform.invokeMethod<bool>('hasBuiltinPrinter') ?? false;
      } on PlatformException catch (e, s) {
        logger.w('[PrintService] hasBuiltinPrinter MethodChannel 실패',
            error: e, stackTrace: s);
      } catch (e, s) {
        logger.w('[PrintService] hasBuiltinPrinter 예외',
            error: e, stackTrace: s);
      }
    }
    ref.read(builtinPrinterAvailableProvider.notifier).state = result;
    logToFile(
        tag: LogTag.PLATFORM, message: '[PrintService] 내장 프린터 감지 결과: $result');

    // self-heal: 하드웨어 없는데 설정상 ON 이면 OFF 로 보정.
    if (!result && _cachedBuiltinPrinter == true) {
      _cachedBuiltinPrinter = false;
      try {
        await _preferenceService.setUseBuiltinPrinter(false);
      } catch (e) {
        logger.w('[PrintService] 내장 프린터 self-heal setPref 실패: $e');
      }
      logToFile(
          tag: LogTag.PLATFORM,
          message: '[PrintService] 내장 프린터 미감지 — 설정 자동 OFF (self-heal)');
    }
  }

  /// 외부에서 강제로 내장 감지를 재시도. 폴링 timeout 으로 누락된 경우용.
  Future<void> refreshBuiltinAvailability() => _probeBuiltinPrinter();

  // 프린터 설정값 로드
  void _loadPrinterSettings() {
    _cachedBuiltinPrinter = _preferenceService.getUseBuiltinPrinter();
    _cachedExternalPrinter = _preferenceService.getUseExternalPrinter();
    _cachedLabelPrinter = _preferenceService.getUseLabelPrinter();
    _cachedBuiltinPrintOrder = _preferenceService.getBuiltinPrintOrder();
    _cachedBuiltinPrintReceipt = _preferenceService.getBuiltinPrintReceipt();
    _cachedExternalPrintOrder = _preferenceService.getExternalPrintOrder();
    _cachedExternalPrintReceipt = _preferenceService.getExternalPrintReceipt();
    _cachedBuiltinPrintCall = _preferenceService.getBuiltinPrintCall();
    _cachedExternalPrintCall = _preferenceService.getExternalPrintCall();
    logToFile(
        tag: LogTag.PLATFORM,
        message:
            '프린터 설정 업데이트: 내장=$_cachedBuiltinPrinter(주문서=$_cachedBuiltinPrintOrder/영수증=$_cachedBuiltinPrintReceipt/기기호출=$_cachedBuiltinPrintCall), '
            '외부=$_cachedExternalPrinter(주문서=$_cachedExternalPrintOrder/영수증=$_cachedExternalPrintReceipt/기기호출=$_cachedExternalPrintCall), '
            '라벨=$_cachedLabelPrinter'
            '${Platform.isWindows ? ", COM=${_preferenceService.getComPortName() ?? "(미설정)"} baud=${_preferenceService.getComPortBaudRate()}" : ""}');
  }

  /// 프린터 연결 상태 관리.
  ///
  /// [external] / [label] 플래그로 특정 프린터만 갱신할 수 있음. 외부 재연결
  /// 버튼이 라벨 status 도 함께 바꿔버리는 sync 이슈 회피용. 둘 다 true (기본)
  /// 이면 기존 동작과 동일하게 한 번에 갱신.
  Future<void> checkConnection(
      {bool external = true, bool label = true}) async {
    // Windows: USB enumerate (PlatformService.getConnectedUsbDevices) 가 Android
    // MethodChannel 전용이라 Windows 에서는 빈 리스트 반환 -> 라벨 프린터를 못
    // 잡는다. autoreplyprint SDK 의 CP_Port_EnumUsb 가 라벨 프린터를 직접 enumerate
    // 하므로 backend.warmupOpen 결과를 그대로 사용. 외부 영수증 프린터(PR800 등)는
    // 설정된 COM 포트가 현재 SerialPort.getAvailablePorts() 결과에 있는지로 판정.
    if (Platform.isWindows) {
      bool? newLabel;
      bool? newExternal;
      try {
        if (label && _cachedLabelPrinter == true) {
          final backend = WindowsLabelRouter.instance;
          bool open = false;
          try {
            open = backend.isOpen;
          } catch (e, s) {
            logger.w('[PrintService] backend.isOpen 예외',
                error: e, stackTrace: s);
          }
          if (open) {
            newLabel = true;
          } else {
            final mode = _preferenceService.getLabelAutoReplyMode();
            newLabel = await backend.warmupOpen(autoReplyMode: mode);
          }
        } else if (label) {
          newLabel = false;
        }
        if (external && _cachedExternalPrinter == true) {
          // ExternalReceiptPrinter 가 내부적으로 deferred 로드된 Windows transport 를
          // 거쳐 COM 가용성 / Winspool default 를 판정. ComPortPrintService 직접 참조
          // 시 안드로이드에서 win32 native lookup 이 트리거되는 문제 회피.
          newExternal = await ExternalReceiptPrinter().isConnected();
        } else if (external) {
          newExternal = false;
        }
        logToFile(
            tag: LogTag.PLATFORM,
            message:
                '[PrintService] Windows checkConnection: label=$newLabel, external=$newExternal '
                '(scope: external=$external label=$label, cachedLabel=$_cachedLabelPrinter, cachedExternal=$_cachedExternalPrinter)');
      } catch (e, s) {
        logger.e('[PrintService] Windows checkConnection 예외',
            error: e, stackTrace: s);
        logToFile(
            tag: LogTag.ERROR,
            message: '[PrintService] Windows checkConnection 예외: $e');
      }
      final winLabelModel = (newLabel == true)
          ? WindowsLabelRouter.instance.connectedModelName
          : null;
      ref.read(printerStatusProvider.notifier).update((s) => s.copyWith(
            isExternalConnected: newExternal,
            isLabelConnected: newLabel,
            updateLabelModel: label,
            labelPrinterModel: winLabelModel,
          ));
      return;
    }
    try {
      final devices = await PlatformService.getConnectedUsbDevices();

      bool isExternalConnected = false;
      bool isLabelConnected = false;
      String? labelModel;

      if (devices.isNotEmpty) {
        for (var device in devices) {
          final vendorId = device['vendorId'];
          final productId = device['productId'];
          final manufacturer = device['manufacturerName'] ?? 'Unknown';
          final productName =
              (device['productName'] ?? 'Unknown').toLowerCase();

          String identification = '';

          // 1. 라벨 프린터 식별 — 화이트리스트는 [labelPrinterModelName] 하나뿐이다
          //    (LabelPrinter.java / BixolonPosDriver.java 와 동기화).
          //    Caysn D2 · Caysn D3 · REXOD RXLA-561(운영 모델) · BIXOLON G30.
          //
          // 조건을 여기에 복제하지 않는 이유: "연결됨" 판정과 기종 판정이 갈라지면
          // 미식별 0x1504 기기가 **연결됨으로 표시되면서 인쇄는 전부 실패**하는 상태가
          // 된다. 그러면 매장은 UI 를 믿고 프린터가 아니라 앱/서버를 의심한다.
          // "연결 안 됨" 이 즉시 올바른 곳(케이블/기종)을 가리킨다.
          //
          // 주의: 범용 USB-Serial 칩(PL2303 0x067B:0x2303 등) 은 넣지 말 것 —
          // 외부 ESC/POS 영수증 프린터를 라벨로 오인한다. (Windows 후보와 동일.)
          // 주의: Android `device_filter.xml` 은 여기와 달리 0x1504 를 VID-only 로
          // 등록한다 — 그건 attach 권한 승계 경로라 목적이 다르다. 같이 조이지 말 것.
          // 루프 밖 [labelModel] 은 누적값이다 — 뒤따르는 비-라벨 장치가 지우지
          // 않도록 지역 변수로 받아 식별된 경우에만 올린다.
          final detectedModel = labelPrinterModelName(
              vendorId: vendorId,
              productId: productId,
              productName: device['productName'] as String?);

          if (detectedModel != null) {
            isLabelConnected = true;
            labelModel = detectedModel;
            identification = ' [라벨 프린터 식별됨 $detectedModel]'
                ' VID:$vendorId / PID:$productId';
          }
          // 2. 외부 영수증 프린터 식별
          // Posbank VID: 0x1552 (5458)
          // 또는 제품명에 printer, pos, mpos 등이 포함된 경우 외부 프린터로 간주
          else if (vendorId == 0x1552 ||
              vendorId == 5458 ||
              productName.contains('printer') ||
              productName.contains('pos') ||
              productName.contains('mpos')) {
            isExternalConnected = true;
            identification = ' [외부 영수증 프린터 식별됨]';
          }

          if (identification.isNotEmpty) {
            logToFile(
              tag: LogTag.PLATFORM,
              message:
                  ' - ${device['productName'] ?? 'Unknown'} ($manufacturer): VID=$vendorId, PID=$productId$identification',
            );
          }
        }
      } else {
        logToFile(tag: LogTag.PLATFORM, message: '연결된 USB 디바이스가 없습니다.');
        logger.d('연결된 USB 디바이스가 없습니다.');
      }

      // UsbReceiptPrinter 가 실제로 device 를 open 했는지 native 측에 재확인.
      // USB enumerate 는 하드웨어가 꽂혀있다는 것만 알려주고, USB 권한이 거부됐거나
      // discover 가 한 번도 돈 적 없으면 connection 이 비어 실제 출력이 실패한다.
      // (외부 토글을 켜둔 채 앱 첫 실행했고 사용자가 USB 권한을 놓친 경우 등.)
      if (external && _cachedExternalPrinter == true && isExternalConnected) {
        try {
          final connected =
              await platform.invokeMethod<bool>('isExternalPrinterConnected');
          if (connected != true) {
            // 네이티브 측에서 open 못한 상태 → discover 재시도. 권한 broadcast 가 받아 처리.
            await platform.invokeMethod('reconnectExternalPrinter');
            logToFile(
                tag: LogTag.PLATFORM,
                message: '[PrintService] 외부 프린터 connection 비어있음 — 재탐색 트리거');
          }
        } on PlatformException catch (e, s) {
          logger.w('[PrintService] 외부 프린터 상태/재탐색 호출 실패',
              error: e, stackTrace: s);
        }
      }

      // 호출한 scope 만 갱신. 외부 재연결 버튼이 라벨 status 까지 같이 토글하지 않도록.
      ref.read(printerStatusProvider.notifier).update((s) => s.copyWith(
            isExternalConnected: external ? isExternalConnected : null,
            isLabelConnected: label ? isLabelConnected : null,
            updateLabelModel: label,
            labelPrinterModel: label ? labelModel : null,
          ));
    } catch (e, s) {
      logger.e('USB 디바이스 확인 중 오류 발생', error: e, stackTrace: s);
    }
  }

  /// Android 외부 영수증 프린터(Posbank) 재탐색.
  /// 외부 프린터 토글 ON / 재연결 버튼에서 호출. USB 권한 미부여 시 시스템 다이얼로그 표시.
  Future<void> reconnectExternalPrinter() async {
    if (!Platform.isAndroid) return;
    try {
      await platform.invokeMethod('reconnectExternalPrinter');
      logToFile(tag: LogTag.PLATFORM, message: '[PrintService] Posbank 재탐색 요청');
    } on PlatformException catch (e, s) {
      logger.e('[PrintService] Posbank 재탐색 실패', error: e, stackTrace: s);
    }
  }

  // 프린터 설정값 업데이트
  void updatePrinterSettings({
    bool? builtinPrinter,
    bool? externalPrinter,
    bool? labelPrinter,
    bool? builtinPrintOrder,
    bool? builtinPrintReceipt,
    bool? externalPrintOrder,
    bool? externalPrintReceipt,
    bool? builtinPrintCall,
    bool? externalPrintCall,
  }) {
    if (builtinPrinter != null) _cachedBuiltinPrinter = builtinPrinter;
    if (externalPrinter != null) _cachedExternalPrinter = externalPrinter;
    if (labelPrinter != null) _cachedLabelPrinter = labelPrinter;
    if (builtinPrintOrder != null) _cachedBuiltinPrintOrder = builtinPrintOrder;
    if (builtinPrintReceipt != null) {
      _cachedBuiltinPrintReceipt = builtinPrintReceipt;
    }
    if (externalPrintOrder != null) {
      _cachedExternalPrintOrder = externalPrintOrder;
    }
    if (externalPrintReceipt != null) {
      _cachedExternalPrintReceipt = externalPrintReceipt;
    }
    if (builtinPrintCall != null) _cachedBuiltinPrintCall = builtinPrintCall;
    if (externalPrintCall != null) _cachedExternalPrintCall = externalPrintCall;
    logToFile(
        tag: LogTag.PLATFORM,
        message:
            '프린터 설정 수동 업데이트: 내장=$_cachedBuiltinPrinter(주문서=$_cachedBuiltinPrintOrder/영수증=$_cachedBuiltinPrintReceipt/기기호출=$_cachedBuiltinPrintCall), '
            '외부=$_cachedExternalPrinter(주문서=$_cachedExternalPrintOrder/영수증=$_cachedExternalPrintReceipt/기기호출=$_cachedExternalPrintCall), '
            '라벨=$_cachedLabelPrinter');
  }

  // 주문 정보를 JSON으로 변환하여 네이티브 프린트 기능 호출
  Future<bool> printOrderReceipt({
    required OrderModel order,
    String type = 'order',
    bool isCancelReceipt = false,
  }) async {
    try {
      // 사용자 이름이 없는 경우 처리 (이미 API에서 userNickname을 받아오지만, 없을 경우를 대비한 로직은 유지 가능)
      /*
      if (order.userName == null &&
          order.userId.isNotEmpty &&
          order.userId != '3740002700000000') {
         // fetchUserName API call removed
      }
      */

      final store = ref.read(storeProvider);
      final orderWithStore = order.copyWith(storeName: store.value?.name);
      // OrderModel 에는 storePhone 필드를 추가하지 않고 toSunmiJson 출력 맵에 직접
      // 주입한다. ExternalReceiptPrinter / Sunmi 양쪽이 'storePhone' 키를 읽어
      // 매장명 아래에 TEL 줄로 출력. (사업자번호는 /v0/shop 응답에 미포함.)
      final orderMap = orderWithStore.toSunmiJson();
      final storePhone = store.value?.phone;
      if (storePhone != null && storePhone.isNotEmpty) {
        orderMap['storePhone'] = storePhone;
      }
      // 영수증/주문서 고정 라벨을 현재 앱 로캘 번역으로 주입. Dart ESC/POS 빌더와
      // Sunmi(Java) 가 동일한 'labels' 맵을 읽어 라벨 언어가 일치한다. (메뉴명/옵션명
      // 등 서버값은 그대로.) 누락 시 각 빌더가 한국어로 fallback.
      orderMap['labels'] =
          buildReceiptLabels(ref.read(localeNotifierProvider).translations);
      // 매장/포장 표기 토글 — 내장(Sunmi Java)/외부(Dart ESC-POS) 양쪽이 이 플래그를
      // JSON payload 에서 읽으므로 판정 로직은 여기 한 곳에만 존재.
      orderMap['showOrderType'] = _preferenceService.getPrintShowOrderType();
      // 취식구분 앞 출처 태그([APP]/[KIOSK]) 노출 여부 — '키오스크 주문 주문서 및
      // 알림소리' 설정을 그대로 재사용한다. 내장(Sunmi Java)/외부(Dart ESC-POS) 양쪽이
      // 이 플래그를 JSON payload 에서 읽는다.
      orderMap['showOrderSourceTag'] =
          _preferenceService.getKioskPrintAndSound();
      final orderJson = jsonEncode(orderMap);

      // 캐시된 설정값이 없는 경우에만 로드
      if (_cachedBuiltinPrinter == null || _cachedExternalPrinter == null) {
        _loadPrinterSettings();
      }

      // 프린터 × 출력물 매트릭스 적용.
      // - 취소 영수증(isCancelReceipt=true)은 주문서 매트릭스 사용 (사용자 결정).
      // - 영수증 재출력 시 두 프린터 동시 ON 강제 OFF 로직 제거 — 매트릭스가 source of truth.
      final isReceiptCategory = (type == 'receipt') && !isCancelReceipt;
      final bool useBuiltin = (_cachedBuiltinPrinter ?? false) &&
          (isReceiptCategory
              ? (_cachedBuiltinPrintReceipt ?? true)
              : (_cachedBuiltinPrintOrder ?? true));
      final bool useExternal = (_cachedExternalPrinter ?? false) &&
          (isReceiptCategory
              ? (_cachedExternalPrintReceipt ?? true)
              : (_cachedExternalPrintOrder ?? true));

      logger.d(
          '${type == 'order' ? '주문서출력' : '영수증출력'}: displayNum=${order.displayNum}');

      logToFile(
          tag: LogTag.PLATFORM,
          message:
              '${type == 'order' ? '주문서출력' : '영수증출력'}: displayNum=${order.displayNum}');

      // 내장(Android Sunmi) 과 외부 영수증 프린터(Windows COM/Winspool, Android 범용 USB)는
      // 동시에 켜질 수 있어 두 경로를 분리 호출. 외부는 플랫폼-무관 [ExternalReceiptPrinter] 위임.
      if (useBuiltin && Platform.isAndroid) {
        // Sunmi 는 raw bytes 미지원이라 기존 JSON 채널 유지.
        // 하단 로고는 브랜드별로 분기 — 외부 프린터와 동일하게 BrandAssets 기반
        // [ExternalReceiptPrinter.loadReceiptLogoBytes] 를 single source of truth 로
        // 사용. 로고 없는 브랜드(receiptLogoPath == null)는 null → 네이티브에서 미출력.
        final logoBytes = await ExternalReceiptPrinter.loadReceiptLogoBytes();
        try {
          await platform.invokeMethod('printOrder', {
            'orderJson': orderJson,
            'type': type,
            'isCancel': isCancelReceipt,
            'useBuiltinPrint': true,
            'logoBase64': logoBytes != null ? base64Encode(logoBytes) : null,
          });
        } on PlatformException catch (e, s) {
          logger.e('[PrintService] Sunmi 내장 출력 실패', error: e, stackTrace: s);
        }
      }
      if (useExternal) {
        try {
          final ext = ExternalReceiptPrinter();
          if (type == 'receipt') {
            await ext.printReceipt(orderMap, isCancel: isCancelReceipt);
          } else {
            await ext.printOrder(orderMap, isCancel: isCancelReceipt);
          }
        } catch (e, s) {
          logger.e('[PrintService] 외부 영수증 프린터 출력 실패', error: e, stackTrace: s);
        }
      }
      return true;
    } on PlatformException catch (e, s) {
      logger.e('Failed to print order', error: e, stackTrace: s);
      rethrow;
    }
  }

  /// 기기 호출(DEVICE_CALL_REQUESTED) 알림 슬립 출력.
  ///
  /// deviceId / 일시 / [phrase] 3줄을 영수증 프린터로 인쇄한다. 주문 영수증과
  /// 동일하게 내장(Sunmi) + 외부 프린터 양쪽을 대상으로 하되, 설정 매트릭스의
  /// 기기 호출 컬럼([_cachedBuiltinPrintCall]/[_cachedExternalPrintCall], 기본 ON)
  /// 으로 대상 프린터를 지정한다.
  Future<bool> printDeviceCall({
    required String deviceId,
    required String phrase,
    DateTime? at,
  }) async {
    // 캐시된 설정값이 없는 경우에만 로드 (printOrderReceipt 동일 패턴).
    if (_cachedBuiltinPrinter == null || _cachedExternalPrinter == null) {
      _loadPrinterSettings();
    }

    final bool useBuiltin =
        (_cachedBuiltinPrinter ?? false) && (_cachedBuiltinPrintCall ?? true);
    final bool useExternal =
        (_cachedExternalPrinter ?? false) && (_cachedExternalPrintCall ?? true);

    final now = at ?? DateTime.now();
    final dateTime =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';

    logToFile(
        tag: LogTag.PLATFORM,
        message:
            '기기호출출력: deviceId=$deviceId, 문구=$phrase (내장=$useBuiltin/외부=$useExternal)');

    // 내장(Android Sunmi) — raw bytes 미지원이라 전용 MethodChannel 사용.
    if (useBuiltin && Platform.isAndroid) {
      try {
        await platform.invokeMethod('printDeviceCall', {
          'headline': phrase,
          'deviceIdLabel': '키오스크번호',
          'deviceId': deviceId,
          'dateLabel': '일시',
          'dateValue': dateTime,
        });
      } on PlatformException catch (e, s) {
        logger.e('[PrintService] Sunmi 내장 기기호출 출력 실패', error: e, stackTrace: s);
      }
    }

    // 외부 영수증 프린터 (Windows COM/Winspool, Android 범용 USB).
    if (useExternal) {
      try {
        await ExternalReceiptPrinter().printDeviceCall(
          deviceId: deviceId,
          dateTime: dateTime,
          phrase: phrase,
        );
      } catch (e, s) {
        logger.e('[PrintService] 외부 기기호출 출력 실패', error: e, stackTrace: s);
      }
    }

    return useBuiltin || useExternal;
  }

  /// 설정 화면 "라벨 테스트 출력" 버튼용. 간단한 mock 라벨 1장 인쇄.
  ///
  /// [LabelPainter.generateLabelImage] 로 'TEST' + 현재 시각 PNG 비트맵을 만들어
  /// 기존 [printLabel] 경로로 송출. 라벨 토글 OFF / 라벨 프린터 미연결 시 false.
  Future<bool> printLabelTestPage() async {
    try {
      if (_cachedLabelPrinter == null) {
        _loadPrinterSettings();
      }
      if (_cachedLabelPrinter != true) {
        logger.w('[PrintService] 라벨 프린터 OFF — 테스트 출력 생략');
        return false;
      }
      final now = DateTime.now();
      final ts =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
      final bytes = await LabelPainter.generateLabelImage(
        menuName: 'TEST',
        options: const [],
        shopOrderNo: 'TEST',
        orderTime: ts,
        memo: '테스트 출력입니다.',
      );
      return await printLabel(bytes, orderNo: 'TEST');
    } catch (e, s) {
      logger.e('[PrintService] 라벨 테스트 출력 실패', error: e, stackTrace: s);
      return false;
    }
  }

  /// 라벨 한 장 인쇄 (bool 편의 래퍼). 종이가 나갔다고 볼 수 있으면 true.
  ///
  /// 재시도 가능 여부까지 알아야 하는 호출자는 [printLabelDetailed] 를 쓸 것 —
  /// bool 은 "안 보냄"과 "보냈는데 응답 없음"을 구분하지 못해, 후자에서 재시도하면
  /// 같은 라벨이 2장 인쇄된다.
  Future<bool> printLabel(Uint8List imageBytes,
      {String orderNo = '-', int labelIndex = 1, int totalLabels = 1}) async {
    final outcome = await printLabelDetailed(
      imageBytes,
      orderNo: orderNo,
      labelIndex: labelIndex,
      totalLabels: totalLabels,
    );
    return outcome.isPrinted;
  }

  /// 라벨 한 장 인쇄. 네이티브 `LabelPrinter.printBitmap` 의 3분류 결과를 그대로 전달.
  ///
  /// rethrow 대신 결과값으로 처리: 한 라벨 실패가 OutputService 의 catch 블록을
  /// 트리거해 같은 주문의 나머지 라벨까지 막는 것을 방지하기 위함.
  Future<LabelPrintOutcome> printLabelDetailed(Uint8List imageBytes,
      {String orderNo = '-', int labelIndex = 1, int totalLabels = 1}) async {
    try {
      if (_cachedExternalPrinter == null) {
        _loadPrinterSettings();
      }

      bool useLabel = _cachedLabelPrinter ?? false;

      if (!useLabel) {
        logger.w('Label printer is disabled in settings.');
        return LabelPrintOutcome.retryable;
      }

      // Windows: FFI 직접 호출 — MethodChannel 'printLabel' 핸들러가
      // Windows runner 측에 없어 invokeMethod 가 무반응이라, backend 를 직접 호출한다.
      // 벤더(Caysn/BIXOLON) 선택은 라우터가 USB VID 로 매 인쇄 재평가.
      // Android 의 기존 MethodChannel 경로는 아래 else 로 보존.
      if (Platform.isWindows) {
        // Windows 백엔드는 내부적으로 이미 submit-wins 를 구현하고 있어
        // (windows_label_printer_backend `_printedAckCount` 스냅샷 + 완료 폴링),
        // false 는 "제출 전 실패 = 재시도 안전" 을 뜻한다.
        final ok = await WindowsLabelRouter.instance.printPng(
          pngBytes: imageBytes,
          width: LabelPainter.width.toInt(),
          height: LabelPainter.height.toInt(),
          options: LabelPrinterOptions(
            autoReplyMode: _preferenceService.getLabelAutoReplyMode(),
            useFeedToTear: _preferenceService.getLabelUseFeedToTear(),
            useBackToPrint: _preferenceService.getLabelUseBackToPrint(),
            useCalibrate: _preferenceService.getLabelUseCalibrate(),
          ),
          orderNo: orderNo,
          labelIndex: labelIndex,
          totalLabels: totalLabels,
        );
        return ok ? LabelPrintOutcome.success : LabelPrintOutcome.retryable;
      }

      final result = await platform.invokeMethod<int>('printLabel', {
        'imageBytes': imageBytes,
        'autoReplyMode': _preferenceService.getLabelAutoReplyMode(),
        'useFeedToTear': _preferenceService.getLabelUseFeedToTear(),
        'useBackToPrint': _preferenceService.getLabelUseBackToPrint(),
        'useCalibrate': _preferenceService.getLabelUseCalibrate(),
        'orderNo': orderNo,
        'labelIndex': labelIndex,
        'totalLabels': totalLabels,
      });
      return LabelPrintOutcome.fromNativeCode(result);
    } on PlatformException catch (e, s) {
      logger.e('Failed to print label', error: e, stackTrace: s);
      return LabelPrintOutcome.retryable;
    }
  }

  /// 직전 ACK timeout 의 네이티브 진단 스냅샷을 가져온다 (읽으면 네이티브에서 비워짐).
  ///
  /// `[LabelPrintOutcome.submittedNoAck]` 을 받은 직후에만 호출할 것. Java 가 이미
  /// 만들어 두고 기기 로그 파일로만 내보내던 값(`portOk`·비콘 age·`err`·`pg`)을 Sentry
  /// 이벤트에 실어 "왜 timeout 했는가" 를 사후 판별할 수 있게 한다.
  ///
  /// 조회 실패는 전부 null — **진단 조회가 집계를 막으면 안 된다.**
  /// Android 전용 (Windows 백엔드는 자체 submit-wins 경로라 이 스냅샷이 없다).
  Future<String?> fetchLastLabelAckDiagnostic() async {
    if (!Platform.isAndroid) return null;
    try {
      return await platform.invokeMethod<String>('getLastLabelAckDiagnostic');
    } catch (e) {
      logger.w('[Label] ACK 진단 스냅샷 조회 실패: $e');
      return null;
    }
  }

  /// 설정 화면 "테스트 출력" 버튼용.
  ///
  /// 외부 영수증 프린터(Windows COM/Winspool, Android 범용 USB)는 모두 동일한
  /// [ExternalReceiptPrinter] 진입점을 거쳐 `ReceiptEscPosBuilder.buildTestPageBytes`
  /// 결과를 출력 — 양 플랫폼 결과물이 일치. Sunmi 내장은 raw bytes 미지원이라 별도 JSON 경로 유지.
  ///
  /// [targetExternalOnly] true 면 외부 sub-settings 테스트 버튼: 외부만 발사.
  /// [targetBuiltinOnly] true 면 내장 sub-settings 테스트 버튼: 내장만 발사.
  /// 둘 다 false 면 켜진 프린터 모두 (구 기본 동작).
  Future<bool> printTestPage({
    bool targetExternalOnly = false,
    bool targetBuiltinOnly = false,
  }) async {
    if (_cachedBuiltinPrinter == null || _cachedExternalPrinter == null) {
      _loadPrinterSettings();
    }
    // 동시 지정은 외부 우선 (이론상 동시 호출이 없어야 하지만 가드).
    if (targetExternalOnly && targetBuiltinOnly) {
      targetBuiltinOnly = false;
    }
    final useBuiltin = targetBuiltinOnly
        ? true
        : ((targetExternalOnly || Platform.isWindows)
            ? false
            : (_cachedBuiltinPrinter ?? false));
    // Windows 는 내장 개념이 없으므로 외부 프린터로 항상 출력 (기존 동작 보존).
    // targetBuiltinOnly 면 외부는 차단.
    final useExternal = targetBuiltinOnly
        ? false
        : (Platform.isWindows ? true : (_cachedExternalPrinter ?? false));

    if (useExternal) {
      await ExternalReceiptPrinter().printTestPage();
    }

    if (useBuiltin) {
      // Sunmi 는 raw bytes 미지원이라 더미 JSON 으로 기존 printOrder 경로 호출.
      final testJson = jsonEncode({
        'displayOrderNum': 'TEST',
        'ordrSimpleId': 'TEST',
        'storeName': '테스트 매장',
        'ordrDtm': DateTime.now().toString(),
        'userName': null,
        'kioskId': null,
        'ordrMemo': '테스트 출력입니다.',
        'ordrPrdList': [
          {
            'prdNm': '테스트 메뉴',
            'ordrCnt': 1,
            'prdPrc': 0,
            'optPrdList': <Map<String, dynamic>>[],
          },
        ],
        'exceptTaxPrice': '0',
        'taxPrice': '0',
        'ordrPrc': '0',
        'discPrc': '0',
        'payPrc': '0',
      });
      try {
        await platform.invokeMethod('printOrder', {
          'orderJson': testJson,
          'type': 'order',
          'isCancel': false,
          'useBuiltinPrint': true,
        });
      } on PlatformException catch (e, s) {
        logger.e('[PrintService] Android 내장 테스트 출력 실패',
            error: e, stackTrace: s);
      }
    }
    return useBuiltin || useExternal;
  }

  // 서비스 정리
  void dispose() {
    _cachedBuiltinPrinter = null;
    _cachedExternalPrinter = null;
  }
}
