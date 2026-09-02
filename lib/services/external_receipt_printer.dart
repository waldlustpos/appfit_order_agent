import 'dart:io';

import 'package:flutter/services.dart';

import 'package:appfit_order_agent/utils/brand_assets.dart';
import 'package:appfit_order_agent/utils/logger.dart';
import 'package:appfit_order_agent/services/platform_service.dart';
import 'package:appfit_order_agent/services/preference_service.dart';
import 'package:appfit_order_agent/services/printer_job_queue.dart';
import 'package:appfit_order_agent/services/receipt_escpos_builder.dart';
import 'package:appfit_order_agent/services/usb_print_descriptor.dart'
    show parseUsbIdsFromDevicePath, usbIdKey;

// Windows 전용 transport (win32 + serial_port_win32 의존).
// Android 런타임에서는 절대 로드되지 않도록 deferred 로 import — 안 그러면
// win32 패키지의 static initializer 가 'kernel32.dll' lookup 을 시도해 실패한다.
// (실 출력은 [PrinterJobQueue] 가 [WindowsTransport] 로 직렬화하므로 본 import
// 는 isConnected / getAvailableComPorts 등 진단 API 용도로 남는다. PrintService
// 가 앱 시작 시 동일한 deferred 모듈을 로드해 transport 를 큐에 주입한다.)
import 'package:appfit_order_agent/services/external_receipt_printer_windows.dart'
    deferred as win_transport;

/// 외부 영수증 프린터 출력의 플랫폼-무관 진입점.
///
/// 빌더([ReceiptEscPosBuilder.buildXxxBytes])가 만든 CP949 byte stream 을 양
/// 플랫폼에서 동일하게 사용한다. Windows 는 COM 우선 → Winspool 폴백, Android 는
/// MethodChannel `printReceiptBytes` → 네이티브 [UsbReceiptPrinter] 가 bulkTransfer
/// 로 송출. Java 측 EUC-KR 인코딩 로직을 걷어내 양 플랫폼 hex dump 가 1대1로 일치.
class ExternalReceiptPrinter {
  static Uint8List? _cachedLogoBytes;
  static String? _cachedLogoPath;
  static bool _cachedLogoIsNull = false;
  static bool _winTransportLoaded = false;

  /// 이 기기의 외부 프린터 컬럼 폭. 미설정이면 기본값(48).
  ///
  /// 기종마다 실효 컬럼이 달라(PR800 48 / POSBANK A8 42) 하드코딩할 수 없다.
  /// 자세한 배경은 [PreferenceService.getExternalPrinterColumns] 참조.
  static int columnsOf(PreferenceService pref) =>
      pref.getExternalPrinterColumns() ?? ReceiptEscPosBuilder.defaultColumns;

  Future<bool> printOrder(
    Map<String, dynamic> orderMap, {
    bool isCancel = false,
  }) async {
    final data = await ReceiptEscPosBuilder.buildOrderBytes(
      jsonOrder: orderMap,
      isCancel: isCancel,
      width: columnsOf(PreferenceService()),
      logoImageBytes: await loadReceiptLogoBytes(),
    );
    final displayNum = _displayNum(orderMap);
    return _sendBytes(data, '주문서_$displayNum');
  }

  Future<bool> printReceipt(
    Map<String, dynamic> orderMap, {
    bool isCancel = false,
  }) async {
    final data = await ReceiptEscPosBuilder.buildReceiptBytes(
      jsonOrder: orderMap,
      isCancel: isCancel,
      width: columnsOf(PreferenceService()),
      logoImageBytes: await loadReceiptLogoBytes(),
    );
    final displayNum = _displayNum(orderMap);
    return _sendBytes(data, '영수증_$displayNum');
  }

