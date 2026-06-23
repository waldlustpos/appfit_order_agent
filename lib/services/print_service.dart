import 'dart:io';

import 'package:flutter/services.dart';
import 'package:appfit_order_agent/services/external_receipt_printer.dart';
import 'package:appfit_order_agent/services/label_printer/label_printer_options.dart';
import 'package:appfit_order_agent/services/label_printer/windows/windows_label_printer_backend.dart';
import 'package:appfit_order_agent/services/platform_service.dart';
import 'package:appfit_order_agent/services/printer_job_queue.dart';
import 'package:appfit_order_agent/services/printer_transport.dart';
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

  PrinterStatus({
    this.isExternalConnected = false,
    this.isLabelConnected = false,
  });

  PrinterStatus copyWith({
    bool? isExternalConnected,
    bool? isLabelConnected,
  }) {
    return PrinterStatus(
      isExternalConnected: isExternalConnected ?? this.isExternalConnected,
      isLabelConnected: isLabelConnected ?? this.isLabelConnected,
    );
  }
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
    Future.microtask(checkConnection);
    Future.microtask(_probeBuiltinPrinter);
  }

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
    logToFile(
        tag: LogTag.PLATFORM,
        message:
            '프린터 설정 업데이트: 내장=${_cachedBuiltinPrinter}(주문서=$_cachedBuiltinPrintOrder/영수증=$_cachedBuiltinPrintReceipt), '
            '외부=${_cachedExternalPrinter}(주문서=$_cachedExternalPrintOrder/영수증=$_cachedExternalPrintReceipt), '
            '라벨=${_cachedLabelPrinter}');
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
          final backend = WindowsLabelPrinterBackend.instance;
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
      ref.read(printerStatusProvider.notifier).update((s) => s.copyWith(
            isExternalConnected: newExternal,
            isLabelConnected: newLabel,
          ));
      return;
    }
    try {
      final devices = await PlatformService.getConnectedUsbDevices();

      bool isExternalConnected = false;
      bool isLabelConnected = false;

      if (devices.isNotEmpty) {
        for (var device in devices) {
          final vendorId = device['vendorId'];
          final productId = device['productId'];
          final manufacturer = device['manufacturerName'] ?? 'Unknown';
          final productName =
              (device['productName'] ?? 'Unknown').toLowerCase();

          String identification = '';

          // 1. 라벨 프린터 식별 (LabelPrinter.java 의 고정 모델과 동기화)
          // VID:0x4B43(19267), PID:0x3538(13624)  Caysn D2
          // VID:0x4B43(19267), PID:0x3830(14384)  Caysn D3
          // VID:0x0FE6(4070),  PID:0x811E(33054)  REXOD RXLA-561 (운영 모델)
          // 주의: 범용 USB-Serial 칩(PL2303 0x067B:0x2303 등) 은 넣지 말 것 —
          // 외부 ESC/POS 영수증 프린터를 라벨로 오인한다. (Windows 후보와 동일.)
          bool isKnownLabelPrinter = (vendorId == 0x4B43 &&
                  (productId == 0x3538 || productId == 0x3830)) ||
              (vendorId == 0x0FE6 && productId == 0x811E);

          if (isKnownLabelPrinter) {
            isLabelConnected = true;
            identification = ' [라벨 프린터 식별됨] VID:$vendorId / PID:$productId';
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
  }) {
    if (builtinPrinter != null) _cachedBuiltinPrinter = builtinPrinter;
    if (externalPrinter != null) _cachedExternalPrinter = externalPrinter;
    if (labelPrinter != null) _cachedLabelPrinter = labelPrinter;
    if (builtinPrintOrder != null) _cachedBuiltinPrintOrder = builtinPrintOrder;
    if (builtinPrintReceipt != null) {
      _cachedBuiltinPrintReceipt = builtinPrintReceipt;
    }
    if (externalPrintOrder != null)
      _cachedExternalPrintOrder = externalPrintOrder;
    if (externalPrintReceipt != null) {
      _cachedExternalPrintReceipt = externalPrintReceipt;
    }
    logToFile(
        tag: LogTag.PLATFORM,
        message:
            '프린터 설정 수동 업데이트: 내장=$_cachedBuiltinPrinter(주문서=$_cachedBuiltinPrintOrder/영수증=$_cachedBuiltinPrintReceipt), '
            '외부=$_cachedExternalPrinter(주문서=$_cachedExternalPrintOrder/영수증=$_cachedExternalPrintReceipt), '
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

  /// 라벨 한 장 인쇄. 네이티브 [LabelPrinter.printBitmap] 의 boolean 결과를 그대로 반환.
  /// false 반환 시 호출자가 재시도/누락 로깅 결정.
  ///
  /// rethrow 대신 `return false` 로 처리: 한 라벨 실패가 OutputService 의 catch 블록을
  /// 트리거해 같은 주문의 나머지 라벨까지 막는 것을 방지하기 위함. 실패는 반환값으로 표현.
  Future<bool> printLabel(Uint8List imageBytes,
      {String orderNo = '-', int labelIndex = 1, int totalLabels = 1}) async {
    try {
      if (_cachedExternalPrinter == null) {
        _loadPrinterSettings();
      }

      bool useLabel = _cachedLabelPrinter ?? false;

      if (!useLabel) {
        logger.w('Label printer is disabled in settings.');
        return false;
      }

      // Windows: autoreplyprint.dll FFI 직접 호출 — MethodChannel 'printLabel' 핸들러가
      // Windows runner 측에 없어 invokeMethod 가 무반응이라, backend 를 직접 호출한다.
      // Android 의 기존 MethodChannel 경로는 아래 else 로 보존.
      if (Platform.isWindows) {
        return await WindowsLabelPrinterBackend.instance.printPng(
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
      }

      final result = await platform.invokeMethod<bool>('printLabel', {
        'imageBytes': imageBytes,
        'autoReplyMode': _preferenceService.getLabelAutoReplyMode(),
        'useFeedToTear': _preferenceService.getLabelUseFeedToTear(),
        'useBackToPrint': _preferenceService.getLabelUseBackToPrint(),
        'useCalibrate': _preferenceService.getLabelUseCalibrate(),
        'orderNo': orderNo,
        'labelIndex': labelIndex,
        'totalLabels': totalLabels,
      });
      return result ?? false;
    } on PlatformException catch (e, s) {
      logger.e('Failed to print label', error: e, stackTrace: s);
      return false;
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