  /// 설정 화면 "테스트 출력" 버튼용. Windows / Android 동일 레이아웃.
  ///
  /// 출력물의 포트/보레이트 줄은 **어느 경로로 나온 종이인지**를 손에 쥔 채로
  /// 확인하기 위한 것이다. usbprint 경로는 보레이트 개념이 없으므로 null 을 넘겨
  /// '-' 로 찍고, 장치 경로는 42컬럼에 안 들어가므로 VID:PID 로 줄인다.
  Future<bool> printTestPage() async {
    final pref = PreferenceService();
    final isUsbPrint = Platform.isWindows &&
        pref.getExternalPrinterConnection() ==
            PreferenceService.extPrinterConnUsbPrint;
    final data = await ReceiptEscPosBuilder.buildTestPageBytes(
      comPort: isUsbPrint
          ? _usbPrintPortLabel(pref.getUsbPrintDevicePath())
          : (pref.getComPortName() ?? (Platform.isAndroid ? 'USB' : '-')),
      baudRate: isUsbPrint ? null : pref.getComPortBaudRate(),
      width: columnsOf(pref),
    );
    return _sendBytes(data, 'TEST');
  }

  /// 설정 화면 "용지 폭 확인" 버튼용 눈금자 출력.
  ///
  /// 폭 설정을 **적용하지 않고** 후보 폭별 막대를 전부 찍는다 — 지금 설정이 틀려서
  /// 확인하는 것이므로 그 값으로 레이아웃을 잡으면 진단이 안 된다.
  Future<bool> printWidthRuler() async {
    final data = await ReceiptEscPosBuilder.buildWidthRulerBytes(
      currentColumns: columnsOf(PreferenceService()),
    );
    return _sendBytes(data, 'RULER');
  }

  static String _usbPrintPortLabel(String? devicePath) {
    if (devicePath == null || devicePath.isEmpty) return 'USB (미선택)';
    final ids = parseUsbIdsFromDevicePath(devicePath);
    final vid = ids.vendorId;
    final pid = ids.productId;
    if (vid == null || pid == null) return 'USB';
    String hex4(int v) => v.toRadixString(16).toUpperCase().padLeft(4, '0');
    return 'USB ${hex4(vid)}:${hex4(pid)}';
  }

  /// 기기 호출(DEVICE_CALL_REQUESTED) 알림 슬립 출력. Windows / Android 동일.
  Future<bool> printDeviceCall({
    required String deviceId,
    required String dateTime,
    required String phrase,
  }) async {
    final data = await ReceiptEscPosBuilder.buildDeviceCallBytes(
      deviceId: deviceId,
      dateTime: dateTime,
      phrase: phrase,
      width: columnsOf(PreferenceService()),
    );
    return _sendBytes(data, '기기호출_$deviceId');
  }

  /// (Android) UsbReceiptPrinter 의 bulkOut endpoint 확보 여부.
  /// Windows 는 COM 포트 enumerate / Winspool default 가용성으로 판단.
  Future<bool> isConnected() async {
    if (Platform.isAndroid) {
      try {
        final ok =
            await platform.invokeMethod<bool>('isExternalPrinterConnected');
        return ok == true;
      } catch (e, s) {
        logger.w('[ExternalReceiptPrinter] isExternalPrinterConnected 실패',
            error: e, stackTrace: s);
        return false;
      }
    }
    if (Platform.isWindows) {
      await _ensureWinTransport();
      return await win_transport.isConnected();
    }
    return false;
  }

  /// (Android) 연결된 외부 영수증 프린터의 USB VID/PID. 못 찾으면 null.
  ///
  /// 기종별 용지 폭 프리시드용이다 — ESC/POS 에 컬럼 수 질의가 없어서
  /// (`GS W` 는 쓰기 전용) VID/PID 로 알려진 기종을 가려내는 것이 유일하게
  /// 자동화 가능한 경로다. Windows 는 usbprint 장치 경로 / COM 포트의 SetupAPI
  /// `SPDRP_HARDWAREID` 에서 같은 값을 얻는다.
  ///
  /// 반환 형식은 Windows 쪽과 맞춰 `'VID:PID'` 대문자 16진수 문자열이라
  /// `knownColumnsForDeviceString` 에 그대로 넣을 수 있다.
  Future<String?> connectedUsbIdString() async {
    if (!Platform.isAndroid) return null;
    try {
      final ids =
          await platform.invokeMapMethod<String, dynamic>('getExternalPrinterIds');
      if (ids == null) return null;
      final vid = (ids['vendorId'] as num?)?.toInt();
      final pid = (ids['productId'] as num?)?.toInt();
      final key = usbIdKey(vendorId: vid, productId: pid);
      // knownColumnsForDeviceString 은 'vid_xxxx&pid_xxxx' 패턴을 찾으므로
      // 그 형태로 감싸서 돌려준다 (Windows 장치 문자열과 같은 파서를 쓰기 위함).
      if (key == null) return null;
      final parts = key.split(':');
      return 'vid_${parts[0]}&pid_${parts[1]}';
    } catch (e) {
      logger.w('[ExternalReceiptPrinter] getExternalPrinterIds 실패: $e');
      return null;
    }
  }

  /// (Android) UsbReceiptPrinter.discover() 재호출 — 권한 dialog 표시 / 재오픈.
  /// Windows 는 no-op (COM enumerate 는 매 출력 시점에 갱신).
  Future<void> reconnect() async {
    if (!Platform.isAndroid) return;
    try {
      await platform.invokeMethod('reconnectExternalPrinter');
    } on PlatformException catch (e, s) {
      logger.e('[ExternalReceiptPrinter] reconnectExternalPrinter 실패',
          error: e, stackTrace: s);
    }
  }

  // ---- internals ------------------------------------------------------

  Future<bool> _sendBytes(Uint8List data, String jobName) async {
    if (!Platform.isAndroid && !Platform.isWindows) {
      logger.w('[ExternalReceiptPrinter] 지원하지 않는 플랫폼 — 출력 생략');
      return false;
    }
    // 직접 transport 호출 대신 PrinterJobQueue 경유.
    // 큐가 직렬화 + 3회 backoff 재시도 + 최종 실패 시 onFinalFailure 콜백을 책임진다.
    // 플랫폼별 transport(Android: AndroidUsbTransport / Windows: WindowsTransport)
    // 는 [PrintService] 가 앱 시작 시 큐에 주입.
    final job = PrinterJob(
      bytes: data,
      jobName: jobName,
      kind: jobName.startsWith('영수증')
          ? 'receipt'
          : (jobName.startsWith('주문서') ? 'order' : 'misc'),
    );
    return PrinterJobQueue.instance.enqueue(job);
  }

  static Future<void> _ensureWinTransport() async {
    if (_winTransportLoaded) return;
    await win_transport.loadLibrary();
    _winTransportLoaded = true;
  }

  String _displayNum(Map<String, dynamic> orderMap) {
    final disp = orderMap['displayOrderNum'];
    if (disp is String && disp.isNotEmpty) return disp;
    final simple = orderMap['ordrSimpleId'];
    if (simple is String && simple.isNotEmpty) return simple;
    return '';
  }

  /// 현재 브랜드([BrandAssets.receiptLogoPath])의 영수증 로고 PNG 바이트를 로드.
  /// 로고가 없는 브랜드(path == null)는 null 반환. lazy-invalidation 캐싱(path 비교)
  /// 으로 번들 재로드는 브랜드당 1회. 외부 영수증 프린터 / Sunmi 내장 프린터가 공유.
  static Future<Uint8List?> loadReceiptLogoBytes() async {
    final String? targetPath = BrandAssets.receiptLogoPath;
    if (_cachedLogoPath != targetPath) {
      // 브랜드 전환(또는 첫 호출) — 캐시 무효화.
      _cachedLogoBytes = null;
      _cachedLogoIsNull = false;
      _cachedLogoPath = targetPath;
    }
    if (targetPath == null) {
      _cachedLogoIsNull = true;
      return null;
    }
    if (_cachedLogoBytes != null) return _cachedLogoBytes;
    if (_cachedLogoIsNull) return null;
    try {
      _cachedLogoBytes =
          (await rootBundle.load(targetPath)).buffer.asUint8List();
      return _cachedLogoBytes;
    } catch (e) {
      logger.w('[ExternalReceiptPrinter] 로고 로드 실패 ($targetPath), 계속 출력: $e');
      _cachedLogoIsNull = true;
      return null;
    }
  }
}
